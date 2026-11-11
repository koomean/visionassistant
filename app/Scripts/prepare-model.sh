#!/bin/zsh
set -euo pipefail
APP_ROOT="${0:A:h:h}"
cd "$APP_ROOT"
SOURCE_MODEL="${1:-$APP_ROOT/../Original Model/Qwen3-VL-2B-Instruct}"
TARGET_MODEL="$APP_ROOT/Models/Qwen3-VL-2B-Instruct-4bit"
if [[ ! -f "$SOURCE_MODEL/model.safetensors" ]]; then
  print -u2 "Missing source model: $SOURCE_MODEL/model.safetensors"
  exit 1
fi
command -v uv >/dev/null || { print -u2 'Install uv: brew install uv'; exit 1; }
if [[ ! -x .venv/bin/python ]]; then uv venv --python 3.11 .venv; fi
uv pip install --python .venv/bin/python -r requirements-model.lock.txt
if [[ -f "$TARGET_MODEL/model.safetensors" ]]; then
  print "Converted model already exists: $TARGET_MODEL"
else
  HF_HUB_OFFLINE=1 .venv/bin/python -m mlx_vlm convert \
    --hf-path "$SOURCE_MODEL" --mlx-path "$TARGET_MODEL" \
    --quantize --q-bits 4 --q-group-size 64 --dtype float16
fi
.venv/bin/python Scripts/verify-model.py "$TARGET_MODEL"
print 'Model ready. Open LunaV.xcodeproj and build for your iPhone.'
