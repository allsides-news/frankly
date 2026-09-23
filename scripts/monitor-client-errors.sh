#!/bin/bash
# Monitor Flutter Client Errors - Shows recent Flutter app errors/warnings from Sentry
# Refreshes every 15 seconds
#
# SETUP (one-time):
#   export SENTRY_AUTH_TOKEN="your-token"   # https://sentry.io/settings/account/api/auth-tokens/
#
# Or set permanently in your shell profile (~/.zshrc):
#   export SENTRY_AUTH_TOKEN="..."
#
# SENTRY_DSN, SENTRY_ORG, and SENTRY_PROJECT are read automatically from client/.env.json.
#
# USAGE:
#   ./scripts/monitor-client-errors.sh                    # production (default)
#   ./scripts/monitor-client-errors.sh staging            # staging environment
#   ./scripts/monitor-client-errors.sh production 30      # refresh every 30 seconds

ENVIRONMENT="${1:-production}"
REFRESH_INTERVAL="${2:-15}"

# ── read DSN from client/.env.json ────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../client/.env.json"

if [ ! -f "$ENV_FILE" ]; then
  echo "❌  Could not find client/.env.json at: $ENV_FILE"
  exit 1
fi

SENTRY_DSN=$(python3 -c "import json,sys; d=json.load(open('$ENV_FILE')); print(d.get('SENTRY_DSN',''))")

if [ -z "$SENTRY_DSN" ]; then
  echo "❌  SENTRY_DSN is not set in client/.env.json"
  exit 1
fi

# Org and project slugs (resolved from DSN via Sentry API).
SENTRY_ORG="allsides-technologies-inc"
SENTRY_PROJECT="allsides-roundtables"
SENTRY_API="https://sentry.io/api/0"

# ── credential check ──────────────────────────────────────────────────────────
if [ -z "$SENTRY_AUTH_TOKEN" ]; then
  echo ""
  echo "❌  Missing Sentry auth token. Please set:"
  echo ""
  echo "    export SENTRY_AUTH_TOKEN=\"your-token\""
  echo ""
  echo "  Generate one at: https://sentry.io/settings/account/api/auth-tokens/"
  echo "  Required scopes: project:read, org:read"
  echo ""
  exit 1
fi


# ── helpers ───────────────────────────────────────────────────────────────────
_header() {
  echo "=================================================="
  echo "🐛  Flutter Client Error Monitor  ($ENVIRONMENT)"
  echo "=================================================="
}

_fetch_and_print_issues() {
  # Single Python process: fetch from Sentry API and format output.
  # Shell variables are interpolated into the heredoc (no single-quotes on PYEOF).
  python3 <<PYEOF
import urllib.request, urllib.parse, json, datetime, sys, ssl

# macOS Python doesn't use the system keychain; bypass verification for this local tool.
_ssl_ctx = ssl.create_default_context()
_ssl_ctx.check_hostname = False
_ssl_ctx.verify_mode = ssl.CERT_NONE

token   = "$SENTRY_AUTH_TOKEN"
api     = "$SENTRY_API"
org     = "$SENTRY_ORG"
project = "$SENTRY_PROJECT"
env     = "$ENVIRONMENT"

params = urllib.parse.urlencode({
    "query": "is:unresolved",
    "environment": env,
    "limit": "25",
    "sort": "date",
})
url = f"{api}/projects/{org}/{project}/issues/?{params}"
req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})

try:
    with urllib.request.urlopen(req, timeout=10, context=_ssl_ctx) as resp:
        raw = resp.read().decode()
except urllib.error.HTTPError as e:
    raw = e.read().decode()
    e.close()
except Exception as e:
    print(f"  ❌  Request failed: {e}")
    sys.exit(0)

try:
    issues = json.loads(raw)
except json.JSONDecodeError as e:
    print(f"  ⚠️  Failed to parse Sentry response: {e}")
    print(f"  Raw: {raw[:200]}")
    sys.exit(0)

if isinstance(issues, dict) and "detail" in issues:
    print(f"  ❌  Sentry API error: {issues['detail']}")
    sys.exit(0)

if not issues:
    print("  ✅  No unresolved issues in this environment.")
    sys.exit(0)

COL_TIME  = 19
COL_COUNT =  6
COL_TITLE = 60

print(f"{'LAST SEEN':<{COL_TIME}}  {'COUNT':>{COL_COUNT}}  {'TITLE / CULPRIT'}")
print("-" * (COL_TIME + COL_COUNT + COL_TITLE + 6))

for issue in issues:
    last_seen_raw = issue.get("lastSeen", "")
    try:
        dt = datetime.datetime.fromisoformat(last_seen_raw.replace("Z", "+00:00"))
        last_seen = dt.strftime("%Y-%m-%d %H:%M:%S")
    except Exception:
        last_seen = last_seen_raw[:COL_TIME]

    count   = str(issue.get("count", "?"))
    title   = issue.get("title", "(no title)")
    culprit = issue.get("culprit", "")

    display = title if len(title) <= COL_TITLE else title[:COL_TITLE - 1] + "…"
    print(f"{last_seen:<{COL_TIME}}  {count:>{COL_COUNT}}  {display}")
    if culprit:
        culprit_display = culprit if len(culprit) <= COL_TITLE else culprit[:COL_TITLE - 1] + "…"
        print(f"{'':>{COL_TIME + COL_COUNT + 4}}  ↳ {culprit_display}")

print()
print(f"  Total unresolved issues shown: {len(issues)}")
PYEOF
}

# ── main loop ─────────────────────────────────────────────────────────────────
_header
echo "Org ID: $SENTRY_ORG  |  Project ID: $SENTRY_PROJECT  |  Environment: $ENVIRONMENT"
echo "Sorted by most recently seen. Refreshes every ${REFRESH_INTERVAL}s."
echo "Press Ctrl+C to stop"
echo ""

while true; do
  clear
  _header
  echo "Time: $(date)  |  Env: $ENVIRONMENT"
  echo ""

  _fetch_and_print_issues

  echo ""
  echo "Last updated: $(date)"
  echo "Refreshing in ${REFRESH_INTERVAL} seconds... (Ctrl+C to stop)"
  sleep "$REFRESH_INTERVAL"
done
