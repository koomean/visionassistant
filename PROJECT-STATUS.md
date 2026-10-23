# LunaV project status

**Evidence reviewed: 23 October 2026.** LunaV is a research prototype. This report separates the current hold-to-talk update from the earlier 21 October model and speech fixtures. The app source and raw logs are not included in this website repository. Evidence filenames below identify the supplied app workspace records, not downloadable files here. [Request the app source](https://shorturl.koomean.com/sourcecodevisionassistant) through the project’s registration/request form; this is not an immediate source download.

## Current implementation

**Hold the centre button, speak while holding, then release to submit.** Pressing starts photo/depth capture and microphone recording together, after microphone permission has been granted. Releasing stops recording immediately; transcription waits for the image to be ready. Silence while holding does not submit the question. A short tap still takes a photograph without submitting a voice question.

Recordings can be up to **2 minutes**. Longer recordings are rejected with a request to ask a shorter question, rather than submitting only the beginning. During speech preparation, transcription, and answering, the centre button can cancel the request. Status messages show the current stage and elapsed time. The transcription screen waits no more than 120 seconds for the whole speech-processing task, including model preparation. Cancelling or reaching that deadline returns control without showing a late answer. Core ML may still need time to finish internally; model-dependent actions wait for that cleanup before starting another large model.

LunaV displays the transcript and answer as text. It uses bundled Whisper large-v3 turbo/Core ML for transcription, Qwen3-VL-2B-Instruct/MLX/Metal for visual questions, and Apple Vision for OCR. Settings contains region selection, text reading and summarisation, grouping for signs/menus/labels, and optional manual LiDAR-point selection.

On a supported rear LiDAR camera, distance questions use depth associated with the captured photograph. The reported distance is from the camera to an object's surface at capture time. The app rejects unavailable or ambiguous measurements instead of inventing a metric distance. Its accepted 0.2–5 metre range is an application validation bound, not a certified accuracy range. Non-LiDAR cameras still support visual questions. The current project targets iOS 27 and Xcode 27 or later; available memory and hardware determine whether models can run.

## Latest recorded checks — 23 October 2026

| Check | Recorded result | What it establishes |
| --- | --- | --- |
| iOS 27 Simulator suite | **155/155 passed: 144 unit tests and 11 UI tests**, with no skips, failures, or recorded runtime warnings | The exercised software and UI paths passed on Simulator. These results supersede the earlier 134-test suite. |
| Hold/release and cancellation UI | Three UI cases exercised hold then release, short tap without a voice submission, cancellation, rejection of a late result, and retry | The real screen and request flow were exercised with simulated camera, audio, and transcription boundaries in Debug Simulator; these are not live microphone or camera results. |
| Unresponsive speech work | Tests covered prompt return on cancellation/deadline, deletion of audio after the worker actually finishes, and preventing overlapping model loads | Software lifecycle checks, not a reproduction of a physical iPhone stall. |
| Offline Core ML transcription on Mac | Two short English/Thai transcripts matched their earlier baseline; a 41-second synthetic recording retained the question at both its beginning and end; silence/noise were rejected; a 121-second recording was explicitly rejected | The local speech path was exercised with network access denied. Matching the Thai baseline does not mean its earlier spelling errors were corrected. This is not real-voice or iPhone validation. |
| Transcription timeout recovery | Two consecutive short-budget calls timed out without leaving model access permanently occupied | The timeout and cleanup path recovered in this controlled check; it is not a guarantee that Core ML stops immediately. |
| Signed iPhone Release | Build and strict code-signature verification succeeded; Simulator-only voice-test flags were absent from the executable | A signed device build was produced. The latest live camera, microphone, LiDAR, inference speed, memory, and thermal behaviour remain **unverified on a physical iPhone**. |

The user's iPhone was unavailable during this validation run. The current hold/release interaction and speech fixes have not been reproduced on that physical device. Simulator and Mac results, synthetic speech, and simulated depth must not be presented as measured iPhone performance.

## Earlier model and speech fixtures — 21 October 2026

These recorded results describe the earlier evaluation corpus. They are retained as historical evidence and have not been relabelled as new 23 October accuracy tests.

| Check | Earlier recorded result | Limit |
| --- | --- | --- |
| VLM/OCR on Mac | **29 controlled cases: 22 correct concrete answers and 7 abstentions**; no incorrect concrete answers in that set | Seven abstentions are not seven successful factual answers. Six declined despite visible information; one correctly declined a price not printed in the image. The fixtures do not establish general accuracy. |
| Follow-up stability | 24 turns completed without recorded looping, truncation, or recovery failure | Stability for that sequence, not 24 factually correct answers. |
| Offline synthetic speech on Mac | 12/12 speech inputs accepted; **10/12 exact transcriptions** after ignoring whitespace/punctuation; 4/4 non-speech inputs rejected, with network denied by sandbox | Two Thai inaccuracies remained. This corpus did not validate human voices or all accents. |
| LiDAR object/depth fusion | 3/3 controlled cases using the real model and Vision with **simulated depth** | Controlled matching and rejection paths, not a physical LiDAR accuracy measurement. |

OCR, object selection, transcription, and generated answers can still be wrong. The current project does not implement spoken answer playback, continuous obstacle alerts, directional audio guidance, or non-LiDAR metric depth estimation.

## Data handling

App inference runs locally and does not require a cloud AI service or an API key. Speech is recorded to a temporary file in the app sandbox. The file is removed when the transcription worker actually finishes. If cancellation or a timeout returns control before Core ML has finished, that worker keeps the file until it can safely clean up; cancellation does not promise instant deletion.

Compressed images, previews, and crops can also be stored temporarily in the sandbox during use; the implementation cleans up superseded images. This is not a claim that all data stays only in RAM or that the operating system never writes temporary files. This paragraph describes the iPhone app, not the hosting and external links of this website.

## Evidence provenance

The supplied app's `README.md`, `VALIDATION.md` (23 October update and separate 21 October history), and `project.yml` describe the implementation and configured targets. Current results were cross-checked with `Logs/ptt-delivery-summary.json`, `Logs/ptt-asr-fixed-summary.json`, and `Logs/ptt-release-test-hook-check.json`. The app validation record also identifies `Logs/ptt-delivery-iphone-build.log`, `Logs/ptt-delivery-signature.log`, and the speech deadline and ASR audits.

The 21 October figures come from `Logs/qa-delivery-native-summary.json`, `Logs/qa-voice-final-summary.json`, `Logs/qa-context-fixed-stress.json`, and `Logs/qa-object-fusion-native.json`. Hold/release behaviour and audio cleanup were checked against `LunaV/VoiceCameraFlow.swift`, `LunaV/LocalSpeechRecognizer.swift`, and `LunaV/LocalSpeechDecoder.swift`; image temporary-file behaviour is in `LunaV/PhotoStore.swift`.

## สรุปภาษาไทย

**ตรวจหลักฐาน ณ วันที่ 23 ตุลาคม 2026** โครงการยังเป็นต้นแบบวิจัย วิธีถามปัจจุบันคือ **กดปุ่มกลางค้างไว้ พูดระหว่างถือ แล้วปล่อยเพื่อส่ง** แอปเริ่มถ่าย RGB/depth และรับเสียงพร้อมกันหลังได้รับสิทธิ์ไมค์ ไม่ต้องรอเตรียมภาพเสร็จ ปล่อยแล้วหยุดรับเสียงทันทีและรอภาพพร้อมก่อนถอดเสียง ความเงียบระหว่างถือไม่ส่งคำถามเอง แตะสั้นยังใช้ถ่ายภาพอย่างเดียวได้

คำถามยาวได้ไม่เกิน **2 นาที** หากเกินจะแจ้งให้ถามสั้นลงและไม่ส่งเฉพาะต้นประโยค ระหว่างเตรียมเสียง ถอดเสียง หรือตอบ ปุ่มกลางใช้ยกเลิกได้ หน้าจอแสดงขั้นตอนและเวลาที่ผ่านไป การรอถอดเสียงรวมเตรียมโมเดลมีเพดาน 120 วินาที ยกเลิกหรือหมดเวลาแล้วไม่รับผลเก่ามาแสดง แต่ Core ML อาจยังทำงานภายใน จึงต้องรอคืนทรัพยากรก่อนเริ่มโมเดลใหญ่งานใหม่ ไฟล์เสียงชั่วคราวถูกลบเมื่องานเดิมสิ้นสุดจริง ไม่ได้รับประกันว่าจะลบทันทีที่กดยกเลิก

ผลล่าสุดวันที่ 23 ตุลาคมคือ Simulator **155/155 ผ่าน (unit 144 + UI 11)** ไม่มี skip/fail หรือ runtime warning ที่บันทึกไว้ การกดค้าง/ปล่อยและยกเลิกทดสอบผ่านหน้าจอจริงใน Simulator โดยจำลองขอบเขตกล้อง เสียง และ ASR ส่วน Core ML บน Mac ที่ปิดเครือข่ายเก็บทั้งคำถามต้นและท้ายของไฟล์เสียงสังเคราะห์ 41 วินาทีได้ ปฏิเสธไฟล์ 121 วินาทีอย่างชัดเจน และตรวจการคืนทรัพยากรหลัง timeout แล้ว

ผล **Mac VLM/OCR 29 กรณี: ตอบตรง 22 และปฏิเสธตอบ 7** กับ **เสียงสังเคราะห์ถอดตรง 10/12** เป็นหลักฐานเดิมวันที่ **21 ตุลาคม** ไม่ใช่ผลทดสอบความแม่นยำชุดใหม่ ผล 7 กรณีที่ปฏิเสธไม่ใช่คำตอบข้อเท็จจริงสำเร็จ และคำถอดเสียงไทยที่คลาดเคลื่อนยังไม่ได้รับการรับรองว่าแก้แล้ว

รุ่นล่าสุด **build และตรวจลายเซ็นสำหรับ iPhone ผ่าน** แต่เครื่องจริง unavailable จึงยังไม่ได้ยืนยันกล้อง ไมค์ LiDAR หรือ inference สดของรุ่นนี้ ผลบน Mac, Simulator, เสียงสังเคราะห์ และ depth จำลองไม่ใช่ผลความแม่นยำ ความเร็ว หรือความร้อนบน iPhone แอปกำหนด iOS 27 / Xcode 27 ขึ้นไปและต้องมีหน่วยความจำเพียงพอ ยังไม่มีการอ่านคำตอบออกเสียง เตือนสิ่งกีดขวางต่อเนื่อง เสียงนำทาง หรือเดาระยะเป็นเมตรในเครื่องไม่มี LiDAR

หลักฐานมาจากเอกสารและไฟล์ที่ระบุด้านบนใน workspace แอป ไม่ได้รวมไฟล์เหล่านั้นไว้ใน repo เว็บไซต์ สามารถใช้[แบบฟอร์มลงทะเบียนขอซอร์สแอป](https://shorturl.koomean.com/sourcecodevisionassistant)เพื่อติดต่อโครงการได้ ช่องทางนี้เป็นแบบฟอร์มคำขอ ไม่ใช่ลิงก์ดาวน์โหลดซอร์สแอปทันที
