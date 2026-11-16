# LunaV project status

**Updated 16 November 2026.** LunaV **3.2.1 (build 6)** is an on-device iPhone research prototype. It uses the camera and speech to make everyday tasks easier for people who are blind, have low vision, or have difficulty seeing in a particular situation. The website and its notices are in the public GitHub repository. App and motion source are available as release assets. [Download the 3.2.1 source release](https://github.com/koomean/visionassistant/releases/tag/v3.2.1-source).

## Reading and visual assistance

- **Follow up on the same photo.** Turn on **Reuse the photo on hold** in Settings. Hold the shutter to ask about the latest photo and its paired depth, or tap briefly to take a new photo. VoiceOver also offers a follow-up action on the shutter.
- **Read only what you ask for.** Say “Read only the price on the right” or ask for the bus route number in Thai or English. Apple Vision OCR extracts the requested text from the photo. LunaV asks for the item or area when several values match and says when it cannot verify the requested text.
- **Find something nearby.** Say “Help me find my keys” to search a fresh camera photo. LunaV reports where a matching item appears in the frame or asks for a distinguishing detail such as its colour. Aim the camera as directed and ask again. When LunaV confirms that the object is centred in a recent capture, it can play a short tone and pulse the haptics on supported devices.
- **Read the most prominent text.** In 3.2.1, a general request such as “Read the label” prefers a prominent heading over small text such as the package quantity. Ask to read all text or name a field when you need it. LunaV can ask which area to read when several prominent headings match.

## Recent validation

### iPhone Simulator — 12 November 2026

The focused **3.2.1 (build 6)** run used the iPhone 17 Simulator with iOS 27.2.

| Check | Passed | What it covered |
| --- | ---: | --- |
| Unit tests | **21/21** | Document reading, prominent text, requested fields and packaged version information. |
| UI tests | **2/2** | Spoken label reading and reading a requested price with Apple Vision OCR. Both used simulated camera and speech inputs. |
| Total | **23/23** | Zero failures, skips or recorded runtime warnings in this run. |

An earlier run of the label-reading check failed that evening. The check passed in the 23-test run.

### Mac component benchmark — 16 November 2026

The evaluation used file inputs on Apple Silicon with macOS 27.2.1 and tools built from LunaV 3.2.1 (build 6). OCR used Apple Vision, the visual model used Qwen3-VL-2B-Instruct 4-bit via MLX, and speech used the app’s Apple Dictation decoder. CER is character error rate and WER is word error rate. Lower is better for both. Each result applies to its own inputs and scoring method.

| Task | Evaluation inputs | Recorded result |
| --- | --- | --- |
| OCR | [TEMS v5](https://data.mendeley.com/datasets/ntdmgksh9w/5), 514 text crops | **3.07% CER**. Exact text on **434/514** images. |
| Visual Q&A | [VizWiz VQA](https://vizwiz.org/tasks-and-datasets/vqa/), 150 questions | **56.07%** under VizWiz’s scoring method. |
| Object finding | 50 synthetic scenes | **39/50 (78%)** matched the expected response. |
| Thai Dictation | [FLEURS](https://huggingface.co/datasets/google/fleurs), 50 Thai clips | **10.73% CER**. All 50 returned text. |
| English Dictation | [FLEURS](https://huggingface.co/datasets/google/fleurs), 50 US English clips | **22.68% CER**, **28.00% WER**. Ten clips returned no text. |
| Document summaries | 8 synthetic document images | **18/27 facts** retained. **3/8** summaries retained every expected fact. |

- **OCR.** The CER represents 263 edits across 8,571 reference characters. Whitespace-delimited WER was 10.64%. Eight images returned no text and counted as deletions.
- **Visual Q&A.** The score was 48.10% on the 100 answerable questions and 72.00% on the 50 unanswerable questions. The model said `unanswerable` on 13 and 35 questions in those groups, respectively. One image below the model’s minimum height scored zero.
- **Object finding.** Left 10/10, right 10/10, centred 4/10, absent 10/10 and multiple matches 5/10. The other six centred scenes prompted a camera adjustment.
- **Dictation.** Thai had 628 edits across 5,854 reference characters. English had 1,139 across 5,023. The ten missing English transcriptions counted as deletions. CER was 5.36% across the 40 English clips that returned text.
- **Summaries.** One reviewer checked the retained facts. Example errors included changing a correctly read Friday time and misidentifying a correctly read water label.

TEMS CER was 2.41% for Thai (258 crops), 0.83% for English (188), 8.36% for mixed Thai/English (63) and 0.00% for numerals/symbols (5). Exploratory 95% bootstrap intervals were **1.93–4.60% CER** for TEMS and **49.00–63.07%** for the VizWiz score. TEMS resampling grouped crops by source photo. The v5 metadata contains 112 test source-photo IDs. The accompanying paper reports 162, so the results should only be compared directly once the test IDs are matched. VizWiz and FLEURS samples used seed 2027. These file-based checks leave live microphone use, end-to-end offline operation, iPhone latency and battery life open for measurement.

### Physical iPhone distance comparison — 16 November 2026

A LunaV **3.2.1 (build 6) Release test build** captured five frames per phone in one scene with a white jar. The iPhone 14 Pro produced filtered rear LiDAR depth. The iPhone 14 used DA3 with scale 1.0 and the camera’s intrinsic matrix. Both devices returned values at all five selected positions in all five frames, giving **25 paired readings**. The DA3 test path invoked the camera, image preparation and depth runtime directly after ordinary preparation attempts reported the model as busy. Both paths used LunaV’s production range reader.

| Point in the frame | Median LiDAR (m) | Median DA3 (m) | Mean DA3 minus LiDAR (cm) |
| --- | --- | --- | --- |
| Jar surface | 0.659 | 0.484 | −17.5 |
| Upper left | 0.813 | 1.131 | +31.8 |
| Upper right | 0.869 | 0.772 | −9.7 |
| Lower left | 0.574 | 0.410 | −16.4 |
| Lower right | 0.648 | 0.427 | −22.1 |

Mean absolute difference across the 25 pairs was **19.5 cm**, and **17.5 cm** over the five jar-surface pairs. A negative value means DA3 estimated a closer surface than LiDAR. The cameras have different frame proportions, so matching corner coordinates may sample different spots. This experiment uses LiDAR as its reference across two devices in one scene. Absolute error remains unmeasured because there was no independent physical reference for each point.

## App language and About

Use **Settings → App language** to switch the interface immediately between Thai and English. The choice persists across relaunches and covers the camera, Settings, About, conversation controls, region/text-group/distance tools, runtime information, status, and errors. It is independent of the selected Dictation language, answer language, and reading voice. Existing questions, answers, and original OCR text are preserved rather than translated when the interface changes. Language names and the creator's name keep their original spelling.

The final Settings group opens **About → About LunaV**, showing the actual bundle version **3.2.1 / build 6**, creator **Wachirawich kripindakul (koomean)**, and a link to the LunaV website. The bundle includes Thai and English interface catalogs and permission descriptions. iOS system screens follow the system language.

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

Settings can fit a per-camera scale from a measured camera-to-surface reference of **0.3–8 metres** near the image centre. Calibration can reduce a consistent bias for that camera. The 16 November comparison used LiDAR as its reference and measured how closely the two devices agreed in one scene. Measuring absolute accuracy requires independent physical reference distances.

**LiDAR obstacle haptics** are an optional Settings feature on compatible iPhones with rear LiDAR. During live camera preview, the pulses become stronger and more frequent as an obstacle in the central area gets closer. The default start distance is **2 m**, the strongest point is **0.4 m**, and the maximum strength is **80%**. Settings lets users adjust all three and preview the vibration. Monitoring pauses during capture or AI processing, while the app is in the background, or when the device is too hot.

## Preparation and resource use

The app targets **iOS 27.0 or later**. Build the source with **Xcode 27.1 or later**. Dictation support depends on device and language; image/depth inference still needs sufficient memory and supported hardware. It prepares visual models before enabling questions and retries temporary failures in the foreground. DA3 preparation applies only to devices without LiDAR. Speech preparation has a **30-second deadline** and can retry separately. If speech is unavailable, photos, typed questions, OCR, and summaries remain available once their required visual models are ready.

The compact policy applies at **6 GiB physical RAM or below**, or when reported positive process headroom is below **1 GiB**. It releases idle visual-model weights before a new capture and after answers, and retains lightweight image references and bounded text/OCR/tokenizer caches. OCR runs before a cold visual-model load. Releasing weights can add another load before the next answer. Successful warmup stages are tracked separately from resident weights so returning from the background does not repeat every completed stage.

Cancellation and memory-warning cleanup follow running work before models reload. In-flight inference may own buffers until it returns; cancellation does not guarantee immediate or complete RAM release. Native-speech cleanup does not block typed visual questions. The optimisation retained model weights, quantisation, image resolution, answer checks, and memory-admission safeguards. Warmup does not guarantee that weights remain in RAM or every device can run inference.

## Earlier app validation

### 3.2.0 build 5 — 11 November 2026

This release passed **288/288 (285 unit and 3 UI)** on an iPhone 17 Simulator with iOS 27.0. The UI tests used simulated camera and speech inputs and checked hold-to-ask, photo reuse and replacement, and Apple Vision price reading. Four selected Mac finder prompts checked right, centred, multiple matches and absent objects. A generic iOS Release compiled with signing disabled and reported version 3.2.0 / build 5.

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

Live microphone accuracy, human-confirmed audibility and Silent-switch behaviour, and absolute distance accuracy still require measurement. Finder tones and haptic strength also require checks on a physical iPhone.

## Data handling

Image/depth inference, OCR, installed-asset transcription, and installed-voice synthesis run on the device without a cloud AI service or API key. Initial Apple language downloads may need network access. Qwen and DA3 are bundled; iOS manages speech assets and voices.

Temporary WAV recordings, compressed images, previews, and crops can be stored in the app sandbox. Audio is removed when its worker actually finishes, including after cancellation/timeout; deletion is not necessarily immediate while work continues. Superseded images are cleaned up. This is not a claim that data stays only in RAM. These statements describe the app, not website hosting or external links.

## Evidence provenance

Descriptions were checked against the supplied app's current `README.md`, `VALIDATION.md`, UI/runtime source, and recorded logs. These provenance names refer to the app workspace, not files distributed in this website repository.

Current version metadata comes from `App/project.yml`. The 12 November XCTest result is `Test-LunaV-2569.11.12_21-55-17-+0700.xcresult` in local Xcode DerivedData. The 16 November aggregate results come from `Test/Mac-Benchmark-2026-11-16/` and `Test/iPhone-Distance-2026-11-16/`. The public status page reports aggregates and methods.

Version 3.2 evidence uses `Logs/LunaV-v32-delivery-simulator.xcresult`, `Logs/LunaV-v32-delivery-simulator.log`, `Logs/LunaV-v32-delivery-iphone.log`, and the local `LunaVModelCheck` finder runs. `project.yml` is the app version source.

Version 3.1 evidence uses `Logs/v31-duo-handoff-summary.json`, `Logs/v31-iphone17-verified-summary.json`, `Logs/v31-landscape-delivery-summary.json`, and `Logs/v31-device-final.log`.

Version 3.0 evidence uses `Logs/v3-language-delivery-test-summary.json`, `Logs/v3-catalog-final-test-summary.json`, `Logs/v3-language-source-summary.json`, `Logs/ui-localization-audit.json`, `Logs/v3-language-final-release-build.log`, `Logs/v3-language-final-signature.log`, and `Logs/v3-language-device-install.log`. The UI session ledger and V3 Simulator previews record visual checks.

Earlier lunar-UI evidence retains `Logs/website-ui-delivery-test-summary.json`, `Logs/website-ui-source-summary.json`, and its release/signature/device-install records.

Earlier resource results use `Logs/resource-optimization-tests-summary.json`, `Logs/resource-optimization-delivery-summary.json`, `Logs/resource-device-delivery-summary.json`, and the functional/OCR/native/TTS/normal-preparation device records. Compact-memory results use `Logs/memory-delivery-summary.json`, `Logs/memory-final-soak.json`, and `Logs/memory-constrained-fixed.json`. Earlier speech/geometry results retain their `answer-speech-*`, `native-dictation-*`, `da3-*`, `qa-*`, and `ptt-*` provenance.
