#!/usr/bin/env python3
"""Rename a web build's font assets to include a content hash.

A release build tree-shakes Material Icons down to only the codepoints that
build references, then emits the subset at a fixed path --
`assets/fonts/MaterialIcons-Regular.otf`. The bytes change on every build; the
URL never does. A browser that cached the old subset therefore keeps it, and
any icon added since renders blank. Cache headers cannot rescue a browser that
has already cached the file, because it will not ask again -- only a different
URL will.

So each font gets a name derived from its own contents, and FontManifest.json
is rewritten to match. New bytes mean a new URL, which is a guaranteed cache
miss; unchanged bytes keep the same URL and stay cached.

Only fonts that FontManifest.json is the sole reference to are renamed. Package
fonts are also listed in AssetManifest, so renaming those would leave a dangling
entry there pointing at a file that no longer exists; they are skipped. In
practice that means the tree-shaken icon font -- which is the one that changes
per build, and the only one Flutter keeps out of AssetManifest.

Usage: fingerprint_font_assets.py <web-build-dir>
"""

import base64
import hashlib
import json
import pathlib
import sys

HASH_LEN = 8


def asset_manifest_text(web: pathlib.Path) -> str:
    """Everything AssetManifest references, as searchable text.

    Returns "" only if no manifest is present at all -- in which case nothing
    can be checked and nothing is fingerprinted, which is the safe direction.
    """
    parts = []
    for name in ("AssetManifest.bin.json", "AssetManifest.json"):
        p = web / "assets" / name
        if not p.is_file():
            continue
        raw = p.read_text()
        parts.append(raw)
        try:
            payload = json.loads(raw)
            if isinstance(payload, str):
                parts.append(base64.b64decode(payload).decode("utf-8", "ignore"))
        except Exception:
            pass
    return "\n".join(parts)


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(f"usage: {argv[0]} <web-build-dir>", file=sys.stderr)
        return 2

    web = pathlib.Path(argv[1])
    manifest_path = web / "assets" / "FontManifest.json"
    if not manifest_path.is_file():
        print(f"no FontManifest.json under {web}", file=sys.stderr)
        return 1

    manifest = json.loads(manifest_path.read_text())

    referenced_elsewhere = asset_manifest_text(web)
    if not referenced_elsewhere:
        print("no AssetManifest to cross-check against; nothing fingerprinted",
              file=sys.stderr)
        return 1

    renamed = 0

    for family in manifest:
        for font in family.get("fonts", []):
            asset = font.get("asset")
            if not asset:
                continue

            source = web / "assets" / asset
            if not source.is_file():
                # Referenced but not emitted; leave it for the build to fail on.
                print(f"  skip (missing): {asset}")
                continue

            if source.name in referenced_elsewhere:
                # AssetManifest points at this too, and renaming would leave
                # that pointing at nothing.
                print(f"  skip (in AssetManifest): {asset}")
                continue

            digest = hashlib.sha256(source.read_bytes()).hexdigest()[:HASH_LEN]
            if source.stem.endswith(f".{digest}"):
                continue  # already fingerprinted; running twice is a no-op

            target_name = f"{source.stem}.{digest}{source.suffix}"
            source.rename(source.with_name(target_name))
            font["asset"] = str(pathlib.PurePosixPath(asset).with_name(target_name))
            print(f"  {asset} -> {font['asset']}")
            renamed += 1

    manifest_path.write_text(json.dumps(manifest))
    print(f"fingerprinted {renamed} font asset(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
