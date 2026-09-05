#!/usr/bin/env bash
# Build Talkty.app and package it into a drag-to-Applications DMG for release.
# Usage: Scripts/make_dmg.sh [debug|release] [--no-build]   (default: release)
#   --no-build  package the existing dist/Talkty.app as-is (e.g. after a CI re-sign)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="release"
NO_BUILD=0
for a in "$@"; do
    case "$a" in
        debug|release) CONFIG="$a" ;;
        --no-build) NO_BUILD=1 ;;
        *) echo "unknown arg: $a" >&2; exit 2 ;;
    esac
done
# Version: TALKTY_VERSION env > the exact git tag on HEAD (v1.5.0 → 1.5.0) > version.json.
# version.json doubles as the UPDATE FEED read from main, so it is bumped only after a
# release is published; tagging first lets the Release workflow stamp the right number.
if [ -n "${TALKTY_VERSION:-}" ]; then
    VERSION="$TALKTY_VERSION"
elif TAG="$(git describe --tags --exact-match 2>/dev/null)" && [ -n "$TAG" ]; then
    VERSION="${TAG#v}"
else
    VERSION="$(/usr/bin/plutil -extract version raw version.json 2>/dev/null || echo 1.0.0)"
fi
APP="dist/Talkty.app"
DMG="dist/Talkty-${VERSION}.dmg"

# Build + sign the app first (no --install — that's for local installs).
[ "$NO_BUILD" = "1" ] || TALKTY_VERSION="$VERSION" Scripts/make_app.sh "$CONFIG"

echo "==> Staging DMG contents…"
STAGE="$(mktemp -d)/Talkty"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Talkty.app"          # ditto preserves the code signature
ln -s /Applications "$STAGE/Applications"  # drag-to-install target

echo "==> Building ${DMG}…"
rm -f "$DMG"
hdiutil create -volname "Talkty" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$(dirname "$STAGE")"

SIZE="$(/usr/bin/du -h "$DMG" | cut -f1 | tr -d ' ')"
echo "==> Done: $DMG ($SIZE)"
