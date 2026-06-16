#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# update-appcast.sh — Run Sparkle's generate_appcast against build/release/
# to produce a signed appcast.xml, then rewrite the enclosure to the stable
# Wave-latest.dmg URL (exactly as done for Ayron).
#
# The generated appcast + the DMG (both versioned and latest) are then published
# to Cloudflare R2 so that:
#   - SUFeedURL (in Info-Direct or Config/Info) points at
#     https://updates.wave.mxv.sh/appcast.xml
#   - Sparkle downloads use the stable latest URL (cache-busted on each release
#     by the short TTL on the latest object).
#
# See Ayron's scripts/release/update-appcast.sh for the original + detailed
# one-time Sparkle key generation instructions.
#
# Requirements:
#   - generate_appcast on PATH or SPARKLE_BIN=/path/to/Sparkle/bin
#   - Private EdDSA key already in the Keychain (from generate_keys once).
#   - Run after a successful build-dmg.sh .
#
# Output: build/release/appcast.xml (copy of the one from the version dir)
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RELEASE_DIR="$REPO_ROOT/build/release"

APPCAST_BASE_URL="${APPCAST_BASE_URL:-https://updates.wave.mxv.sh}"
APPCAST_DMG_URL="${APPCAST_DMG_URL:-$APPCAST_BASE_URL/downloads/Wave-latest.dmg}"

# Locate generate_appcast (same logic as Ayron + current wave Makefile).
if [[ -n "${SPARKLE_BIN:-}" && -x "$SPARKLE_BIN/generate_appcast" ]]; then
    GENERATE_APPCAST="$SPARKLE_BIN/generate_appcast"
elif command -v generate_appcast >/dev/null 2>&1; then
    GENERATE_APPCAST="$(command -v generate_appcast)"
else
    cat >&2 <<'EOF'
ERROR: generate_appcast not found.

Set SPARKLE_BIN to the directory containing it, e.g.:
    export SPARKLE_BIN=~/Tools/Sparkle/bin

Or install Sparkle tools / build the project in Xcode once so the
derived data copy is found, or put Sparkle's bin/ on your PATH.
EOF
    exit 1
fi

if [[ ! -d "$RELEASE_DIR" ]]; then
    echo "ERROR: $RELEASE_DIR does not exist. Run scripts/release/build-dmg.sh first." >&2
    exit 1
fi

if [[ -n "${VERSION:-}" && -n "${BUILD:-}" ]]; then
    APPCAST_SOURCE_DIR="$RELEASE_DIR/$VERSION-$BUILD"
else
    APPCAST_SOURCE_DIR="$(find "$RELEASE_DIR" -mindepth 1 -maxdepth 1 -type d -name '[0-9]*-[0-9]*' -print | sort -V | tail -n 1)"
fi

if [[ -z "${APPCAST_SOURCE_DIR:-}" || ! -d "$APPCAST_SOURCE_DIR" ]]; then
    echo "ERROR: no release version directory in $RELEASE_DIR. Run build-dmg.sh first." >&2
    exit 1
fi

if ! find "$APPCAST_SOURCE_DIR" -maxdepth 1 -name 'Wave-*.dmg' -print -quit | grep -q .; then
    echo "ERROR: no Wave DMG found in $APPCAST_SOURCE_DIR." >&2
    exit 1
fi

echo "▶  Running generate_appcast against ${APPCAST_SOURCE_DIR}…"
"$GENERATE_APPCAST" \
    --download-url-prefix "$APPCAST_BASE_URL/downloads/" \
    "$APPCAST_SOURCE_DIR"

APPCAST="$RELEASE_DIR/appcast.xml"
GENERATED_APPCAST="$APPCAST_SOURCE_DIR/appcast.xml"
if [[ ! -f "$GENERATED_APPCAST" ]]; then
    echo "ERROR: generate_appcast did not produce $GENERATED_APPCAST" >&2
    exit 1
fi
cp "$GENERATED_APPCAST" "$APPCAST"

# Rewrite the first enclosure to the stable latest.dmg (R2 will serve the
# bytes of the newest release under that name; signature/length remain valid).
python3 - "$APPCAST" "$APPCAST_DMG_URL" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
stable_url = sys.argv[2]
xml = path.read_text()
xml, count = re.subn(r'url="[^"]*/downloads/Wave-[^"]+\.dmg"', f'url="{stable_url}"', xml, count=1)
if count != 1:
    raise SystemExit(f"ERROR: expected exactly one DMG enclosure URL to rewrite in {path}")
path.write_text(xml)
PY

echo
echo "✅  Appcast updated → $APPCAST"
echo
echo "Upload / publish checklist:"
echo "  - $APPCAST                              → $APPCAST_BASE_URL/appcast.xml"
echo "  - $RELEASE_DIR/<ver>/Wave-*.dmg         → $APPCAST_DMG_URL (and versioned)"
echo
echo "Sparkle clients will pick up the new item on next check."
