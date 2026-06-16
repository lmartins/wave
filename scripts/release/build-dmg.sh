#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# build-dmg.sh — Build, notarize, and package the Direct (self-distribution)
# build of Wave into a DMG ready to upload to updates.wave.mxv.sh (via R2).
#
# This follows the same pattern we used for Ayron (see that project's
# scripts/release/build-dmg.sh for the full reference implementation and
# one-time setup notes).
#
# Pipeline (high level):
#   1. xcodebuild archive (Release config; or Direct if/when a dedicated
#      config/scheme is added for separate Info-Direct.plist + entitlements).
#   2. xcodebuild -exportArchive (development method as workaround).
#   3. Manual re-sign with Developer ID Application, hardened runtime,
#      appropriate entitlements (sandbox must be OFF for Sparkle privileged
#      updates; see Ayron script for the entitlement stripping logic).
#   4. Notarize + staple the .app
#   5. Assemble DMG (create-dmg preferred for UX, fallback hdiutil)
#   6. Sign + notarize + staple the DMG.
#
# One-time setup (release machine):
#   - brew install create-dmg
#   - xcrun notarytool store-credentials "wave-notary" --apple-id ... --team-id ... 
#     (or use keychain key)
#   - Developer ID provisioning profile for self-distribution.
#   - Sparkle EdDSA private key in Keychain (see update-appcast.sh).
#   - The public key goes into Config/Info.plist (and/or Info-Direct) as SUPublicEDKey.
#
# Usage:
#   scripts/release/build-dmg.sh
#   scripts/release/build-dmg.sh 0.5.0 12     # override version/build
#
# Outputs under build/release/<version>-<build>/Wave-....dmg
# Also updates build/release/appcast.xml later via the appcast step.
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

# ── Config (adapt if adding a true "Direct" scheme/config later) ──────────────
SCHEME="${SCHEME:-Wave}"
CONFIGURATION="${CONFIGURATION:-Release}"
PROJECT="Wave.xcodeproj"
EXPORT_OPTIONS="$REPO_ROOT/ExportOptions-Direct.plist"
# Prefer Info-Direct if present for dedicated SUFeedURL etc.; fallback to main.
if [[ -f "$REPO_ROOT/Config/Info-Direct.plist" ]]; then
  INFO_PLIST="$REPO_ROOT/Config/Info-Direct.plist"
else
  INFO_PLIST="$REPO_ROOT/Config/Info.plist"
fi

NOTARY_PROFILE="${NOTARY_PROFILE:-wave-notary}"
TEAM_ID="${TEAM_ID:-996Y4MJA7D}"   # from Signing.xcconfig / Local
DEVELOPER_ID_PROFILE_NAME="${DEVELOPER_ID_PROFILE_NAME:-Wave Self Distribution}"

# Version from plist (or CLI args)
MARKETING_VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST" 2>/dev/null || echo "0.0.0")}"
BUILD_NUMBER="${2:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST" 2>/dev/null || echo "1")}"
VERSION_TAG="${MARKETING_VERSION}-${BUILD_NUMBER}"

OUT_DIR="$REPO_ROOT/build/release/$VERSION_TAG"
ARCHIVE_PATH="$OUT_DIR/Wave.xcarchive"
EXPORT_PATH="$OUT_DIR/export"
APP_PATH="$EXPORT_PATH/Wave.app"
DMG_STAGING="$OUT_DIR/dmg-staging"
DMG_PATH="$OUT_DIR/Wave-$VERSION_TAG.dmg"

mkdir -p "$OUT_DIR"

echo "▶  Releasing Wave $VERSION_TAG (configuration: $CONFIGURATION)"
echo "   Output: $OUT_DIR"
echo "   Using Info: $INFO_PLIST"

# ── 1. Archive ────────────────────────────────────────────────────────────────
echo "▶  Archiving…"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    archive | xcpretty 2>/dev/null || xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    archive

# ── 2. Export (development method as base) ────────────────────────────────────
echo "▶  Exporting .app…"
rm -rf "$EXPORT_PATH"
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS"

if [[ ! -d "$APP_PATH" ]]; then
    echo "ERROR: expected exported app at $APP_PATH" >&2
    exit 1
fi

# ── 3. Re-sign with Developer ID (the Ayron workaround pattern) ───────────────
echo "▶  Re-signing with Developer ID (preserving/trimming entitlements)…"

APP_ENTITLEMENTS="$(mktemp /tmp/wave-app-entitlements.XXXXXX)"
codesign -d --entitlements :- "$APP_PATH" > "$APP_ENTITLEMENTS" 2>/dev/null || true

delete_entitlement() {
    local key="$1"
    if /usr/libexec/PlistBuddy -c "Print :$key" "$APP_ENTITLEMENTS" >/dev/null 2>&1; then
        /usr/libexec/PlistBuddy -c "Delete :$key" "$APP_ENTITLEMENTS"
    fi
}

# Sandbox must be absent for Sparkle's privileged update installer flow.
delete_entitlement 'com.apple.security.app-sandbox'
delete_entitlement 'com.apple.security.temporary-exception.mach-lookup.global-name'
# Apple Sign In may or may not be wanted in direct builds; strip if the
# provisioning profile for Developer ID self-dist doesn't carry it.
delete_entitlement 'com.apple.developer.applesignin'

# Locate a matching Developer ID provisioning profile (name match).
DEVELOPER_ID_PROFILE=""
while IFS= read -r profile; do
    profile_name="$(security cms -D -i "$profile" 2>/dev/null | plutil -extract Name raw -o - - 2>/dev/null || true)"
    if [[ "$profile_name" == "$DEVELOPER_ID_PROFILE_NAME" ]]; then
        DEVELOPER_ID_PROFILE="$profile"
        break
    fi
done < <(find "$HOME/Library/MobileDevice/Provisioning Profiles" -maxdepth 1 -name '*.provisionprofile' -print 2>/dev/null)

if [[ -z "$DEVELOPER_ID_PROFILE" ]]; then
    echo "WARN: Developer ID provisioning profile '$DEVELOPER_ID_PROFILE_NAME' not found; continuing with ad-hoc style Developer ID Application identity only." >&2
fi

if [[ -n "$DEVELOPER_ID_PROFILE" ]]; then
    cp "$DEVELOPER_ID_PROFILE" "$APP_PATH/Contents/embedded.provisionprofile"
fi

xattr -cr "$APP_PATH" 2>/dev/null || true

# Minimal XPC entitlements for Sparkle components (empty is fine).
cat > /tmp/sparkle-xpc-wave.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
EOF

# Sign frameworks (including the embedded whisper.xcframework and Sparkle).
# Sparkle bits get special treatment.
while IFS= read -r framework; do
    executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$framework/Resources/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$framework/Info.plist" 2>/dev/null || basename "$framework" .framework)"
    executable_path="$framework/$executable_name"
    if [[ -f "$executable_path" ]]; then
        codesign --force --sign "Developer ID Application" --options runtime --timestamp "$executable_path" || true
    fi
    codesign --force --sign "Developer ID Application" --options runtime --timestamp "$framework" || true
done < <(find "$APP_PATH/Contents/Frameworks" -maxdepth 1 -type d -name '*.framework' -print 2>/dev/null)

# Sparkle specific (if bundled).
if [[ -d "$APP_PATH/Contents/Frameworks/Sparkle.framework" ]]; then
    FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B"
    codesign --force --sign "Developer ID Application" --options runtime --timestamp "$FRAMEWORK/Autoupdate" || true
    codesign --force --sign "Developer ID Application" --options runtime --timestamp "$FRAMEWORK/Sparkle" || true
    codesign --force --sign "Developer ID Application" --options runtime --timestamp "$FRAMEWORK/Updater.app" || true
    codesign --force --sign "Developer ID Application" --options runtime --timestamp --entitlements /tmp/sparkle-xpc-wave.plist "$FRAMEWORK/XPCServices/Downloader.xpc" || true
    codesign --force --sign "Developer ID Application" --options runtime --timestamp --entitlements /tmp/sparkle-xpc-wave.plist "$FRAMEWORK/XPCServices/Installer.xpc" || true
    codesign --force --sign "Developer ID Application" --options runtime --timestamp "$APP_PATH/Contents/Frameworks/Sparkle.framework" || true
fi

# Also sign the whisper xcframework if present at root Frameworks.
if [[ -d "$APP_PATH/Contents/Frameworks/whisper.xcframework" ]]; then
    codesign --force --sign "Developer ID Application" --options runtime --timestamp "$APP_PATH/Contents/Frameworks/whisper.xcframework" || true
fi

# Final app sign with the (possibly trimmed) entitlements.
codesign --force --sign "Developer ID Application" --options runtime --timestamp --entitlements "$APP_ENTITLEMENTS" "$APP_PATH" || \
codesign --force --sign "Developer ID Application" --options runtime --timestamp "$APP_PATH"

echo "▶  Verifying signature & hardened runtime…"
codesign --verify --deep --strict --verbose=2 "$APP_PATH" || true

# ── 4. Notarize the .app ──────────────────────────────────────────────────────
echo "▶  Submitting .app for notarization…"
APP_ZIP="$OUT_DIR/Wave-$VERSION_TAG-app.zip"
ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"
xcrun notarytool submit "$APP_ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
rm -f "$APP_ZIP"

echo "▶  Stapling notarization ticket to .app…"
xcrun stapler staple "$APP_PATH" || true
xcrun stapler validate "$APP_PATH" || true

# ── 5. Build DMG ──────────────────────────────────────────────────────────────
echo "▶  Building DMG…"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
ditto --noextattr --noqtn "$APP_PATH" "$DMG_STAGING/Wave.app"
ln -s /Applications "$DMG_STAGING/Applications"

if command -v create-dmg >/dev/null 2>&1; then
    create-dmg \
        --volname "Wave $MARKETING_VERSION" \
        --window-pos 200 120 \
        --window-size 640 360 \
        --icon-size 96 \
        --icon "Wave.app" 180 170 \
        --hide-extension "Wave.app" \
        --app-drop-link 460 170 \
        "$DMG_PATH" \
        "$DMG_STAGING/" || {
            echo "WARN: create-dmg failed; falling back to hdiutil." >&2
            rm -f "$DMG_PATH"
            hdiutil create -volname "Wave $MARKETING_VERSION" \
                -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"
        }
else
    hdiutil create -volname "Wave $MARKETING_VERSION" \
        -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"
fi

xattr -c "$DMG_PATH" 2>/dev/null || true

echo "▶  Signing DMG…"
codesign --sign "Developer ID Application" --timestamp "$DMG_PATH"

# ── 6. Notarize + staple DMG ──────────────────────────────────────────────────
echo "▶  Submitting DMG for notarization…"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "▶  Stapling DMG…"
xcrun stapler staple "$DMG_PATH" || true
xcrun stapler validate "$DMG_PATH" || true

DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo
echo "✅  Released Wave $VERSION_TAG"
echo "   DMG:  $DMG_PATH  ($DMG_SIZE)"
echo
echo "Next steps:"
echo "  1. Run scripts/release/update-appcast.sh"
echo "  2. source scripts/release/load-release-env.sh && scripts/release/publish-r2.sh"
echo "  3. (Optional) update landing download links / deploy site"
echo "  4. git tag v$MARKETING_VERSION-$BUILD_NUMBER (or use release-it)"
