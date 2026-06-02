#!/usr/bin/env bash
# Build Resources/Talkty.icns from a 1024px source PNG (rendered via `Talkty --render`).
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${1:-/tmp/talkty-previews/icon_1024.png}"
[ -f "$SRC" ] || { echo "source not found: $SRC (run: .build/debug/Talkty --render /tmp/talkty-previews)"; exit 1; }

mkdir -p Resources
ICONSET="$(mktemp -d)/Talkty.iconset"
mkdir -p "$ICONSET"

for size in 16 32 128 256 512; do
  sips -z $size $size       "$SRC" --out "$ICONSET/icon_${size}x${size}.png"   >/dev/null
  sips -z $((size*2)) $((size*2)) "$SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o Resources/Talkty.icns
echo "wrote Resources/Talkty.icns"
