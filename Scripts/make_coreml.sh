#!/usr/bin/env bash
# Generate a Core ML encoder for a Whisper model and install it next to the .bin,
# so whisper.cpp runs the encode pass on the Apple Neural Engine (lower power than
# Metal-only). Needs NO Xcode — coremltools compiles the .mlmodelc itself; torch +
# coremltools are pulled on demand via uv (Python 3.11). whisper.cpp falls back to
# Metal automatically if the encoder isn't present, so this is purely opt-in.
#
# Usage: Scripts/make_coreml.sh <model>     e.g. base.en, large-v3-turbo, large-v3
set -euo pipefail
cd "$(dirname "$0")/.."

MODEL="${1:?usage: Scripts/make_coreml.sh <model>  (e.g. base.en)}"
WHISPER="$PWD/Vendor/whisper.cpp"
OUT="$HOME/Library/Application Support/Talkty/Models/ggml-${MODEL}-encoder.mlmodelc"

[ -d "$WHISPER/models" ] || { echo "vendored whisper.cpp missing — run Scripts/bootstrap.sh" >&2; exit 1; }

echo "==> Generating Core ML encoder for '$MODEL' (first run pulls torch/coremltools)…"
cd "$WHISPER"
OUT="$OUT" MODEL="$MODEL" uv run --python 3.11 \
    --with torch --with coremltools --with openai-whisper --with ane_transformers --with "numpy<2" \
    python - <<'PY'
import os, sys, subprocess, shutil, coremltools as ct
model = os.environ["MODEL"]; out = os.environ["OUT"]
# 1) torch → Core ML .mlpackage (encoder only, ANE-optimized) via whisper.cpp's converter
subprocess.run([sys.executable, "models/convert-whisper-to-coreml.py",
                "--model", model, "--encoder-only", "True", "--optimize-ane", "True"], check=True)
# 2) compile .mlpackage → .mlmodelc WITHOUT Xcode's coremlc
pkg = f"models/coreml-encoder-{model}.mlpackage"
compiled = ct.utils.compile_model(pkg)          # returns a path to a compiled .mlmodelc
shutil.rmtree(out, ignore_errors=True)
shutil.copytree(compiled, out)
print("installed:", out)
PY
echo "==> Done. whisper.cpp will use the ANE encoder for '$MODEL' on next load."
