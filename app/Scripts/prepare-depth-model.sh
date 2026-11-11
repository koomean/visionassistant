#!/bin/zsh
# Build-time network access only. The app consumes a compiled bundled model.
set -euo pipefail
APP_ROOT="${0:A:h:h}"
cd "$APP_ROOT"
MODEL_REVISION=4010e39f3634a45bc60553321fb49fb760bd594e
SOURCE_REVISION=3d835ec1a5802d64a8b8b15f817a1ab54809bfe4
EXPORT_ROOT="$APP_ROOT/Tools/DepthAnything3Export"
PYTHON="$APP_ROOT/Tools/.venv-depth/bin/python"
command -v uv >/dev/null || { print -u2 'Install uv first.'; exit 1; }
HF_CLI="$(command -v hf || true)"
if [[ -z "$HF_CLI" && -x "$HOME/.local/bin/hf" ]]; then HF_CLI="$HOME/.local/bin/hf"; fi
[[ -n "$HF_CLI" ]] || { print -u2 'Install the Hugging Face hf CLI first.'; exit 1; }
if [[ ! -x "$PYTHON" ]]; then
  uv venv --python 3.11 "$APP_ROOT/Tools/.venv-depth"
fi
uv pip install --python "$PYTHON" -r "$EXPORT_ROOT/requirements.resolved.txt"
if [[ ! -f "$EXPORT_ROOT/upstream/src/depth_anything_3/model/dpt.py" ]]; then
  curl -L --fail "https://api.github.com/repos/ByteDance-Seed/Depth-Anything-3/tarball/$SOURCE_REVISION" \
    -o "$EXPORT_ROOT/upstream.tar.gz"
  mkdir -p "$EXPORT_ROOT/upstream"
  tar -xzf "$EXPORT_ROOT/upstream.tar.gz" --strip-components 1 -C "$EXPORT_ROOT/upstream"
fi
"$HF_CLI" download depth-anything/DA3METRIC-LARGE --revision "$MODEL_REVISION" \
  --local-dir "$EXPORT_ROOT/checkpoint"
mkdir -p "$APP_ROOT/Models/DepthAnything3Metric"
cp "$EXPORT_ROOT/upstream/LICENSE" "$APP_ROOT/Models/DepthAnything3Metric/LICENSE"
if [[ ! -f "$APP_ROOT/Models/DepthAnything3Metric/DepthAnything3Metric.mlpackage/Manifest.json" ]]; then
  HF_HUB_OFFLINE=1 "$PYTHON" "$EXPORT_ROOT/export.py" export
fi
HF_HUB_OFFLINE=1 "$PYTHON" "$EXPORT_ROOT/export.py" verify --compute-units all
print 'Depth Anything 3 Metric Large is ready for the offline iOS bundle.'
