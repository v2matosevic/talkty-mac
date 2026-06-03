#!/usr/bin/env bash
# Assemble Talkty.app from the SwiftPM build, sign it, and optionally install it.
# Usage: Scripts/make_app.sh [debug|release] [--install]   (default: release)
#   --install  also replace /Applications/Talkty.app with the fresh build
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="release"
INSTALL=0
for a in "$@"; do
    case "$a" in
        debug|release) CONFIG="$a" ;;
        --install) INSTALL=1 ;;
        *) echo "unknown arg: $a" >&2; exit 2 ;;
    esac
done
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

# Prefer a stable self-signed identity (keeps TCC grants across rebuilds — see
# Scripts/dev_identity.sh); fall back to ad-hoc. TALKTY_SIGN_ID overrides both.
TALKTY_KC="$HOME/Library/Keychains/talkty-dev.keychain-db"
if [ -n "${TALKTY_SIGN_ID:-}" ]; then
    SIGN_ID="$TALKTY_SIGN_ID"
elif [ -f "$TALKTY_KC" ] && security find-identity -p codesigning -v "$TALKTY_KC" 2>/dev/null | grep -q "Talkty Dev"; then
    SIGN_ID="Talkty Dev"
    security unlock-keychain -p talkty-dev "$TALKTY_KC" 2>/dev/null || true
    # codesign resolves the identity via the keychain search list — ensure ours is in it.
    if ! security list-keychains -d user | grep -q "talkty-dev.keychain"; then
        security list-keychains -d user -s "$TALKTY_KC" $(security list-keychains -d user | xargs -n1)
    fi
else
    SIGN_ID="-"
fi

echo "==> Code-signing ($([ "$SIGN_ID" = "-" ] && echo ad-hoc || echo "$SIGN_ID"))…"
codesign --force --deep --sign "$SIGN_ID" "$APP" >/dev/null 2>&1
codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /' || true

if [ "$INSTALL" = "1" ]; then
    DEST="/Applications/Talkty.app"
    echo "==> Installing to ${DEST}…"
    rm -rf "${DEST}"
    ditto "$APP" "${DEST}"            # ditto preserves the code signature
    echo "    installed (signature preserved)."
fi

echo "==> Done: $APP"
