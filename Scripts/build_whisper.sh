#!/usr/bin/env bash
# Rebuild the vendored whisper.cpp static libs (Metal embedded) into Vendor/whisper-install
set -euo pipefail
cd "$(dirname "$0")/.."

# CPU baseline for the redistributable build. GGML_NATIVE=OFF: never bake the build
# machine's microarch (-mcpu=native picked up M5-only features like +sme) into a
# binary that ships to other Macs. ggml passes this string to -march=, so it must be
# an ISA spec (not a core name like apple-m1). The default is the M1 floor — every
# Apple Silicon Mac has it; the CPU path needs no more (encode runs on Metal/ANE).
# Override for a tuned local/per-arch build, e.g.:
#   TALKTY_GGML_ARCH=armv8.6-a+fp16+dotprod+i8mm Scripts/build_whisper.sh   # M2+
GGML_ARCH="${TALKTY_GGML_ARCH:-armv8.4-a+fp16+dotprod}"

cmake -S Vendor/whisper.cpp -B Vendor/whisper-build \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_ACCELERATE=ON \
  -DWHISPER_COREML=ON -DWHISPER_COREML_ALLOW_FALLBACK=ON \
  -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_SERVER=OFF \
  -DGGML_NATIVE=OFF -DGGML_CPU_ARM_ARCH="${GGML_ARCH}"
cmake --build Vendor/whisper-build --config Release -j
cmake --install Vendor/whisper-build --prefix Vendor/whisper-install
cp Vendor/whisper-install/include/*.h Sources/CWhisper/include/
echo "whisper rebuilt -> Vendor/whisper-install"
