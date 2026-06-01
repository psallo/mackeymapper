#!/usr/bin/env bash
# build_dmg.sh — Builds and packages MacLauncherRemote.dmg for distribution
# Usage: ./Scripts/build_dmg.sh [--sign "Developer ID Application: Your Name (TEAMID)"]
#
# Prerequisites:
#   brew install create-dmg
#   Xcode with Developer ID certificate in Keychain

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
APP_NAME="MacLauncherRemote"
SCHEME="MacLauncherRemote"
BUILD_DIR="$PROJECT_ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
DMG_OUTPUT="$PROJECT_ROOT/$APP_NAME.dmg"

# Parse args
SIGN_IDENTITY=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sign) SIGN_IDENTITY="$2"; shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

echo "==> Building $APP_NAME…"
mkdir -p "$BUILD_DIR"

# Archive
xcodebuild archive \
    -project "$PROJECT_ROOT/MacLauncherRemote.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_STYLE=Manual \
    ${SIGN_IDENTITY:+CODE_SIGN_IDENTITY="$SIGN_IDENTITY"} \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    | xcpretty 2>/dev/null || true

# Export
cat > "$BUILD_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>manual</string>
    ${SIGN_IDENTITY:+<key>signingCertificate</key><string>$SIGN_IDENTITY</string>}
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    -exportPath "$EXPORT_PATH"

APP_PATH="$EXPORT_PATH/$APP_NAME.app"
echo "==> App exported to: $APP_PATH"

# Notarize (requires Apple ID credentials in keychain as 'notarytool-password')
if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "==> Notarizing…"
    xcrun notarytool submit "$APP_PATH" \
        --keychain-profile "notarytool-password" \
        --wait || echo "WARN: Notarization failed or not configured."
    xcrun stapler staple "$APP_PATH" || true
fi

# Create DMG
if command -v create-dmg &>/dev/null; then
    echo "==> Creating DMG…"
    create-dmg \
        --volname "$APP_NAME" \
        --volicon "$APP_PATH/Contents/Resources/AppIcon.icns" \
        --window-pos 200 120 \
        --window-size 660 400 \
        --icon-size 128 \
        --icon "$APP_NAME.app" 180 170 \
        --hide-extension "$APP_NAME.app" \
        --app-drop-link 480 170 \
        "$DMG_OUTPUT" \
        "$APP_PATH"
    echo "==> DMG created: $DMG_OUTPUT"
else
    echo "WARN: create-dmg not found. Install with: brew install create-dmg"
    echo "      Packaging as plain zip instead."
    ditto -c -k --keepParent "$APP_PATH" "$BUILD_DIR/$APP_NAME.zip"
    echo "==> ZIP created: $BUILD_DIR/$APP_NAME.zip"
fi

echo "Done."
