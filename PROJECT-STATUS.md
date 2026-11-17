# LunaV project status

LunaV **3.2.1 (build 6)** is the current iPhone research prototype. [Download the source on GitHub](https://github.com/koomean/visionassistant/releases/tag/v3.2.1-source).

## Latest test results

### iPhone Simulator — 12 November 2026

This run checked text reading and version information on an iPhone 17 Simulator with iOS 27.2.

| Test | Passed | What we checked |
| --- | ---: | --- |
| Unit tests | **21/21** | Reading documents, headings and specific fields, plus the packaged version number. |
| Screen tests | **2/2** | Asking LunaV to read a label heading or a specific price. Camera and speech inputs were simulated. |
| Total | **23/23** | No failures, skipped tests or recorded runtime warnings. |

The label-heading check failed in an earlier run that evening and passed in this run.

### Component tests on Mac — 16 November 2026

These tests used images and recordings on an Apple silicon Mac with macOS 27.2.1. OCR turns text in a photo into readable text. CER measures errors per character. WER measures errors per word. Lower rates are better.

| Test | What we used | Result |
| --- | --- | --- |
| Read text | 514 text crops from [TEMS v5](https://data.mendeley.com/datasets/ntdmgksh9w/5) | **3.07% CER**. Exact text on **434/514** images. |
| Answer questions about images | 150 questions from [VizWiz VQA](https://vizwiz.org/tasks-and-datasets/vqa/) | **56.07%** under VizWiz’s scoring method. |
| Find objects | 50 generated test scenes | **39/50 (78%)** matched the expected response. |
| Transcribe Thai speech | 50 Thai clips from [FLEURS](https://huggingface.co/datasets/google/fleurs) | **10.73% CER**. All 50 clips returned text. |
| Transcribe English speech | 50 US English clips from [FLEURS](https://huggingface.co/datasets/google/fleurs) | **22.68% CER**, **28.00% WER**. Ten clips returned no text. |
| Summarise documents | 8 generated document images | **18/27 facts** kept. **3/8** summaries kept every expected fact. |

- **Reading text.** Apple Vision output needed 263 edits to match 8,571 reference characters. WER was 10.64%, counting words split by spaces. Eight blank results counted as deletions. CER by group was 2.41% on Thai (258 images), 0.83% on English (188), 8.36% on mixed Thai and English (63), and 0.00% on numbers and symbols (5).
- **Visual questions.** Qwen3-VL-2B-Instruct 4-bit (MLX) scored 48.10% on 100 answerable questions and 72.00% on 50 unanswerable ones. It answered `unanswerable` 13 and 35 times in those groups, respectively. One image below the model’s minimum height scored zero.
- **Finding objects.** Left 10/10, right 10/10, centre 4/10, absent 10/10 and multiple matches 5/10. The other six centre cases prompted the user to aim again.
- **Speech.** Apple Dictation output needed 628 edits across 5,854 Thai reference characters and 1,139 across 5,023 English characters. The ten blank English results counted as deletions. CER on the 40 English clips with text was 5.36%.
- **Summaries.** One person checked the results. Examples of mistakes include changing a Friday appointment time and misidentifying a water label even though OCR read both correctly.

The exploratory 95% ranges were **1.93–4.60% CER** for TEMS and **49.00–63.07%** for VizWiz. The TEMS bootstrap grouped text crops by source photo. The v5 metadata lists 112 test-photo IDs and the paper lists 162. Match those IDs before comparing scores directly. VizWiz and FLEURS used random seed 2027. Live microphone accuracy, end-to-end offline use, iPhone response times and battery life still need separate tests.

### Distance on two iPhones — 16 November 2026

A Release build set up to record test data took five photos per phone in one scene with a white jar. The iPhone 14 Pro measured depth with its rear LiDAR sensor. The iPhone 14 estimated depth with Depth Anything 3 (DA3), using scale 1.0 and the camera’s lens data. Both phones returned distances at five points per frame. The usual DA3 preparation reported the model as busy, so the test called the camera, image preparation and model directly and used the app’s standard distance reader.

| Point in the photo | LiDAR median (m) | DA3 median (m) | Mean DA3 − LiDAR (cm) |
| --- | --- | --- | --- |
| Jar surface | 0.659 | 0.484 | −17.5 |
| Upper left | 0.813 | 1.131 | +31.8 |
| Upper right | 0.869 | 0.772 | −9.7 |
| Lower left | 0.574 | 0.410 | −16.4 |
| Lower right | 0.648 | 0.427 | −22.1 |

The average size of the gap was **19.5 cm across 25 pairs** and **17.5 cm** at the jar surface. A negative number means DA3 estimated a shorter distance. Different frame shapes can put the corners on different spots. The test used LiDAR as the reference in this one scene. Measuring error against the true distance requires separate physical measurements.

## Reading and device details

- **Read a label or a specific detail.** “Read the label” usually reads the most prominent text first. You can ask for all the text, name a field, or specify an area, such as “Read the price on the right.” LunaV may ask which detail you mean if several match.
- **Ask a follow-up.** Turn on **Reuse the photo on hold** in Settings or use the shutter’s VoiceOver follow-up action. Tap briefly to take a new photo. The object finder takes a fresh photo and describes the object’s position in the frame. It can play a short tone or vibrate when the object is centred on supported devices.
- **Choose a language.** Go to **Settings → App language** to change the buttons and menus. Your choice is saved. Dictation, answers and reading voices have their own settings. Existing questions, answers and text read from photos stay in their original language. Find the installed version under **Settings → About → About LunaV**.
- **Timing and speech.** Dictation has 30 seconds to prepare and 45 seconds to transcribe a recording. When voice input is unavailable, you can still take photos, type questions, read text, and summarise once the required models are ready.
- **Check a distance.** LunaV shows which source it used. LiDAR readings need matching sensor data. DA3 estimates use a photo and lens data and are calculated when needed. Imported photos need paired depth for a numeric reading. A compatible rear LiDAR iPhone can also vibrate during the live preview when a central obstacle comes closer. The optional setting defaults to a 2 m start, 0.4 m for the strongest pulse and 80% maximum strength. Capture, processing, backgrounding or high temperature pauses the feature. Haptic strength and finder tones still need physical-device checks.

On phones with 6 GiB of RAM or less, or when the app has less than 1 GiB of available memory, LunaV can unload idle models and reload them as needed. For iOS, Xcode, and model requirements, see [Supported devices](devices.html).

Camera, Settings and About previews on the site show version **3.0.0** from 29 October 2026. [See screenshot credits](ASSET-CREDITS.md).

## Earlier tests

| Version or date | Simulator or Mac | Build or physical device |
| --- | --- | --- |
| 3.2.0 build 5 · 11 November | **288/288** on iPhone 17 Simulator with iOS 27.0 (285 unit and 3 screen tests). Four Mac finder prompts checked right, centre, multiple matches and no match. | An unsigned iOS Release built successfully. |
| 3.1.0 build 4 · 11 November | **2/2** iPhone Duo layout checks, **271** unit tests and **7/7** landscape checks. The sensor and vibration checks used simulated input. | An unsigned iOS Release built successfully. |
| 3.0.0 build 3 · 29 October | **269/269** on Simulator (253 unit and 16 screen tests), plus **2/2** for language and version information. | The iOS Release signature passed verification. Installation on an iPhone 14 was cancelled after more than three minutes without progress. |
| Lunar interface · 29 October | **262/262** Simulator tests (249 unit and 13 screen tests). | The Release signature passed verification. An iPhone 14 lost its connection during installation (CoreDevice 4000). |
| Memory optimisation · 24 October | **259/259** Simulator tests (248 unit and 11 screen tests) before final diagnostics changes. | A signed Release installed on an iPhone 14 with iOS 27.2. Two real-camera question cycles completed with recorded speech. One depth estimate was reused for two checks on the same photo. |

On the 24 October build, measured app memory peaked at **2.394 GB** and fell to **96.7–117.6 MB** after reading or distance checks. The figures cover the app process.

An earlier compact build completed **30/30** cycles on an iPhone 14 Pro in **545.8 seconds** with real camera captures and recorded speech. **15 cycles returned a fallback message** after retry. Settled app memory was **91.6–225.8 MiB** (median **155.9 MiB**) and peaked at about **2.47 GB**. Memory rose during the run and the phone reached a serious thermal state. The 24 October speech checks used recordings, so hearing the spoken answer and using the Silent switch still need separate checks.

## Where the app processes data

If you cancel a request or it times out, LunaV deletes temporary audio once the background processing ends. See [privacy](./#privacy) for how the app handles photos and voice input.

## Test records

The app workspace holds the original records. The current version comes from `App/project.yml`, the Simulator run from `Test-LunaV-2569.11.12_21-55-17-+0700.xcresult`, and the two 16 November results from `Test/Mac-Benchmark-2026-11-16/` and `Test/iPhone-Distance-2026-11-16/`. Earlier checks are recorded in the app’s `VALIDATION.md` and `Logs/` folders.
