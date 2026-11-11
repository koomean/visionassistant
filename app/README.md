# LunaV iOS app

LunaV is an on-device visual assistant for iPhone. The app captures a photo, accepts a spoken or typed question, and can read text, describe an image, or estimate distance. LiDAR devices use paired sensor depth; other supported devices can use Depth Anything 3 Metric. Speech uses iOS speech services and system voices where available. Measurements and generated answers may be incorrect; this is research software and is not a substitute for mobility aids.

## Source layout

- `LunaV/` — SwiftUI app, camera, speech, accessibility and assets.
- `Shared/` — model runtime, OCR, depth processing and response policy.
- `Models/DepthAnything3Metadata/` — depth-model provenance and license.
- `Scripts/` — build and model preparation scripts.
- `Tools/DepthAnything3Export/` — reproducible Core ML export source.

This release excludes test and diagnostic files, user data, logs, build outputs, and model weights. The app source is based on version 3.2.0 (build 5). Internal validation entry points and their diagnostic-only files are omitted from the published copy.

## Prerequisites

A Mac with Xcode 27 or later and the iOS 27 SDK, XcodeGen, `uv`, the Hugging Face `hf` CLI, Python 3.11 (managed by `uv`), ample free disk space and network access for initial model preparation. Running on a device requires your own Apple development team and a unique bundle identifier. iOS speech language assets may also need initial download. Inference is on device after preparation.

## Prepare models and build

From this folder:

```sh
# Download the original Qwen model, then convert it locally to MLX 4-bit.
hf download Qwen/Qwen3-VL-2B-Instruct --local-dir Models/.source-qwen
./Scripts/prepare-model.sh "$PWD/Models/.source-qwen"

# Download pinned Depth Anything 3 Metric Large and export Core ML locally.
./Scripts/prepare-depth-model.sh

# Generate the Xcode project and build without signing.
./Scripts/build.sh
```

Model preparation downloads gigabytes of weights and can take considerable time and memory. The depth script uses a pinned model and source revision and verifies the downloaded checkpoint. The generated model files are ignored by Git and must not be committed. `prepare-model.sh` converts the supplied upstream weights; it does not download them itself.

Open `LunaV.xcodeproj` after model preparation (or run `xcodegen generate`), choose your iPhone and set **Signing & Capabilities** to your own team and bundle identifier. For a fresh checkout the two model paths do not exist until the preparation commands complete. Device capabilities, installed speech assets and available memory affect feature availability.

## Licensing

The project is distributed under the repository's [AGPL-3.0 license](../LICENSE), with [commercial licensing information](../COMMERCIAL-LICENSE.md). Third-party models and bundled fonts have their own licenses and terms; see `Models/DepthAnything3Metadata/` and `LunaV/Fonts/`. Qwen3-VL and Depth Anything 3 are separate upstream projects; review their model cards and licenses before distribution.
