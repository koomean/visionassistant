"""Check that the bundled weights are complete MLX Qwen3-VL weights, without loading them."""
import json
import struct
import sys
from pathlib import Path

directory = Path(sys.argv[1])
for filename in ("config.json", "tokenizer.json", "tokenizer_config.json", "preprocessor_config.json"):
    assert (directory / filename).is_file(), f"Missing {filename}"
config = json.loads((directory / "config.json").read_text())
assert config["model_type"] == "qwen3_vl"
assert config["quantization"]["bits"] == 4
weights = sorted(directory.glob("*.safetensors"))
assert weights, "Missing safetensors weights"
total = 0
for weight in weights:
    with weight.open("rb") as handle:
        header_size = struct.unpack("<Q", handle.read(8))[0]
        header = json.loads(handle.read(header_size))
    tensors = [value for name, value in header.items() if name != "__metadata__"]
    assert weight.stat().st_size == 8 + header_size + max(t["data_offsets"][1] for t in tensors)
    assert any(name.endswith(".scales") for name in header), "Weights are not quantized"
    total += weight.stat().st_size
print(f"Verified Qwen3-VL 4-bit model: {len(weights)} weight file(s), {total / 1024**3:.2f} GiB")
