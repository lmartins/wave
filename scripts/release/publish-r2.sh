#!/usr/bin/env bash
# Publish Wave Direct macOS Sparkle artifacts (DMG + appcast) to Cloudflare R2.
#
# This is the same pattern used for Ayron: versioned artifacts for history +
# a stable "Wave-latest.dmg" + short-TTL appcast.xml that the landing page
# and Sparkle SUFeedURL consume.
#
# Required (via env or wave-release.env):
#   R2_BUCKET, R2_ENDPOINT, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
#
# Usage after build + appcast steps:
#   source scripts/release/load-release-env.sh
#   scripts/release/publish-r2.sh
#   # or with explicit:
#   VERSION=0.5.0 BUILD=12 scripts/release/publish-r2.sh
#
# Requires: aws CLI v2 (brew install awscli)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RELEASE_DIR="$REPO_ROOT/build/release"

VERSION="${VERSION:-}"
BUILD="${BUILD:-}"
R2_BUCKET="${R2_BUCKET:?Set R2_BUCKET (see scripts/release/wave-release.env.example)}"
R2_ENDPOINT="${R2_ENDPOINT:?Set R2_ENDPOINT}"
R2_PREFIX="${R2_PREFIX:-}"

if ! command -v aws >/dev/null 2>&1; then
  echo "ERROR: aws CLI not found. brew install awscli" >&2
  exit 1
fi

if [[ -n "$VERSION" && -n "$BUILD" ]]; then
  VERSION_TAG="$VERSION-$BUILD"
else
  VERSION_TAG="$(find "$RELEASE_DIR" -mindepth 1 -maxdepth 1 -type d -name '[0-9]*-[0-9]*' -print | sort -V | tail -n 1 | xargs basename 2>/dev/null || true)"
fi

DMG="$RELEASE_DIR/$VERSION_TAG/Wave-$VERSION_TAG.dmg"
APPCAST="$RELEASE_DIR/appcast.xml"

if [[ ! -f "$DMG" ]]; then
  echo "ERROR: missing DMG: $DMG" >&2
  exit 1
fi
if [[ ! -f "$APPCAST" ]]; then
  echo "ERROR: missing appcast: $APPCAST" >&2
  exit 1
fi

prefix_path() {
  local key="$1"
  if [[ -n "$R2_PREFIX" ]]; then
    printf '%s/%s' "${R2_PREFIX%/}" "$key"
  else
    printf '%s' "$key"
  fi
}

DMG_KEY="$(prefix_path "downloads/Wave-$VERSION_TAG.dmg")"
LATEST_DMG_KEY="$(prefix_path "downloads/Wave-latest.dmg")"
APPCAST_KEY="$(prefix_path "appcast.xml")"

echo "▶  Uploading to R2 (bucket: $R2_BUCKET)…"

aws --endpoint-url "$R2_ENDPOINT" s3 cp "$DMG" "s3://$R2_BUCKET/$DMG_KEY" \
  --content-type application/octet-stream \
  --cache-control 'public, max-age=31536000, immutable'

# Overwrite the stable latest (short cache so updates propagate quickly to users + landing).
aws --endpoint-url "$R2_ENDPOINT" s3 cp "$DMG" "s3://$R2_BUCKET/$LATEST_DMG_KEY" \
  --content-type application/octet-stream \
  --cache-control 'public, max-age=300'

aws --endpoint-url "$R2_ENDPOINT" s3 cp "$APPCAST" "s3://$R2_BUCKET/$APPCAST_KEY" \
  --content-type application/xml \
  --cache-control 'public, max-age=300'

echo "✅ Published Wave Direct artifacts to R2"
echo "   DMG (versioned): s3://$R2_BUCKET/$DMG_KEY"
echo "   DMG (latest):    s3://$R2_BUCKET/$LATEST_DMG_KEY  →  https://updates.wave.mxv.sh/downloads/Wave-latest.dmg"
echo "   Appcast:         s3://$R2_BUCKET/$APPCAST_KEY     →  https://updates.wave.mxv.sh/appcast.xml"
echo
echo "Update the landing (if it still fetches from GitHub) and verify Sparkle can see the new feed."
