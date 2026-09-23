#!/usr/bin/env bash
# Populate path-dependency patches (full upstream trees + repo overlays).
# Git tracks only overlay files under client/patches/* — CI and fresh clones need this before pub get.
# See client/update.sh (interactive) and client/UPGRADE-README.md.

set -euo pipefail

CLIENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${CLIENT_DIR}/.." && pwd)"

AGORA_PATCH_REPO="${AGORA_PATCH_REPO:-https://github.com/berkmancenter/Agora-Flutter-SDK.git}"
# Pin upstream revision so remote force-pushes cannot silently change injected sources (override via AGORA_PATCH_REF).
_ref_file="${CLIENT_DIR}/.agora-patch-ref"
if [[ -f "$_ref_file" ]]; then
  AGORA_PATCH_REF="${AGORA_PATCH_REF:-$(tr -d '[:space:]' < "$_ref_file")}"
fi
AGORA_PATCH_REF="${AGORA_PATCH_REF:-1227b746492a145d9a4869ce98cb2cf77a50d058}"
YOUTUBE_IFRAME_WEB_VERSION="${YOUTUBE_IFRAME_WEB_VERSION:-2.0.2}"
# SHA-256 of the pub.dev youtube_player_iframe_web-{VERSION}.tar.gz archive — update when bumping version.
YOUTUBE_IFRAME_WEB_TARBALL_SHA256="${YOUTUBE_IFRAME_WEB_TARBALL_SHA256:-c7020816031600349b56d2729d4e8be011fcb723ff7dc2dd0cdf72096a0e5ff4}"

YT_PATCH_DIR="${CLIENT_DIR}/patches/youtube_player_iframe_web-${YOUTUBE_IFRAME_WEB_VERSION}"
AGORA_PATCH_DIR="${CLIENT_DIR}/patches/agora_rtc_engine"

file_sha256_hex() {
  local f="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$f" | awk '{print $1}'
  else
    openssl dgst -sha256 "$f" | awk '{print $NF}'
  fi
}

bootstrap_youtube_patch() {
  local url="https://pub.dev/api/archives/youtube_player_iframe_web-${YOUTUBE_IFRAME_WEB_VERSION}.tar.gz"
  echo "==> Fetching youtube_player_iframe_web ${YOUTUBE_IFRAME_WEB_VERSION} from pub.dev..."
  rm -rf "${YT_PATCH_DIR}"
  mkdir -p "${YT_PATCH_DIR}"
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/youtube_player_iframe_web-${YOUTUBE_IFRAME_WEB_VERSION}.XXXXXX.tar.gz")"
  curl -fsSL "$url" -o "$tmp"
  local actual expected
  actual="$(file_sha256_hex "$tmp" | tr '[:upper:]' '[:lower:]')"
  expected="$(echo "${YOUTUBE_IFRAME_WEB_TARBALL_SHA256}" | tr '[:upper:]' '[:lower:]')"
  if [[ "$actual" != "$expected" ]]; then
    echo "ERROR: youtube_player_iframe_web tarball SHA-256 mismatch (got ${actual}, expected ${expected})." >&2
    rm -f "$tmp"
    exit 1
  fi
  tar -xzf "$tmp" -C "${YT_PATCH_DIR}"
  rm -f "$tmp"
}

bootstrap_agora_patch() {
  echo "==> Fetching Agora Flutter SDK (${AGORA_PATCH_REF}) into patches/agora_rtc_engine..."
  rm -rf "${AGORA_PATCH_DIR}"
  mkdir -p "${AGORA_PATCH_DIR}"
  git init "${AGORA_PATCH_DIR}"
  git -C "${AGORA_PATCH_DIR}" remote add origin "${AGORA_PATCH_REPO}"
  git -C "${AGORA_PATCH_DIR}" fetch --depth 1 origin "${AGORA_PATCH_REF}"
  git -C "${AGORA_PATCH_DIR}" checkout -q FETCH_HEAD
}

restore_tracked_overlays() {
  if ! git -C "${REPO_ROOT}" rev-parse --git-dir >/dev/null 2>&1; then
    echo "WARNING: Not a git checkout — ensure overlay files match the repo." >&2
    return 0
  fi
  echo "==> Restoring tracked overlay files under client/patches/..."
  # FORCE_RESTORE_OVERLAYS=1 is set on CI: actions/cache restores vendor trees after checkout,
  # so git diff vs HEAD looks dirty — still checkout overlays so commits apply without bumping cache keys.
  if ! git -C "${REPO_ROOT}" diff --quiet HEAD -- \
      client/patches/agora_rtc_engine \
      "client/patches/youtube_player_iframe_web-${YOUTUBE_IFRAME_WEB_VERSION}"; then
    echo "WARNING: Uncommitted changes in client/patches/ overlay files — skipping checkout to preserve your work." >&2
    echo "         Re-run with FORCE_RESTORE_OVERLAYS=1 to overwrite." >&2
    if [[ -z "${FORCE_RESTORE_OVERLAYS:-}" ]]; then
      return 0
    fi
  fi
  git -C "${REPO_ROOT}" checkout HEAD -- \
    client/patches/agora_rtc_engine \
    "client/patches/youtube_player_iframe_web-${YOUTUBE_IFRAME_WEB_VERSION}"
}

NEED_YT=
NEED_AGORA=
if [[ ! -f "${YT_PATCH_DIR}/lib/src/web_youtube_player_iframe_platform.dart" ]]; then
  NEED_YT=1
fi
if [[ ! -f "${AGORA_PATCH_DIR}/lib/agora_rtc_engine.dart" ]]; then
  NEED_AGORA=1
fi

if [[ -n "${NEED_YT}" ]]; then
  bootstrap_youtube_patch
fi
if [[ -n "${NEED_AGORA}" ]]; then
  bootstrap_agora_patch
fi

restore_tracked_overlays

if [[ ! -f "${YT_PATCH_DIR}/lib/src/web_youtube_player_iframe_platform.dart" ]] ||
  [[ ! -f "${AGORA_PATCH_DIR}/lib/agora_rtc_engine.dart" ]]; then
  echo "ERROR: Patched packages still incomplete after bootstrap." >&2
  echo "  Expected: ${YT_PATCH_DIR}/lib/src/web_youtube_player_iframe_platform.dart" >&2
  echo "  Expected: ${AGORA_PATCH_DIR}/lib/agora_rtc_engine.dart" >&2
  exit 1
fi

echo "==> Patched packages ready."
