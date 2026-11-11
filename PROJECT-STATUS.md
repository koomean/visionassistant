# LunaV project status

**Updated 11 November 2026.** The current app is **LunaV 3.2.0 (build 5)**, an on-device iPhone research prototype designed to make everyday tasks easier for people who face barriers to seeing, including people who are blind, have low vision, or have difficulty seeing in a particular situation. The public GitHub repository hosts this website and its notices. The app source, model weights, and raw validation logs are kept in the app workspace. [Visit the project on GitHub](https://github.com/koomean/visionassistant).

## What’s new in 3.2.0

- **Follow up on the same photo.** Turn on **Reuse the photo on hold** in Settings. Hold the shutter to ask about the latest photo and its paired depth, or tap briefly to take a new photo. VoiceOver also offers a follow-up action on the shutter.
- **Read only what you ask for.** Say “Read only the price on the right” or ask for the bus route number in Thai or English. Apple Vision OCR extracts the requested text from the photo. LunaV asks for the item or area when several values match and says when it cannot verify the requested text.
- **Find something nearby.** Say “Help me find my keys” to search a fresh camera photo. LunaV reports where a matching item appears in the frame or asks for a distinguishing detail such as its colour. Aim the camera as directed and ask again. When LunaV confirms that the object is centred in a recent capture, it can play a short tone and pulse the haptics on supported devices.

## Latest validation — 11 November 2026

| Check | Recorded result | Scope and limit |
| --- | --- | --- |
| iPhone 17 Simulator with iOS 27.0 | **288/288 passed (285 unit and 3 UI)** with zero failures, skips, or recorded runtime warnings | The UI checks cover hold-and-release submission, keeping and replacing a photo, and reading a price with Apple Vision OCR. Camera capture and speech recognition use simulated inputs in these checks. |
| Local visual-model checks on Mac | Qwen located the orange-juice bottle on the right and the green bottle in the centre of their respective test images, requested a detail when several bottles matched, and reported that absent keys were not found | These results cover the selected test images and prompts. |
| Generic iOS Release | Xcode build passed with signing disabled for compilation. Bundle metadata shows **3.2.0 / build 5**. | Installation, tone playback, and the finder’s haptic pulse are awaiting checks on a physical iPhone. |

The results above come from the app’s release checks. General model accuracy, human speech accuracy, physical distance accuracy, battery life, and thermal performance require separate validation.

## App language and About

Use **Settings → App language** to switch the interface immediately between Thai and English. The choice persists across relaunches and covers the camera, Settings, About, conversation controls, region/text-group/distance tools, runtime information, status, and errors. It is independent of the selected Dictation language, answer language, and reading voice. Existing questions, answers, and original OCR text are preserved rather than translated when the interface changes. Language names and the creator's name keep their original spelling.

The final Settings group opens **About → About LunaV**, showing the actual bundle version **3.2.0 / build 5**, creator **Wachirawich kripindakul (koomean)**, and a link to the LunaV website. The bundle includes Thai and English interface catalogs and permission descriptions. iOS system screens follow the system language.

## Current interface

The camera, Settings, conversation, region-selection, text-grouping, and distance screens use midnight blue, warm white, pale blue/gold, Noto Sans Thai, and Manrope. The app icon now uses the website's crescent-and-star geometry. Settings puts language, speech input, and answer voices before testing tools, with expandable speech and calibration details. The camera screen retains its two main buttons; the front/rear camera-switch menu has been removed from Settings.

The iPhone Duo layout keeps the same two controls on the outer screen, separates the preview and answer areas in the wider open layout, and uses the space available around the fold in partly folded mode.

A native SwiftUI introduction shows **LunaVision → red pen over “ision” → LunaV. → camera header** in about **4.22 seconds**. Model preparation starts alongside it and continues underneath. If preparation is still incomplete, the app shows its actual preparation/retry state after the animation. Reduce Motion uses a brief static mark instead; returning from the background does not replay the introduction. The app does not use a WebView or video for this sequence.

The website’s camera, conversation, Settings, and Thai/English About previews were captured from **iOS Simulator on 29 October 2026** for version 3.0.0. The English conversation preserves its original Thai question and source OCR text. The text-grouping preview shows the earlier lunar UI. These previews illustrate interface behaviour and OCR test images.

## Ask, read, and listen

By default, holding the centre button starts photo/depth capture and microphone recording together after microphone permission is granted. Speak while holding, then release to stop recording and submit once the image is ready. A short tap takes a photograph only. The optional same-photo setting reuses the latest capture for follow-up questions. The finder still uses a fresh capture. Recordings over the **2-minute limit** are rejected rather than submitting only their beginning.

**Apple DictationTranscriber through SpeechAnalyzer** handles speech input locally using installed Apple language assets. Thai is the default; select English with the separate speech-language setting in Settings. Each request uses one selected language, without automatic language switching. The app checks device/locale support. Missing language assets may need an initial download; fresh-install offline speech is not guaranteed. Transcription has a **45-second deadline**. Whisper is no longer in the current app bundle.

Completed AI, OCR, summary, and distance answers are read automatically by default with **installed Apple voices**. Settings can disable reading, select Thai/English voices, and preview a voice. Reading stops before new capture/recording, cancellation, context clearing, or backgrounding. This does not promise access to the user's selected Siri voice. Additional voices can be installed through iOS Settings.

Apple Vision OCR and Qwen3-VL-2B-Instruct 4-bit through MLX/Metal run locally. Settings tools support region selection, grouping signs/menus/labels, and summarising selected OCR text. Same-photo questions use bounded follow-up context. Finder directions describe the captured camera frame. OCR, transcription, estimates, and generated answers can be wrong.

## Distance and its source

On a **LiDAR-equipped device**, supported captures use sensor depth paired with the photograph: camera-to-surface distance at capture time. These devices skip Depth Anything 3, including when sensor depth is missing. A failed LiDAR reading is not silently replaced with a model estimate labelled as LiDAR.

On a **device without LiDAR**, bundled **Depth Anything 3 Metric** estimates depth from a new photograph and its lens focal information **when a distance question or manual point selection needs it**. Ordinary visual questions do not trigger a prediction. A successful map is reused for the same capture; transient prediction failures can be retried. Missing lens information, sky, or invalid values can prevent a reading. Answers label the model source and round estimates to 0.1 metre. Imported images without paired depth do not produce numeric distances.

Settings can fit a per-camera scale from a measured camera-to-surface reference of **0.3–8 metres** near the image centre. Calibration may reduce consistent bias; it does not validate other scenes or certify accuracy. **DA3 has not been compared against measured physical reference distances on the delivered app.** LiDAR is also not certified here against physical reference measurements.

**LiDAR obstacle haptics** are an optional Settings feature on compatible iPhones with rear LiDAR. During live camera preview, the pulses become stronger and more frequent as an obstacle in the central area gets closer. The default start distance is **2 m**, the strongest point is **0.4 m**, and the maximum strength is **80%**. Settings lets users adjust all three and preview the vibration. Monitoring pauses during capture or AI processing, while the app is in the background, or when the device is too hot.

## Preparation and resource use

The app targets **iOS 27 / Xcode 27 or later**. Dictation support depends on device and language; image/depth inference still needs sufficient memory and supported hardware. It prepares visual models before enabling questions and retries temporary failures in the foreground. DA3 preparation applies only to devices without LiDAR. Speech preparation has a **30-second deadline** and can retry separately. If speech is unavailable, photos, typed questions, OCR, and summaries remain available once their required visual models are ready.

The compact policy applies at **6 GiB physical RAM or below**, or when reported positive process headroom is below **1 GiB**. It releases idle visual-model weights before a new capture and after answers, and retains lightweight image references and bounded text/OCR/tokenizer caches. OCR runs before a cold visual-model load. Releasing weights can add another load before the next answer. Successful warmup stages are tracked separately from resident weights so returning from the background does not repeat every completed stage.

Cancellation and memory-warning cleanup follow running work before models reload. In-flight inference may own buffers until it returns; cancellation does not guarantee immediate or complete RAM release. Native-speech cleanup does not block typed visual questions. The optimisation retained model weights, quantisation, image resolution, answer checks, and memory-admission safeguards. Warmup does not guarantee that weights remain in RAM or every device can run inference.

## Earlier app validation

### 3.1.0 build 4 — 11 November 2026

Version 3.1 added a layout that adapts to the iPhone Duo’s outer, open, and partly folded states, plus the optional LiDAR obstacle haptics. On the Duo Simulator, **2/2** UI checks passed, including the layout transition with the question, photo status, and both controls preserved. On the regular iPhone 17 Simulator, **271 unit tests** and **7/7 landscape checks** passed. A generic iOS Release compiled with signing disabled. The sensor-distance and haptic-strength checks were simulated.

### 3.0.0 build 3 — 29 October 2026

Version 3.0 added Thai/English UI selection and About. The Simulator suite passed **269/269 (253 unit and 16 UI)**, followed by a **2/2** focused translation and bundle metadata rerun. A signed generic-iOS Release passed strict code-signature verification. The iPhone 14 installation command was cancelled after more than three minutes without connection or transfer progress. The source and catalog audit found 26 unchanged core source hashes and no missing or invalid English entries.

### Earlier lunar interface — 29 October 2026

The lunar-theme update before 3.0.0 passed **262/262 Simulator tests (249 unit + 13 UI)** and its signed Release passed verification. That build's physical iPhone 14 install failed with **CoreDevice 4000 / transport peer no longer reachable**. Its seven UI source hashes and 18 Shared hashes matched its recorded manifest.

## Earlier resource build — 24 October 2026

These results belong to the earlier resource-optimisation build, not the new UI's physical-device validation.

| Check | Recorded result | Scope and limit |
| --- | --- | --- |
| Simulator regression | **259/259: 248 unit + 11 UI**, no failures/skips/runtime warnings | Recorded before later device diagnostics and headroom-check ordering entered the final signed build. |
| iPhone 14 / iOS 27.2 | Signed Release installed and returned to normal ready mode | This check used the 24 October resource build on an iPhone 14 without LiDAR. |
| Two real-camera question cycles | Recorded speech fixtures → VLM/TTS completed without retry, fallback, or memory refusal in those cases | Real captures with file-based speech input; not a live-human microphone or semantic-accuracy benchmark. |
| Deferred/reused DA3 | Two ordinary photos used **0** predictions; manual depth then automatic range on one photo reused **1** prediction | Capture time and lens pairing checked; no measured reference distance or calibration change. |
| Two OCR fixture questions | OCR preceded cold model loading; second question reused the same-image OCR cache | Confirms order/cache use for those cases, not universal semantic correctness. |
| Speech / answer reading | Five Thai/English fixtures returned text, silence/white noise were rejected, and **3** TTS completion/session-handoff cases passed | Fixed recordings and synthesis callbacks; not human accuracy, human-heard playback, or Silent-switch validation. |
| Sampled app-process footprint | Peak **2.394 GB**; settled **96.7–117.6 MB** after TTS/range, decimal units | Includes diagnostics overhead, excludes separate iOS speech services. No controlled savings comparison, battery/thermal benchmark, or new long-duration soak. |

## Earlier evidence and remaining limits

A preceding compact-memory build on **iPhone 14 Pro** completed **30/30 cycles in 545.8 seconds**, using real RGB/depth captures, recorded speech, and TTS enabled. **15 cycles returned a safe fallback after retry**. No memory refusal/app stop was recorded in that run, but this is not 30 correct or spoken model answers. Settled footprint was **91.6–225.8 MiB, median 155.9 MiB**; sampled peak about **2.47 GB**. Settled memory rose during the run and a serious thermal state was observed. A separate controlled three-cycle check compared about **1.9 GiB** baseline with **61–66 MiB** compact footprint; one injected memory warning recovered. These are bounded earlier tests, not universal savings or unlimited-operation guarantees.

Earlier 24 October speech work recorded 224 unit passes, initially 10/11 UI followed by a corrected targeted 2/2 rerun. The earlier Dictation run passed 220/220 plus six separate native-integration cases. Five synthetic speech files and two non-speech files were checked on iPhone 14 Pro; a 41-second file retained speech beyond 30 seconds. These historical results are not added to the latest test total.

Earlier 21 October Mac VLM/OCR evidence contained **22 correct concrete answers + 7 abstentions across 29 cases**; six abstentions missed visible information and one declined an absent price. Former Whisper synthetic results were **10/12 exact transcriptions**, not current Apple Dictation accuracy. The historical 23 October hold/release suite passed 155/155. Controlled follow-up/LiDAR/DA3 fixtures establish routing or geometry for their setup, not physical distance accuracy.

Human microphone accuracy, human-confirmed audibility/Silent-switch behaviour, and measured physical distance accuracy remain unestablished by these records. No promise is made of compatibility with every iPhone, continuous navigation, unlimited operation, or correct answers on every image.

## Data handling

Image/depth inference, OCR, installed-asset transcription, and installed-voice synthesis run on the device without a cloud AI service or API key. Initial Apple language downloads may need network access. Qwen and DA3 are bundled; iOS manages speech assets and voices.

Temporary WAV recordings, compressed images, previews, and crops can be stored in the app sandbox. Audio is removed when its worker actually finishes, including after cancellation/timeout; deletion is not necessarily immediate while work continues. Superseded images are cleaned up. This is not a claim that data stays only in RAM. These statements describe the app, not website hosting or external links.

## Evidence provenance

Descriptions were checked against the supplied app's current `README.md`, `VALIDATION.md`, UI/runtime source, and recorded logs. These provenance names refer to the app workspace, not files distributed in this website repository.

Version 3.2 evidence uses `Logs/LunaV-v32-delivery-simulator.xcresult`, `Logs/LunaV-v32-delivery-simulator.log`, `Logs/LunaV-v32-delivery-iphone.log`, and the local `LunaVModelCheck` finder runs. `project.yml` is the app version source.

Version 3.1 evidence uses `Logs/v31-duo-handoff-summary.json`, `Logs/v31-iphone17-verified-summary.json`, `Logs/v31-landscape-delivery-summary.json`, and `Logs/v31-device-final.log`.

Version 3.0 evidence uses `Logs/v3-language-delivery-test-summary.json`, `Logs/v3-catalog-final-test-summary.json`, `Logs/v3-language-source-summary.json`, `Logs/ui-localization-audit.json`, `Logs/v3-language-final-release-build.log`, `Logs/v3-language-final-signature.log`, and `Logs/v3-language-device-install.log`. The UI session ledger and V3 Simulator previews record visual checks.

Earlier lunar-UI evidence retains `Logs/website-ui-delivery-test-summary.json`, `Logs/website-ui-source-summary.json`, and its release/signature/device-install records.

Earlier resource results use `Logs/resource-optimization-tests-summary.json`, `Logs/resource-optimization-delivery-summary.json`, `Logs/resource-device-delivery-summary.json`, and the functional/OCR/native/TTS/normal-preparation device records. Compact-memory results use `Logs/memory-delivery-summary.json`, `Logs/memory-final-soak.json`, and `Logs/memory-constrained-fixed.json`. Earlier speech/geometry results retain their `answer-speech-*`, `native-dictation-*`, `da3-*`, `qa-*`, and `ptt-*` provenance.
