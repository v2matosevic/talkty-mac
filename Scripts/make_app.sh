#!/usr/bin/env bash
# Assemble Talkty.app from the SwiftPM build and ad-hoc code-sign it.
# Usage: Scripts/make_app.sh [debug|release]   (default: release)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
VERSION="$(/usr/bin/plutil -extract version raw version.json 2>/dev/null || echo 1.0.0)"
APP="dist/Talkty.app"
BUNDLE_ID="hr.version2.talkty"

echo "==> Building ($CONFIG)…"
swift build -c "$CONFIG" --product Talkty >/dev/null

echo "==> Assembling $APP (v$VERSION)…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/Talkty" "$APP/Contents/MacOS/Talkty"
[ -f Resources/Talkty.icns ] && cp Resources/Talkty.icns "$APP/Contents/Resources/Talkty.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Talkty</string>
    <key>CFBundleDisplayName</key><string>Talkty</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>Talkty</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>Talkty</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Talkty transcribes your speech to text entirely on your device. Audio never leaves your Mac.</string>
</dict>
</plist>
PLIST

echo "==> Code-signing (ad-hoc)…"
# Ad-hoc signing for personal use. For stable Accessibility/Mic grants across
# rebuilds, replace "-" with a self-signed identity (see Scripts/dev_identity.sh).
SIGN_ID="${TALKTY_SIGN_ID:--}"
codesign --force --deep --sign "$SIGN_ID" "$APP" >/dev/null 2>&1
codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /' || true

echo "==> Done: $APP"
