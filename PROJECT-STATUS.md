# LunaV project status

**Evidence reviewed: 21 October 2026.** LunaV is a research prototype. This report summarises the latest supplied app validation record; the app source and raw logs are not included in this website repository. Evidence filenames below identify the supplied app workspace records, not downloadable files in this repository. [Request the app source](https://shorturl.koomean.com/sourcecodevisionassistant) through the project’s registration/request form; this is not an immediate source download.

## Current implementation

LunaV captures a photograph before accepting a spoken Thai or English question and displays the transcript and answer as text. It uses bundled Whisper large-v3 turbo/Core ML for transcription, Qwen3-VL-2B-Instruct/MLX/Metal for visual questions, and Apple Vision for OCR. Settings contains region selection, text reading and summarisation, grouping for signs/menus/labels, and optional manual LiDAR-point selection.

On a supported rear LiDAR camera, distance questions use depth associated with the captured photograph. The reported distance is from the camera to an object's surface at capture time. The app rejects unavailable or ambiguous measurements instead of inventing a metric distance. Its accepted 0.2–5 metre range is an application validation bound, not a certified accuracy range. Non-LiDAR cameras still support visual questions. The current project targets iOS 27 and Xcode 27 or later; available memory and hardware determine whether models can run.

## Latest recorded checks

| Check | Recorded result | What it establishes |
| --- | --- | --- |
| iOS 27 Simulator suite | **134/134 passed: 126 unit tests and 8 UI tests**, with no skips or recorded runtime warnings | The exercised software and UI paths passed on Simulator; this is not physical-device validation. |
| VLM/OCR on Mac | **29 controlled cases: 22 correct concrete answers and 7 abstentions**; no incorrect concrete answers in this set | Seven abstentions are not seven successful factual answers. Six declined despite visible information; one correctly declined a price not printed in the image. These fixtures do not establish general accuracy. |
| Follow-up stability | 24 turns completed without recorded looping, truncation, or recovery failure | Stability for this sequence, not 24 factually correct answers. |
| Offline speech on Mac | Network denied by sandbox; 12/12 synthetic speech inputs accepted; **10/12 exact transcriptions** after ignoring whitespace/punctuation; 4/4 non-speech inputs rejected | The local path worked on this synthetic corpus. Two Thai inaccuracies remain; real voices and accents are unverified. |
| LiDAR object/depth fusion | 3/3 controlled cases, using the real model and Vision with **simulated depth** | The controlled matching/rejection paths worked. This does not measure physical LiDAR accuracy. |
| Signed iPhone Release | Build and strict code-signature verification succeeded | The latest build was signed. Live camera, microphone, LiDAR, inference speed, memory, and thermal behaviour were **not verified on an iPhone for this release**. |

The latest release could not be installed during that validation run. Simulator and Mac results, synthetic speech, and simulated depth must not be presented as measured iPhone performance. The project does not currently implement spoken answer playback, continuous obstacle alerts, directional audio guidance, or non-LiDAR metric depth estimation. OCR, object selection, transcription, and generated answers can still be wrong.

## Data handling

App inference runs locally and does not require a cloud AI service or an API key. Speech is recorded to a temporary file in the app sandbox and removed after transcription or cancellation. Compressed images, previews, and crops can also be stored temporarily in the sandbox during use; the implementation cleans up superseded images. This is not a claim that all data stays only in RAM or that the operating system never writes temporary files. This paragraph describes the iPhone app, not the hosting and external links of this website.

## Evidence provenance

The supplied app's `README.md`, `VALIDATION.md` (latest QA section), and `project.yml` describe the implementation and configured targets. Results were cross-checked with `Logs/qa-delivery-system-summary.json`, `Logs/qa-delivery-native-summary.json`, `Logs/qa-voice-final-summary.json`, `Logs/qa-context-fixed-stress.json`, `Logs/qa-object-fusion-native.json`, `Logs/qa-delivery-iphone-build.log`, and `Logs/qa-delivery-signature.log`. Temporary-file behaviour is implemented in `LunaV/LocalSpeechRecognizer.swift` and `LunaV/PhotoStore.swift`.

## สรุปภาษาไทย

**ตรวจหลักฐาน ณ วันที่ 21 ตุลาคม 2026** โครงการยังเป็นต้นแบบวิจัย รับคำถามเสียงไทยและอังกฤษหลังถ่ายภาพ แสดงคำถามและคำตอบเป็นข้อความ อ่านและสรุป OCR จากทั้งภาพหรือพื้นที่ที่เลือก และวัดจากกล้องถึงพื้นผิววัตถุเมื่อภาพมี LiDAR ที่ใช้ได้ การประมวลผลโมเดลทำบน iPhone โดยไม่มี cloud AI หรือ API key แต่มีการเก็บไฟล์เสียงและภาพชั่วคราวใน sandbox ระหว่างใช้งาน เสียงถูกลบหลังถอดหรือยกเลิก และภาพเก่าถูกเก็บกวาดเมื่อเปลี่ยนภาพ

ผลล่าสุดคือ Simulator **134/134 ผ่าน (unit 126 + UI 8)**; Mac VLM/OCR **29 กรณี ตอบตรง 22 และปฏิเสธตอบ 7** โดย 6 กรณียังตอบไม่ได้ทั้งที่ข้อมูลมองเห็น และอีก 1 กรณีไม่มีราคานั้นพิมพ์จริง จึงไม่ใช่คำตอบถูก 29/29 การทดสอบเสียงใช้เสียงสังเคราะห์ รับเสียงพูด 12/12 แต่ถอดตรงคำเพียง **10/12** หลังไม่นับช่องว่างและวรรคตอน ปฏิเสธเสียงที่ไม่ใช่คำพูด 4/4

รุ่นล่าสุด **build และตรวจลายเซ็นสำหรับ iPhone ผ่าน** แต่ยังไม่ได้ยืนยันกล้อง ไมค์ LiDAR และ inference สดบนเครื่องจริง ผลบน Mac, Simulator, เสียงสังเคราะห์ และ depth จำลองไม่ใช่ผลความแม่นยำ ความเร็ว หรือความร้อนบน iPhone แอปกำหนด iOS 27 / Xcode 27 ขึ้นไปและต้องมีหน่วยความจำเพียงพอ ยังไม่มีการอ่านคำตอบออกเสียง เตือนสิ่งกีดขวางต่อเนื่อง เสียงนำทาง หรือเดาระยะเป็นเมตรในเครื่องไม่มี LiDAR

หลักฐานมาจากเอกสารและไฟล์ที่ระบุด้านบนใน workspace แอป ไม่ได้รวมไฟล์เหล่านั้นไว้ใน repo เว็บไซต์ สามารถใช้[แบบฟอร์มลงทะเบียนขอซอร์สแอป](https://shorturl.koomean.com/sourcecodevisionassistant)เพื่อติดต่อโครงการได้ ช่องทางนี้เป็นแบบฟอร์มคำขอ ไม่ใช่ลิงก์ดาวน์โหลดซอร์สแอปทันที
