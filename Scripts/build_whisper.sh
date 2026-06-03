#!/usr/bin/env bash
# Rebuild the vendored whisper.cpp static libs (Metal embedded) into Vendor/whisper-install
set -euo pipefail
cd "$(dirname "$0")/.."
cmake -S Vendor/whisper.cpp -B Vendor/whisper-build \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_ACCELERATE=ON \
  -DWHISPER_COREML=ON -DWHISPER_COREML_ALLOW_FALLBACK=ON \
  -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_SERVER=OFF
cmake --build Vendor/whisper-build --config Release -j
cmake --install Vendor/whisper-build --prefix Vendor/whisper-install
cp Vendor/whisper-install/include/*.h Sources/CWhisper/include/
echo "whisper rebuilt -> Vendor/whisper-install"
