#!/usr/bin/env python3
"""Export the official DA3 metric checkpoint; never substitute relative depth.

Run with the isolated environment installed by Scripts/prepare-depth-model.sh.
The upstream backbone and DPT head are used unchanged. Only the fixed-size
positional interpolation is precomputed, and sky percentile replacement is
omitted: the consumer rejects sky pixels instead of inventing a sky distance.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import time
import types

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
WIDTH, HEIGHT = 392, 294
MODEL_REVISION = "4010e39f3634a45bc60553321fb49fb760bd594e"
SOURCE_REVISION = "3d835ec1a5802d64a8b8b15f817a1ab54809bfe4"
WEIGHTS_SHA256 = "bbea5b0b3ee389849cffa7ddae89de064a90abd2b055fc5aa99aac68db324776"
OUTPUT = ROOT / "Models/DepthAnything3Metric"
PACKAGE = OUTPUT / "DepthAnything3Metric.mlpackage"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(4 * 1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def dependencies():
    sys.path.insert(0, str(HERE / "upstream/src"))
    import numpy as np
    import torch
    from PIL import Image, ImageOps
    from safetensors.torch import load_file
    from depth_anything_3.model.dinov2.dinov2 import DinoV2
    from depth_anything_3.model.dpt import DPT
    return np, torch, Image, ImageOps, load_file, DinoV2, DPT


def make_model():
    np, torch, Image, ImageOps, load_file, DinoV2, DPT = dependencies()
    torch.set_num_threads(4)
    checkpoint = HERE / "checkpoint/model.safetensors"
    assert sha256(checkpoint) == WEIGHTS_SHA256, "Official checkpoint checksum mismatch"

    class Metric(torch.nn.Module):
        def __init__(self):
            super().__init__()
            self.backbone = DinoV2(name="vitl", out_layers=[4, 11, 17, 23],
                                   alt_start=-1, qknorm_start=-1, rope_start=-1,
                                   cat_token=False)
            self.head = DPT(dim_in=1024, output_dim=1, features=256,
                            out_channels=[256, 512, 1024, 1024])
            self.register_buffer("rgb_mean", torch.tensor([.485, .456, .406]).view(1, 3, 1, 1))
            self.register_buffer("rgb_std", torch.tensor([.229, .224, .225]).view(1, 3, 1, 1))

        def forward(self, image):
            normalized = (image - self.rgb_mean) / self.rgb_std
            features, _ = self.backbone(normalized.unsqueeze(1))
            result = self.head(features, HEIGHT, WIDTH, patch_start_idx=0)
            return result.depth[:, 0], result.sky[:, 0]

    model = Metric().eval()
    state = {k.removeprefix("model."): v for k, v in load_file(str(checkpoint)).items()}
    result = model.load_state_dict(state, strict=False)
    assert result.missing_keys == ["rgb_mean", "rgb_std"] and not result.unexpected_keys, result
    del state
    return model


def prepared_image(path):
    np, _, Image, ImageOps, *_ = dependencies()
    image = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
    # Reference fixtures are explicitly rotated/cropped just as the static input
    # contract requires. This is not an estimate of camera focal length.
    if image.height > image.width:
        image = image.transpose(Image.Transpose.ROTATE_90)
    target_aspect = WIDTH / HEIGHT
    if image.width / image.height > target_aspect:
        new_width = round(image.height * target_aspect)
        left = (image.width - new_width) // 2
        image = image.crop((left, 0, left + new_width, image.height))
    else:
        new_height = round(image.width / target_aspect)
        top = (image.height - new_height) // 2
        image = image.crop((0, top, image.width, top + new_height))
    return image.resize((WIDTH, HEIGHT), Image.Resampling.BILINEAR)


def fixtures():
    return [HERE / "upstream/assets/examples/SOH/000.png",
            HERE / "upstream/assets/examples/SOH/010.png"]


def export():
    np, torch, *_ = dependencies()
    import coremltools as ct
    OUTPUT.mkdir(parents=True, exist_ok=True)
    model = make_model()
    reference_dir = ROOT / "Logs/da3-reference"
    reference_dir.mkdir(parents=True, exist_ok=True)
    records = []
    for index, fixture in enumerate(fixtures()):
        image = prepared_image(fixture)
        image.save(reference_dir / f"input-{index}.png")
        tensor = torch.from_numpy(np.asarray(image).copy()).permute(2, 0, 1).unsqueeze(0).float() / 255
        started = time.monotonic()
        with torch.inference_mode():
            depth, sky = model(tensor)
        arrays = {"canonicalDepth": depth.numpy(), "sky": sky.numpy()}
        np.savez_compressed(reference_dir / f"expected-{index}.npz", **arrays)
        records.append({"fixture": str(fixture.relative_to(ROOT)), "seconds": time.monotonic()-started,
                        "shape": list(depth.shape), "depthRange": [float(depth.min()), float(depth.max())],
                        "nonSkyFraction": float((sky < .3).float().mean())})
        print("reference", index, records[-1], flush=True)

    # Static positional embedding: same official bicubic interpolation, evaluated
    # once, and compared below. This removes unsupported dynamic bicubic graph ops.
    backbone = model.backbone.pretrained
    with torch.inference_mode():
        position = backbone.interpolate_pos_encoding(
            torch.zeros(1, (HEIGHT//14)*(WIDTH//14)+1, 1024), HEIGHT, WIDTH)
    backbone.register_buffer("fixed_position", position)
    def fixed_position(self, x, w, h):
        return self.fixed_position.to(x.dtype)
    backbone.interpolate_pos_encoding = types.MethodType(fixed_position, backbone)
    with torch.inference_mode():
        check_depth, check_sky = model(tensor)
    precompute_error = max(float((check_depth-depth).abs().max()), float((check_sky-sky).abs().max()))
    assert precompute_error == 0, precompute_error
    print("trace begins", flush=True)
    with torch.inference_mode():
        traced = torch.jit.trace(model, tensor, check_trace=False, strict=False)
    print("CoreML conversion begins", flush=True)
    converted = ct.convert(
        traced, convert_to="mlprogram", minimum_deployment_target=ct.target.iOS18,
        inputs=[ct.ImageType(name="image", shape=(1, 3, HEIGHT, WIDTH),
                             color_layout=ct.colorlayout.RGB, scale=1/255)],
        outputs=[ct.TensorType(name="canonicalDepth", dtype=np.float32),
                 ct.TensorType(name="sky", dtype=np.float32)],
        compute_precision=ct.precision.FLOAT16,
        compute_units=ct.ComputeUnit.ALL, skip_model_load=True,
    )
    converted.author = "ByteDance Seed; CoreML conversion by LunaV"
    converted.license = "Apache-2.0"
    converted.short_description = "Official Depth Anything 3 Metric Large, canonical metric depth and sky score"
    converted.version = MODEL_REVISION
    converted.input_description["image"] = "RGB 392x294, rotate/crop rectilinear RGB and transform intrinsics to this grid"
    converted.output_description["canonicalDepth"] = "Raw canonical z depth; metres = value * mean(fxModel,fyModel) / 300"
    converted.output_description["sky"] = "Raw nonnegative sky score, not probability/confidence; reject sky >= 0.3"
    converted.user_defined_metadata.update({
        "model_repository": "depth-anything/DA3METRIC-LARGE", "model_revision": MODEL_REVISION,
        "source_revision": SOURCE_REVISION, "metric_scale_denominator": "300",
        "sky_threshold": "0.3", "normalization": "RGB/255; mean .485,.456,.406; std .229,.224,.225",
    })
    converted.save(str(PACKAGE))
    shutil.copy2(HERE / "upstream/LICENSE", OUTPUT / "LICENSE")
    (OUTPUT / "NOTICE").write_text(
        "Depth Anything 3 Metric Large\n"
        "Copyright (c) 2025 ByteDance Ltd. and/or its affiliates.\n"
        "DINOv2 components: Copyright (c) Meta Platforms, Inc. and affiliates.\n"
        "Apache License 2.0; see LICENSE.\n\n"
        f"Official model: depth-anything/DA3METRIC-LARGE, revision {MODEL_REVISION}\n"
        f"Official source: ByteDance-Seed/Depth-Anything-3, revision {SOURCE_REVISION}\n\n"
        "LunaV conversion: CoreML FP16; exact fixed-size positional precomputation;\n"
        "ImageNet normalization in graph; raw depth and sky outputs without\n"
        "percentile sky-depth replacement. Sky is rejected for object ranges.\n")
    manifest = {
        "model": "Depth Anything 3 Metric Large", "repository": "depth-anything/DA3METRIC-LARGE",
        "revision": MODEL_REVISION, "sourceRepository": "https://github.com/ByteDance-Seed/Depth-Anything-3",
        "sourceRevision": SOURCE_REVISION, "license": "Apache-2.0", "parameters": 334171394,
        "officialWeightsSHA256": WEIGHTS_SHA256, "input": {"name": "image", "width": WIDTH,
        "height": HEIGHT, "color": "RGB", "scale": 1/255, "mean": [.485,.456,.406], "std": [.229,.224,.225]},
        "outputs": {"canonicalDepth": [1, HEIGHT, WIDTH], "sky": [1, HEIGHT, WIDTH]},
        "metricFormula": "zMetres = canonicalDepth * (fxAtModelInput + fyAtModelInput) / 2 / 300",
        "validity": "finite canonicalDepth > 0 and finite sky < 0.3; no confidence head",
        "precision": "float16 weights and compute, float32 outputs", "minimumIOS": "18.0",
        "geometry": "Runtime rotates upright portrait RGB 90 degrees counterclockwise, aspect fits into 392x294 with black letterbox, removes padding and undoes rotation in depth and sky. Scale intrinsics using only the valid content width/height in original upright orientation, not padded canvas dimensions.",
        "files": {str(p.relative_to(OUTPUT)): {"bytes": p.stat().st_size, "sha256": sha256(p)}
                  for p in sorted(PACKAGE.rglob("*")) if p.is_file()},
    }
    (OUTPUT / "manifest.json").write_text(json.dumps(manifest, indent=2)+"\n")
    (ROOT / "Logs/da3-pytorch-reference.json").write_text(json.dumps({"cases": records,
        "positionalPrecomputeMaxAbsoluteError": precompute_error, "torch": torch.__version__,
        "coremltools": ct.__version__}, indent=2)+"\n")
    print("saved", PACKAGE, flush=True)


def verify(compute_units="cpu-gpu"):
    import numpy as np
    import coremltools as ct
    from PIL import Image
    manifest = json.loads((OUTPUT / "manifest.json").read_text())
    for relative_path, expected_file in manifest["files"].items():
        path = OUTPUT / relative_path
        assert path.stat().st_size == expected_file["bytes"] and sha256(path) == expected_file["sha256"], path
    ref = ROOT / "Logs/da3-reference"
    started = time.monotonic()
    units = {"cpu-gpu": ct.ComputeUnit.CPU_AND_GPU, "all": ct.ComputeUnit.ALL,
             "cpu": ct.ComputeUnit.CPU_ONLY}[compute_units]
    model = ct.models.MLModel(str(PACKAGE), compute_units=units)
    loaded_seconds = time.monotonic() - started
    records = []
    for index in range(3):
        image = Image.open(ref / f"input-{index}.png").convert("RGB")
        expected = np.load(ref / f"expected-{index}.npz")
        started = time.monotonic()
        actual = model.predict({"image": image})
        elapsed = time.monotonic() - started
        record = {"case": index, "predictionSeconds": elapsed, "outputs": {}}
        for key in ("canonicalDepth", "sky"):
            a, e = actual[key], expected[key]
            finite = np.isfinite(a) & np.isfinite(e)
            assert finite.all(), (index, key, "nonfinite output")
            delta = np.abs(a-e)
            relative = delta / np.maximum(np.abs(e), .1)
            record["outputs"][key] = {"shape": list(a.shape), "meanAbsoluteError": float(delta.mean()),
                "maximumAbsoluteError": float(delta.max()), "meanRelativeError": float(relative.mean()),
                "p99RelativeError": float(np.quantile(relative, .99))}
            if key == "canonicalDepth":
                assert float(relative.mean()) < .03 and float(np.quantile(relative, .99)) < .12, record
        record["nonSkyMaskAgreement"] = float(((actual["sky"] < .3) == (expected["sky"] < .3)).mean())
        assert record["nonSkyMaskAgreement"] > .98, record
        # Geometry scaling invariant: doubling known focal doubles metric depth.
        d = actual["canonicalDepth"]
        assert np.allclose(d * 600/300, (d * 300/300)*2)
        records.append(record)
        print(json.dumps(record), flush=True)
    report = {"runtime": f"native CoreML {units.name} on macOS", "loadSeconds": loaded_seconds,
              "parity": "official PyTorch backbone+DPT prior to sky percentile replacement",
              "cases": records, "metricScalingInvariant": "passed; raw depth * known resized focal / 300",
              "physicalAccuracy": "not measured; conversion parity is not LiDAR accuracy"}
    suffix = "" if compute_units == "cpu-gpu" else f"-{compute_units}"
    (ROOT / f"Logs/da3-coreml-parity{suffix}.json").write_text(json.dumps(report, indent=2)+"\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["export", "verify"])
    parser.add_argument("--compute-units", choices=["cpu-gpu", "all", "cpu"], default="cpu-gpu")
    args = parser.parse_args()
    if args.action == "export":
        export()
    else:
        verify(args.compute_units)
