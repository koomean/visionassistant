# LunaV project status

**Evidence reviewed: 25 October 2026; the latest app checks below were recorded on 24 October.** LunaV is a research prototype. The current app uses Apple Dictation, automatic Apple-voice answer reading, and deferred model-based depth on devices without LiDAR. The latest update reduces repeated processing and releases idle model resources on lower-memory devices without changing the model weights or image resolution. Earlier Whisper results below are historical. This repository contains the website, not the app or its raw logs. [Request the app source](https://shorturl.koomean.com/sourcecodevisionassistant) through the project’s registration/request form; this is not an immediate download.

## Ask, read, and listen

Hold the centre button to start photo/depth capture and microphone recording together, after microphone permission is granted. Speak while holding, then release to stop recording and submit when the image is ready. Silence while holding does not submit. A short tap takes a photo only. Recordings over the **2-minute limit** are explicitly rejected.

**Apple DictationTranscriber through SpeechAnalyzer now handles speech input.** Thai is the default; select English in Settings. A request uses one selected language, without an automatic language-switching claim. The app checks device/locale support and installed assets. A missing Apple language asset may require an initial download. Question transcription uses installed assets locally and has a **45-second deadline**. Whisper is no longer in the current app bundle.

Completed AI, OCR, summary, and distance answers are read automatically by default with **installed Apple voices**. Settings can turn reading off, select Thai/English voices, and play a voice preview. Reading stops before new capture/recording, cancellation, context clearing, or backgrounding. The app does not promise access to the user's Siri voice. Additional enhanced/premium voices can be installed through iOS Settings; the app uses voices already available on that device.

Apple Vision OCR and the existing Qwen3-VL-2B-Instruct/MLX/Metal visual-question pipeline remain local. Settings tools support region selection, text grouping for signs/menus/labels, and summarisation of selected OCR text. The app has no continuous obstacle-alert or directional-navigation feature.

## Distance and its source

On a **LiDAR-equipped device**, supported captures use sensor depth paired with the photograph. The reading is camera-to-surface distance at capture time. These devices skip Depth Anything 3 loading, including front-camera use or a failed LiDAR capture; a failed sensor reading is not silently replaced with a model estimate labelled as LiDAR.

On a **device without LiDAR**, bundled **Depth Anything 3 Metric** estimates a depth map from the newly captured image **when a distance question or manual point selection needs it**, rather than for every ordinary photo. A successful map is reused for later distance questions about the same capture; a temporary prediction failure can be retried. Image alignment and lens focal information are used to produce metre estimates; missing lens information, sky, and invalid values can prevent a reading. Answers identify the model source and round estimates to 0.1 metre. This is an estimate, not a LiDAR measurement or a certified accuracy figure. Imported images without paired depth do not produce numeric distances.

Settings can fit a per-camera scale from a measured camera-to-surface reference of **0.3–8 metres** near the centre of the captured image. A scale adjustment can reduce a consistent bias for that camera, but does not validate other scenes or establish an uncertainty bound. **DA3 has not been compared against measured physical reference distances on the delivered iPhone app.**

## Preparation and availability

The app prepares visual models before enabling questions, and automatically retries transient preparation failures while in the foreground. DA3 is prepared only when the device has no LiDAR. Model residency depends on memory headroom and the limits iOS grants the app; warming does not mean weights remain in RAM indefinitely.

Speech preparation has a **30-second deadline**. If the selected Dictation language is unavailable or preparation fails, the app reports it and retries speech separately. Photos, typed questions, OCR, and summaries remain usable once their required visual models are ready. Finishing cleanup of a cancelled native-speech request does not block typed visual questions.

The project currently targets **iOS 27 and Xcode 27 or later**. Dictation support varies by device and language; Qwen and DA3 still require sufficient memory and supported hardware. No claim is made that every iPhone meeting the operating-system target has passed testing.

## Resource use between questions

Lower-memory devices use visual-model weights only while processing. The compact policy applies at 6 GiB of physical RAM or below, or when reported process headroom is positive but below 1 GiB. Idle weights are released before a new capture and after answers, while lightweight image identifiers and bounded text context can rebuild a follow-up. This costs another weights load between questions; it does not make inference fit within any amount of RAM.

OCR runs before a cold visual-model load, with a bounded result cache for the current image. One CPU tokenizer cache avoids repeated vocabulary parsing and can be reclaimed under pressure. DA3 predictions are deferred until needed and its weights are released when the compact policy requires it. Startup remembers completed warmup stages separately from currently resident weights, so returning from background does not repeat every successful warmup.

Cancellation and memory-warning cleanup follow running work before models reload. An in-flight model call may still own its buffers until it returns; there is no promise of immediate or complete RAM release. Native-speech cleanup does not reserve the visual-model memory needed for typed questions. The optimisation retained the existing models, weights, quantisation, image resolution, answer checks, and memory-admission safeguards.

## Latest resource checks — recorded 24 October, reviewed 25 October 2026

| Check | Recorded result | Scope and limit |
| --- | --- | --- |
| Resource-optimisation Simulator regression | **259/259 passed: 248 unit + 11 UI**, no failures, skips, or recorded runtime warnings | Production-path regression recorded before the later device diagnostics and cheap headroom-check ordering were included in the final signed device build. No new app suite was run for this website update. |
| Signed Release on iPhone 14 / iOS 27.2 | Strict deep signature verification and installation passed; returned to normal mode with image and speech preparation ready and no diagnostic launch arguments | This later non-LiDAR device check supersedes the earlier step where iPhone 14 Pro was unavailable. It is not a fresh iPhone 14 Pro test. |
| Two real-camera question cycles | Capture → Apple Dictation from recorded speech fixtures → VLM/TTS completed without retries, fallback, or memory refusal in those cases | Real camera captures with file-based speech input, not a live-human microphone test or semantic accuracy benchmark. |
| Deferred and reused DA3 map | Two ordinary photos triggered **0** predictions. Manual depth followed by an automatic range question on the same photo used **1** prediction; pairing with capture time and lens data was checked | No known reference distance was available. Calibration was not changed and physical metre accuracy was not established. |
| Two fixed-image OCR questions | OCR ran before large-model loading; the second question hit the same-image OCR cache | Confirms processing order and cache use for those cases, not that every answer is semantically correct. |
| Native speech and answer reading | Five Thai/English speech fixtures returned text; silence and white noise were rejected. **3** TTS completion cases and record-session handoff succeeded | Fixed recordings and system synthesis callbacks; not human speech accuracy, human-heard playback, or Silent-switch validation. |
| Observed process footprint in that functional check | Peak **2.394 GB**; settled after TTS/range **96.7–117.6 MB**, using decimal units | Sampled app-process values include diagnostics overhead and exclude separate iOS speech services. This is not a controlled before/after savings figure or a long-duration result. |

The latest check was a small set of functional cases. **No new long-duration soak, controlled memory-savings comparison, battery-life measurement, or thermal benchmark was performed for this resource-optimisation build.** It does not establish that memory refusals can never recur or that AI is correct on every image.

## Earlier compact-memory device run — 24 October 2026

This was a preceding build on **iPhone 14 Pro**, separate from the later iPhone 14 functional check above. It completed **30/30 cycles in 545.8 seconds**, with a fresh real RGB/depth capture each time, recorded Thai speech input, and answer reading enabled. No insufficient-memory refusal or app stop was recorded during that run. **15 cycles returned a safe fallback after model retry**, so completion does not mean 30 correct answers or 30 successfully spoken model answers.

The app-process footprint after each cycle was **91.6–225.8 MiB, median 155.9 MiB**; sampled inference peak was about **2.47 GB**. Settled footprint rose during the run, and a serious thermal state was observed. These are bounded observations, not proof of an hours-long memory plateau, better battery life, or unlimited operation. Measurements exclude separate iOS speech-service processes.

A separate **controlled three-cycle constraint test** for that preceding build compared roughly **1.9 GiB** baseline app footprint after speech with **61–66 MiB** in compact mode. This describes that test setup, not a universal savings percentage or the measured footprint of the latest build. Model weights still have to load during inference. One injected memory warning also recovered in the earlier test; it was a deliberate recovery check, not a new spontaneous system warning.

## Earlier speech feature checks — 24 October 2026

Before the memory/resource changes, the answer-reading update passed **224 unit tests**. Its initial full run passed 10 of 11 UI cases; an old idle-state expectation was revised for answer playback and the focused OCR/two-button rerun passed 2/2. The earlier Dictation suite passed **220/220 (209 unit + 11 UI)**, plus 6 native-integration cases in a separate run. These are historical runs, not additional tests to add to the latest 259.

On iPhone 14 Pro / iOS 27.0.1, five synthetic Thai/English speech files returned text and two non-speech files were rejected. A 41-second file retained speech before and after the 30-second point. Normal startup and three installed-voice completion/session cases were also checked. Language assets were already present. These results do not certify human speech accuracy, fresh-install offline readiness, human-audible playback, or Silent-switch behaviour.

## DA3 checks and earlier evidence

The DA3 pipeline has run locally with the actual model and Qwen/Vision object selection on controlled fixtures. In three automatic-fusion cases, two target objects were located in their expected regions and an absent object was rejected. Those tests used an explicit **test focal value**. They establish routing and geometry for the fixture, not physical distance accuracy. An earlier physical iPhone 14 startup/retry check established model preparation and recovery for that version; its old Whisper-loading timings do not describe the current Dictation engine.

Earlier results are retained with their original context:

| Earlier check | Recorded result | Limit |
| --- | --- | --- |
| 23 October hold/release version | **155/155 Simulator tests: 144 unit + 11 UI** | A historical version using the former Whisper speech path, superseded by later suites. |
| 21 October VLM/OCR on Mac | **29 controlled cases: 22 correct concrete answers + 7 abstentions**; no incorrect concrete answers in that set | Six abstentions missed visible information; one declined an absent price. They are not 29 successful factual answers or a new 24 October evaluation. |
| 21 October Whisper synthetic speech | 12/12 speech inputs accepted; **10/12 exact transcriptions** after ignoring whitespace/punctuation; 4/4 non-speech inputs rejected | Former engine and synthetic Mac corpus; not current Apple Dictation accuracy. |
| 21 October follow-up and sensor-fusion fixtures | 24 turns without recorded loop/truncation/recovery failure; 3/3 LiDAR object/depth cases with simulated depth | Sequence stability and controlled routing, not 24 correct answers or measured physical LiDAR accuracy. |

## Data handling

Image/depth inference, OCR, installed-asset question transcription, and installed-voice answer synthesis run locally without a cloud AI service or API key. **Initial Apple language-asset downloads may need network access.** The app bundles its Qwen and DA3 models; iOS manages Dictation assets and Apple voices. Fresh-install offline use is not guaranteed before required assets are present.

Audio is recorded to a temporary WAV file in the app sandbox. Its worker removes it when processing actually ends; cancellation or a timeout does not promise immediate deletion if cleanup is still running. Compressed images, previews, and crops can also be stored temporarily during use, and superseded images are cleaned up. This is not a claim that all data stays only in RAM. These statements describe the app, not the website's hosting or external links.

## Evidence provenance

Current descriptions were checked against the supplied app's `README.md`, the resource-optimisation/device sections of `VALIDATION.md`, and current speech, model-preparation, depth, and memory-policy sources. Logs below are provenance names from the app workspace; they are not files included in this website repository. This website update did not modify the app or run new app tests.

Latest results use `Logs/resource-optimization-tests-summary.json`, `Logs/resource-optimization-delivery-summary.json`, `Logs/resource-optimization-source-summary.json`, and `Logs/resource-device-delivery-summary.json`. The device details are in `Logs/resource-device-functional.json`, `Logs/resource-device-ocr.json`, `Logs/resource-device-native.json`, `Logs/resource-device-tts.json`, and `Logs/resource-device-normal-preparation.json`. The device session ledger and final install/signature records identify the later hardware check.

The preceding compact-memory measurements use `Logs/memory-delivery-summary.json`, `Logs/memory-final-soak.json`, `Logs/memory-constrained-fixed.json`, and the app's memory-session ledger. Earlier speech checks retain their `answer-speech-*` and `native-dictation-*` provenance; DA3 fixture geometry uses `Logs/da3-automatic-fusion-geometry-check.json`. The 21/23 October results retain their original `qa-*` and `ptt-*` records.

## สรุปภาษาไทย

**ตรวจหลักฐานถึงวันที่ 25 ตุลาคม 2026 โดยผลแอปล่าสุดด้านล่างบันทึกวันที่ 24 ตุลาคม** รุ่นปัจจุบันใช้ **Apple Dictation บนเครื่องแทน Whisper** ค่าเริ่มต้นไทย เปลี่ยน English ได้ในตั้งค่า โดยใช้ภาษาที่เลือกทีละภาษา กดปุ่มกลางค้าง พูดระหว่างถือ แล้วปล่อยเพื่อส่ง ความเงียบไม่ส่งเอง รับเสียงไม่เกิน 2 นาที ถ้าเกินจะแจ้งข้อผิดพลาด การถอดเสียงมีเส้นตาย 45 วินาที หากไม่มี asset ภาษาของ Apple อาจต้องดาวน์โหลดตอนเตรียมครั้งแรก จึงไม่รับรองว่าเพิ่งติดตั้งแล้วจะใช้เสียงออฟไลน์ได้ทันที

**อ่านคำตอบอัตโนมัติเป็นค่าเริ่มต้น** ใช้เสียง Apple ที่ติดตั้งแล้ว อ่านเมื่อคำตอบ AI/OCR/สรุป/ระยะเสร็จ หยุดก่อนรับเสียงหรือถ่ายใหม่ ปิดหรือเลือกเสียงไทย/อังกฤษได้ในตั้งค่า ไม่อ้างว่าใช้เสียง Siri การทดสอบบน iPhone 14 Pro ได้ completion callback **3/3** และตรวจการส่งต่อ audio session แล้ว แต่ยังไม่ได้ยืนยันการได้ยินด้วยหูหรือผลสวิตช์ Silent

เครื่องไม่มี LiDAR เก็บภาพใหม่และข้อมูลเลนส์ แล้วใช้ **Depth Anything 3 Metric เมื่อถามระยะหรือเลือกจุดเอง** หากสำเร็จใช้แผนที่เดิมกับคำถามต่อในภาพเดียวกัน จึงไม่ต้องทำนาย depth ทุกภาพปกติ ระบุว่าเป็นค่าประมาณ ปัดเป็น 0.1 เมตร ปรับสเกลแยกกล้องด้วยระยะอ้างอิงกลางภาพ 0.3–8 เมตรได้ แต่ยังไม่มีผลเทียบ DA3 กับระยะกายภาพจริงของรุ่นส่งมอบ เครื่องมี LiDAR ข้าม DA3 รวมทั้งตอนใช้กล้องหน้าหรือจับ depth ไม่สำเร็จ ภาพนำเข้าที่ไม่มีคู่ depth ไม่ตอบระยะเป็นตัวเลข

รุ่นลดงานซ้ำใช้โมเดล/weights/ความละเอียดเดิม จัด OCR ก่อนโหลด VLM เก็บ cache ข้อความ/OCR/tokenizer แบบมีขอบเขต และคืน weights เมื่อว่างในเครื่อง RAM น้อย จึงมีต้นทุนโหลด weights ใหม่ระหว่างคำถาม ก่อนโหลดใหม่ต้องรอให้งานที่ยังถือทรัพยากรคืนจริง การยกเลิกไม่รับประกันคืน RAM ทันที และหากงบยังไม่พอก็ยังปฏิเสธได้อย่างปลอดภัย

ผล regression รุ่นลดงานซ้ำ **259/259 ผ่าน (unit 248 + UI 11)** ไม่มี fail/skip และ build/ลายเซ็นผ่าน ต่อมาติดตั้งและคืนสู่โหมดปกติพร้อมใช้บน **iPhone 14 ที่ไม่มี LiDAR / iOS 27.2** แล้ว ตรวจกล้องจริง 2 รอบโดยใช้ไฟล์เสียงตัวอย่างกับ VLM/TTS และ OCR ภาพทดสอบ 2 คำถาม ภาพปกติ 2 ภาพไม่เรียก DA3; manual ตามด้วยถามระยะอัตโนมัติในภาพเดิมใช้ prediction เดียว ข้อมูลนี้เกิดหลังขั้นที่ iPhone 14 Pro unavailable จึงไม่ใช่การติดตั้งรุ่นล่าสุดบน 14 Pro

ค่า process ที่สังเกตในรอบฟังก์ชันล่าสุดหลังจบ TTS/ระยะอยู่ประมาณ **96.7–117.6 MB** และ peak **2.394 GB** เป็นหน่วยฐานสิบ เฉพาะ process แอป ไม่รวมบริการเสียงของ iOS และมี diagnostics ทำงาน ไม่ใช่ before/after benchmark ไม่มีการทดสอบรอบยาว แบตเตอรี่ หรือความร้อนชุดใหม่ และไม่ได้รู้ระยะอ้างอิงเพื่อยืนยันความแม่นยำ DA3

รุ่น compact ก่อนหน้านั้นบน iPhone 14 Pro จบรอบยาว **30/30 ใน 545.8 วินาที** ด้วยภาพ RGB/depth จริง เสียงจากไฟล์ตัวอย่าง และเปิด TTS แต่ **15 รอบเป็น safe fallback** จึงไม่ใช่คำตอบถูก 30/30 ค่าหลังจบรอบ median155.9 MiB และยังเพิ่มขึ้นระหว่างรัน จึงไม่รับประกันใช้ได้ไม่สิ้นสุด ผลเทียบประมาณ1.9 GiBกับ61–66 MiBมาจากการจำกัดงบแบบควบคุม 3 รอบของรุ่นก่อน ไม่ใช่ผลลด RAM สากลของรุ่นล่าสุด

ยังใช้ Apple Dictation ภาษาที่เลือกและเสียง Apple ที่ติดตั้งแล้วตามเดิม หากเสียงไม่พร้อมยังใช้ภาพ พิมพ์ถาม และ OCR ได้เมื่อโมเดลที่ต้องใช้พร้อม ไฟล์เสียงชั่วคราวลบเมื่องานจบจริง ผลเสียงไฟล์ตัวอย่างกับ TTS completion ไม่ใช่การยืนยันเสียงคนจริงหรือการได้ยินด้วยหู

ผล VLM/OCR **22 คำตอบตรง + 7 ปฏิเสธ จาก 29 กรณี** และ Whisper **ถอดตรง 10/12** เป็นประวัติวันที่ 21 ตุลาคม ไม่ใช่ผลของ Dictation รุ่นปัจจุบัน หลักฐานที่ระบุเป็นไฟล์ใน workspace แอปและไม่ได้รวมใน repo เว็บไซต์ ติดต่อผ่าน[แบบฟอร์มลงทะเบียนขอซอร์สแอป](https://shorturl.koomean.com/sourcecodevisionassistant)ได้ โดยไม่ใช่ลิงก์ดาวน์โหลดทันที
