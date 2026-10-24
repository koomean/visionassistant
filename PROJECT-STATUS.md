# LunaV project status

**Evidence reviewed: 24 October 2026.** LunaV is a research prototype. The current app uses Apple Dictation, automatic Apple-voice answer reading, and model-based depth on devices without LiDAR. Earlier Whisper results below are historical. This repository contains the website, not the app or its raw logs. [Request the app source](https://shorturl.koomean.com/sourcecodevisionassistant) through the project’s registration/request form; this is not an immediate download.

## Ask, read, and listen

Hold the centre button to start photo/depth capture and microphone recording together, after microphone permission is granted. Speak while holding, then release to stop recording and submit when the image is ready. Silence while holding does not submit. A short tap takes a photo only. Recordings over the **2-minute limit** are explicitly rejected.

**Apple DictationTranscriber through SpeechAnalyzer now handles speech input.** Thai is the default; select English in Settings. A request uses one selected language, without an automatic language-switching claim. The app checks device/locale support and installed assets. A missing Apple language asset may require an initial download. Question transcription uses installed assets locally and has a **45-second deadline**. Whisper is no longer in the current app bundle.

Completed AI, OCR, summary, and distance answers are read automatically by default with **installed Apple voices**. Settings can turn reading off, select Thai/English voices, and play a voice preview. Reading stops before new capture/recording, cancellation, context clearing, or backgrounding. The app does not promise access to the user's Siri voice. Additional enhanced/premium voices can be installed through iOS Settings; the app uses voices already available on that device.

Apple Vision OCR and the existing Qwen3-VL-2B-Instruct/MLX/Metal visual-question pipeline remain local. Settings tools support region selection, text grouping for signs/menus/labels, and summarisation of selected OCR text. The app has no continuous obstacle-alert or directional-navigation feature.

## Distance and its source

On a **LiDAR-equipped device**, supported captures use sensor depth paired with the photograph. The reading is camera-to-surface distance at capture time. These devices skip Depth Anything 3 loading, including front-camera use or a failed LiDAR capture; a failed sensor reading is not silently replaced with a model estimate labelled as LiDAR.

On a **device without LiDAR**, bundled **Depth Anything 3 Metric** estimates a depth map from the newly captured image. Image alignment and lens focal information are used to produce metre estimates; missing lens information, sky, and invalid values can prevent a reading. Answers identify the model source and round estimates to 0.1 metre. This is an estimate, not a LiDAR measurement or a certified accuracy figure. Imported images without paired depth do not produce numeric distances.

Settings can fit a per-camera scale from a measured camera-to-surface reference of **0.3–8 metres** near the centre of the captured image. A scale adjustment can reduce a consistent bias for that camera, but does not validate other scenes or establish an uncertainty bound. **DA3 has not been compared against measured physical reference distances on the delivered iPhone app.**

## Preparation and availability

The app prepares visual models before enabling questions, and automatically retries transient preparation failures while in the foreground. DA3 is prepared only when the device has no LiDAR. Model residency depends on memory headroom and the limits iOS grants the app; warming does not mean weights remain in RAM indefinitely.

Speech preparation has a **30-second deadline**. If the selected Dictation language is unavailable or preparation fails, the app reports it and retries speech separately. Photos, typed questions, OCR, and summaries remain usable once their required visual models are ready. Finishing cleanup of a cancelled native-speech request does not block typed visual questions.

The project currently targets **iOS 27 and Xcode 27 or later**. Dictation support varies by device and language; Qwen and DA3 still require sufficient memory and supported hardware. No claim is made that every iPhone meeting the operating-system target has passed testing.

## Current recorded checks — 24 October 2026

| Check | Recorded result | Scope and limit |
| --- | --- | --- |
| Latest answer-speech unit checks | **224/224 unit tests passed** | This is the unit result, not a claim that one combined 235-test run passed. |
| Answer-speech UI checks | The first full run passed **10/11 UI tests**. An old idle-state expectation was revised for automatic answer reading; the focused OCR/two-button rerun passed **2/2** | The initial full run was 234 passed and 1 failed. The targeted correction is reported separately rather than rewriting that run as 235/235. |
| Dictation regression checks | **220/220 passed: 209 unit + 11 UI**, with no skips/failures; **6/6** native-integration checks passed in a separate run | Earlier runs for the Dictation update, separate from the latest answer-speech suite. Counts must not be added into one full-suite total. |
| Dictation on iPhone 14 Pro / iOS 27.0.1 | **7/7 expected outcomes:** five synthetic Thai/English speech files returned text and silence/white-noise files were rejected | Real device, synthetic audio files. This is not a seven-question accuracy score or live human-microphone validation. |
| Longer Dictation file on that iPhone | A 41-second synthetic file retained the questions before and after the 30-second point | Confirms that test file's later speech reached the transcript; it is not proof that every two-minute question reaches AI without other limits. |
| Normal iPhone 14 Pro startup | Image and selected-language speech preparation reported ready; DA3 was skipped for LiDAR hardware; no pending worker or injected validation error | The language assets were already installed on this device. This does not establish first-use offline readiness on another phone. |
| Apple answer reading on iPhone 14 Pro | **3/3 synthesis completion callbacks**, using installed Kanya Enhanced and Allison Enhanced; stopping before record-session activation and session release succeeded | The check exercised actual system speech/session paths but did not record microphone input. No human-heard playback or Silent-switch behaviour was verified. |
| Signed latest iPhone Release | Build and strict deep code-signature checks passed; installed and launched normally on iPhone 14 Pro | Build/startup evidence does not certify all live camera, human speech, physical distance, thermal, or accessibility behaviour. |

The current device evidence replaces the earlier statement that no physical phone was available. It still has the specific limits above. In particular, model, OCR, transcription, and object-selection errors remain possible.

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

Current descriptions were checked against the supplied app's `README.md`, the 24 October sections of `VALIDATION.md`, and current speech, model-preparation, depth, and calibration sources. Logs are provenance names from that app workspace; they are not files included in this website repository.

The latest speech checks use `Logs/answer-speech-full-summary.json`, `Logs/answer-speech-delivery-summary.json`, `Logs/answer-speech-ui-readiness-summary.json`, and `Logs/answer-speech-device-result.json`. Dictation results use `Logs/native-dictation-fixed-tests-summary.json`, `Logs/native-pending-observation-summary.json`, `Logs/pro-native-fixed-validation.json`, `Logs/pro-native-long-validation.json`, and `Logs/pro-native-final-normal-preparation.json`. Device build/signature/normal-launch records are identified in the app validation report.

DA3 scope is supported by `Logs/da3-automatic-fusion-proof.json`, `Logs/da3-automatic-fusion-geometry-check.json`, and the app's depth-conversion/geometry audits. Historical figures retain their `ptt-*`, `qa-delivery-native-summary.json`, and `qa-voice-final-summary.json` provenance.

## สรุปภาษาไทย

**ตรวจหลักฐานถึงวันที่ 24 ตุลาคม 2026** รุ่นปัจจุบันใช้ **Apple Dictation บนเครื่องแทน Whisper** ค่าเริ่มต้นไทย เปลี่ยน English ได้ในตั้งค่า โดยใช้ภาษาที่เลือกทีละภาษา กดปุ่มกลางค้าง พูดระหว่างถือ แล้วปล่อยเพื่อส่ง ความเงียบไม่ส่งเอง รับเสียงไม่เกิน 2 นาที ถ้าเกินจะแจ้งข้อผิดพลาด การถอดเสียงมีเส้นตาย 45 วินาที หากไม่มี asset ภาษาของ Apple อาจต้องดาวน์โหลดตอนเตรียมครั้งแรก จึงไม่รับรองว่าเพิ่งติดตั้งแล้วจะใช้เสียงออฟไลน์ได้ทันที

**อ่านคำตอบอัตโนมัติเป็นค่าเริ่มต้น** ใช้เสียง Apple ที่ติดตั้งแล้ว อ่านเมื่อคำตอบ AI/OCR/สรุป/ระยะเสร็จ หยุดก่อนรับเสียงหรือถ่ายใหม่ ปิดหรือเลือกเสียงไทย/อังกฤษได้ในตั้งค่า ไม่อ้างว่าใช้เสียง Siri การทดสอบบน iPhone 14 Pro ได้ completion callback **3/3** และตรวจการส่งต่อ audio session แล้ว แต่ยังไม่ได้ยืนยันการได้ยินด้วยหูหรือผลสวิตช์ Silent

เครื่องไม่มี LiDAR ใช้ **Depth Anything 3 Metric จากภาพใหม่และข้อมูลเลนส์** ระบุว่าเป็นค่าประมาณ ปัดเป็น 0.1 เมตร ปรับสเกลแยกกล้องด้วยระยะอ้างอิงกลางภาพ 0.3–8 เมตรได้ แต่ยังไม่มีผลเทียบ DA3 กับระยะกายภาพจริงของรุ่นส่งมอบ เครื่องมี LiDAR ข้าม DA3 รวมทั้งตอนใช้กล้องหน้าหรือจับ depth ไม่สำเร็จ ภาพนำเข้าที่ไม่มีคู่ depth ไม่ตอบระยะเป็นตัวเลข

รุ่นอ่านคำตอบล่าสุด **unit 224/224 ผ่าน**; UI รอบแรกผ่าน 10/11 อีกข้อใช้ expectation เดิมที่รอข้อความ idle ขณะกำลังอ่านคำตอบ จึงแก้แล้วตรวจ OCR/หน้าหลักสองปุ่มซ้ำผ่าน **2/2** ไม่เรียกรอบแรกว่า 235/235 ผ่าน ส่วนชุด Dictation ก่อนหน้านั้นผ่าน **220/220 (unit 209 + UI 11)** และ native integration เพิ่ม 6/6 แยกรอบกัน บน iPhone 14 Pro / iOS 27.0.1 ไฟล์เสียงสังเคราะห์ไทย/อังกฤษได้ข้อความ 5 ไฟล์ และ silence/noise ถูกปฏิเสธ 2 ไฟล์ รวม 7 ผลตามคาด ไม่ใช่คะแนนความแม่นยำเสียงคน 7/7

รุ่นล่าสุด build เซ็น ติดตั้ง และเปิดปกติบน iPhone 14 Pro แล้ว สถานะภาพ/เสียงพร้อมและข้าม DA3 ตามฮาร์ดแวร์ แต่ยังไม่รับรอง iPhone ทุกรุ่น ความแม่นยำเสียงคน ระยะจริง ความร้อน หรือการเข้าถึงครบทุกกรณี แอปยังต้องมี iOS 27 และ RAM/Metal เพียงพอ หากเสียงไม่พร้อมยังใช้ภาพ พิมพ์ถาม และ OCR ได้เมื่อโมเดลที่ต้องใช้พร้อม งานเสียงเก่าที่กำลังคืนทรัพยากรไม่บล็อกคำถามพิมพ์ ไฟล์เสียงถูกลบเมื่องานเดิมจบจริง ไม่ได้รับประกันลบทันทีที่ยกเลิก

ผล VLM/OCR **22 คำตอบตรง + 7 ปฏิเสธ จาก 29 กรณี** และ Whisper **ถอดตรง 10/12** เป็นประวัติวันที่ 21 ตุลาคม ไม่ใช่ผลของ Dictation รุ่นปัจจุบัน หลักฐานที่ระบุเป็นไฟล์ใน workspace แอปและไม่ได้รวมใน repo เว็บไซต์ ติดต่อผ่าน[แบบฟอร์มลงทะเบียนขอซอร์สแอป](https://shorturl.koomean.com/sourcecodevisionassistant)ได้ โดยไม่ใช่ลิงก์ดาวน์โหลดทันที
