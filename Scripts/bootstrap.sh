#!/usr/bin/env bash
# Bootstrap the native build: vendor whisper.cpp at a pinned commit and build the
# Metal-enabled static libs. Keeps the repo lean (Vendor/ is gitignored).
set -euo pipefail
cd "$(dirname "$0")/.."

WHISPER_COMMIT="610e664ba7cfe3af46125ed1b5a1184fccb51bcd"   # ggml-org/whisper.cpp, ggml 0.13.1
WHISPER_DIR="Vendor/whisper.cpp"

if ! command -v cmake >/dev/null 2>&1; then
  echo "cmake is required (brew install cmake)"; exit 1
fi

mkdir -p Vendor
if [ ! -d "$WHISPER_DIR/.git" ]; then
  echo "==> Cloning whisper.cpp @ $WHISPER_COMMIT"
  git clone https://github.com/ggml-org/whisper.cpp "$WHISPER_DIR"
fi
git -C "$WHISPER_DIR" fetch --depth 1 origin "$WHISPER_COMMIT" 2>/dev/null || true
git -C "$WHISPER_DIR" checkout -q "$WHISPER_COMMIT" 2>/dev/null || \
  echo "    (using existing checkout $(git -C "$WHISPER_DIR" rev-parse --short HEAD))"

exec "$(dirname "$0")/build_whisper.sh"
