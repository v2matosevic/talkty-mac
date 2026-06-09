#!/usr/bin/env bash
# Rebuild the vendored whisper.cpp static libs (Metal embedded) into Vendor/whisper-install
set -euo pipefail
cd "$(dirname "$0")/.."
cmake -S Vendor/whisper.cpp -B Vendor/whisper-build \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_ACCELERATE=ON \
  -DWHISPER_COREML=ON -DWHISPER_COREML_ALLOW_FALLBACK=ON \
  -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_SERVER=OFF \
  -DGGML_NATIVE=OFF -DGGML_CPU_ARM_ARCH=armv8.4-a+fp16+dotprod
  # GGML_NATIVE=OFF: never bake the build machine's microarch (-mcpu=native picked up
  # M5-only features like +sme) into a redistributable binary. ggml passes this string
  # to -march=, so it must be an ISA spec (not a core name like apple-m1). armv8.4-a
  # +fp16+dotprod is the M1 floor — every Apple Silicon Mac has it, none need more
  # ISA than this on the CPU path (encode runs on Metal/ANE anyway); no i8mm/sme.
cmake --build Vendor/whisper-build --config Release -j
cmake --install Vendor/whisper-build --prefix Vendor/whisper-install
cp Vendor/whisper-install/include/*.h Sources/CWhisper/include/
echo "whisper rebuilt -> Vendor/whisper-install"
