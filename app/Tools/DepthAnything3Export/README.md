# Depth Anything 3 Metric Large export

`Scripts/prepare-depth-model.sh` downloads the official checkpoint at a pinned
revision and converts it locally using the isolated Python 3.11 environment.
There is no runtime download, Python, or PyTorch dependency in the iOS app.

- Weights: `depth-anything/DA3METRIC-LARGE`, revision
  `4010e39f3634a45bc60553321fb49fb760bd594e`.
- Upstream source: ByteDance-Seed/Depth-Anything-3, revision
  `3d835ec1a5802d64a8b8b15f817a1ab54809bfe4`.
- License: Apache 2.0; the model asset directory contains the upstream license.
- Uses all 334,171,394 checkpoint parameters, including the sky head. This is
  the metric DA3 model, not a relative-depth model with an arbitrary scale.

## CoreML contract

Input `image`: RGB image, 392 by 294 pixels. CoreML divides bytes by 255;
the graph applies ImageNet mean `[.485,.456,.406]` and standard deviation
`[.229,.224,.225]`. Outputs `canonicalDepth` and `sky` are float32 arrays
`[1,294,392]`. Weights and computation use float16.

`zMetres = canonicalDepth * mean(fxAtModelInput, fyAtModelInput) / 300`

The focal values must come from the matching calibrated camera and be
transformed by the same rotation, crop and resize as RGB. Pixel coordinates
must map back through the inverse transform before associating an object.
The Swift runtime rotates portrait photos counterclockwise to landscape,
aspect fits them into the model grid with black letterbox, then removes the
padding and undoes rotation in both output maps. Intrinsics use the valid
content width/height after undoing rotation, not the padded canvas size. Never
stretch an image and keep an unmodified focal length. Never guess focal length
for an imported image. Export parity fixtures use explicit center crops solely
to compare identical prepared tensors; Swift runtime performs a separate letterbox mapping for real camera input.

Reject nonfinite/nonpositive depth and any pixel with `sky >= .3`. The sky
output is a nonnegative score, not a calibrated probability or range confidence.
The official percentile replacement of sky distance is deliberately omitted:
sky is invalid for object distance. Native parity therefore compares the
unchanged official backbone+DPT outputs before that sky replacement.

Conversion parity verifies numerical implementation, not physical distance
accuracy. Monocular estimates cannot promise LiDAR-equivalent measurements.
Real camera/LiDAR comparison and per-camera calibration remain necessary for
accuracy claims. The export script writes conversion parity results under `Logs/`.

`MonocularDepthRuntime.prepare()` loads and performs a real prediction before
declaring readiness. The actor retains the model for subsequent questions;
cancellation and deferred release preserve ownership until actual CoreML work
returns. iOS loads require 1.5 GiB available process headroom; each prediction
requires an additional 512 MiB working allowance. These are conservative
admission budgets, not measured iPhone footprint promises. macOS has no iOS
process-headroom API; native QA treats that budget as unknown.
