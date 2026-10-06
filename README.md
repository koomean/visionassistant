# VisionGuide Offline

**An on-device visual guide for people who are blind or have low vision.** VisionGuide uses an iPhone camera to describe nearby objects, estimate distance, read text, and respond to voice questions in Thai and English. Core analysis runs on the device, without a cloud AI service.

> **Project status:** Active development. Source and model packaging have build and test evidence, but important camera, speech, depth, accessibility, performance, and offline behaviors still need validation on physical iPhones. This project is not yet described as production-ready.

[ภาษาไทย](#ภาษาไทย) · [Features](#features) · [Requirements](#requirements) · [Getting-started](#getting-started) · [Models-and-privacy](#models-and-privacy) · [License](#license)

## Features

- Detects people, objects, and obstacles, with safety-aware prioritization.
- Estimates distance using ARKit LiDAR depth when available, or a bundled Depth Anything V3 Metric model when LiDAR is unavailable or not selected.
- Creates concise scene descriptions with a local Qwen model and a deterministic fallback.
- Accepts spoken questions and commands using bundled Whisper. Apple SpeechTranscriber is also available on supported iOS versions and locales; Apple may download its managed language assets before first use.
- Reads text from signs and documents using on-device text recognition and speech output.
- Provides obstacle warnings with haptic feedback and directional audio cues.
- Supports Thai and English. Responses follow the language of the spoken or typed question when it can be identified.
- Includes accessibility and privacy settings, model readiness feedback, and low-resource fallbacks.

## How it works

```text
Camera + ARKit
      ↓
Object detection + depth estimation
      ↓
Scene fusion + safety evaluation
      ↓
Local description or deterministic fallback
      ↓
Speech · haptics · directional audio
```

The app uses protocol-based dependency injection so services can be substituted with test doubles. Camera frames, depth maps, transcripts, prompts, and descriptions are processed in memory for the active analysis or command. The app does not provide a cloud AI path.

## Requirements

- macOS with Xcode and the iOS SDK. The shared scheme is `VisionGuide` in `VisionGuide.xcodeproj`.
- iOS deployment target: **iOS 18.0**.
- An Apple Silicon Mac is required for the included arm64 iOS Simulator native llama.cpp libraries.
- A physical iPhone is required to validate camera, LiDAR, microphone, thermal, memory, accessibility, and real-world model behavior.
- The app requests camera and microphone access. It does not request location, contacts, photo library, Bluetooth, tracking, or health data.

## Getting started

1. Clone or download this repository and open `VisionGuide.xcodeproj` in Xcode from the repository root.
2. Resolve the Swift package dependencies when Xcode prompts you.
3. Check that all required model assets are available under `../VisionGuide/Resources/Models/` (see [Models and privacy](#models-and-privacy)). Large model artifacts may be excluded from Git; a source checkout may not contain them.
4. Select the `VisionGuide` scheme and an iPhone simulator or connected iPhone, then build and run.
5. Grant camera and microphone access when prompted. Complete the startup model preparation flow before using scene analysis.

The bundled setup helper intentionally does **not** download models automatically. It is a guarded placeholder; review pinned upstream revisions, hashes, access conditions, and license terms before refreshing model files. See [`../Documentation/ModelSetup.md`](../Documentation/ModelSetup.md).

### Build from the command line

```sh
xcodebuild \
  -project VisionGuide.xcodeproj \
  -scheme VisionGuide \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

This is a generic build, not a simulator launch or a physical-device validation. For available source and model checks:

```sh
Scripts/preflight.sh --source-only
Scripts/preflight.sh --full
```

`--full` also checks that the model packages and files exist and match the recorded hashes. It will fail if the ignored model assets have not been supplied.

## Models and privacy

The app bundles local assets for YOLO26n object detection, Depth Anything V3 Metric depth estimation, Whisper Small speech recognition, Qwen3.5-2B scene descriptions, and four VachanaTTS Thai voices. Models are large and some are ignored by Git; check `../.gitignore` and `../Documentation/ModelManifest.md` before assuming a fresh clone is runnable.

Model acquisition and conversion are development-time tasks. The production app is not intended to fetch its model files from the network. Required filenames, upstream revisions, conversion notes, license evidence, and SHA-256 values are documented in:

- [`../Documentation/ModelSetup.md`](../Documentation/ModelSetup.md)
- [`../Documentation/ModelManifest.md`](../Documentation/ModelManifest.md)
- [`../Documentation/ThirdPartyLicenses.md`](../Documentation/ThirdPartyLicenses.md)

The app keeps captured frames and analysis content in memory during the active task. If Apple SpeechTranscriber is selected on a supported system, Apple may download or update its system-managed language model assets; bundled Whisper remains the fully bundled speech-recognition option. Actual airplane-mode behavior still requires device validation.

## Testing and validation status

The repository contains unit and UI test targets. The latest recorded verification reports a successful generic iOS Simulator build, generic iPhoneOS builds, and 317 unit tests with 3 skipped and 0 failures (as recorded on 2026-08-11). Some model inference has been checked through Core ML or ONNX Runtime paths, but this does not prove performance or accuracy on a physical iPhone.

Still requiring physical-device validation:

- Camera permission, ARKit capture, and LiDAR alignment.
- YOLO, Whisper, Qwen, and speech output behavior on supported iPhones.
- Non-LiDAR distance accuracy across representative indoor and outdoor scenes.
- VoiceOver/accessibility flows, memory use, thermal behavior, latency, and airplane-mode operation.

See [`../Documentation/VerificationReport.md`](../Documentation/VerificationReport.md), [`../Documentation/ImplementationAudit.md`](../Documentation/ImplementationAudit.md), and [`../Documentation/PhysicalDeviceTesting.md`](../Documentation/PhysicalDeviceTesting.md) for evidence and limitations. Verification records are historical and should be rerun against the current checkout before a release.

## Documentation

- [`../Documentation/Architecture.md`](../Documentation/Architecture.md) — application architecture and runtime flow.
- [`../Documentation/Privacy.md`](../Documentation/Privacy.md) — data handling and permissions.
- [`../Documentation/Dependencies.md`](../Documentation/Dependencies.md) — native and Swift dependencies.
- [`../Documentation/ModelSetup.md`](../Documentation/ModelSetup.md) — model sources and setup status.
- [`../Documentation/ThirdPartyLicenses.md`](../Documentation/ThirdPartyLicenses.md) — third-party model and dependency license evidence.
- [`../Documentation/VerificationReport.md`](../Documentation/VerificationReport.md) — recorded builds, tests, and known gaps.

## License

Project source code is licensed under the **GNU General Public License v3.0**. See [`../LICENSE`](../LICENSE). Bundled models, generated resources, and dependencies may have separate terms; the project license does not relicense them. Review [`../Documentation/ThirdPartyLicenses.md`](../Documentation/ThirdPartyLicenses.md), especially the outstanding YOLO26 distribution review, before redistributing the app or its bundled assets.

---

## ภาษาไทย

**VisionGuide Offline คือผู้ช่วยบอกสิ่งรอบตัวบน iPhone สำหรับผู้พิการทางสายตา** ใช้กล้องเพื่อบรรยายวัตถุและสิ่งกีดขวาง ประเมินระยะ อ่านข้อความ และตอบคำถามด้วยเสียง รองรับภาษาไทยและอังกฤษ โดยการวิเคราะห์หลักทำงานบนอุปกรณ์และไม่มีบริการ AI บนคลาวด์

> **สถานะโครงการ:** อยู่ระหว่างพัฒนา มีหลักฐานการ build และทดสอบบางส่วนแล้ว แต่ยังต้องตรวจสอบกล้อง เสียง ระยะทาง การเข้าถึง ประสิทธิภาพ และการทำงานออฟไลน์บน iPhone จริงก่อนเรียกว่า production-ready

### ความสามารถ

- ตรวจจับคน วัตถุ และสิ่งกีดขวาง พร้อมจัดลำดับสิ่งที่สำคัญต่อความปลอดภัย
- ประเมินระยะด้วย LiDAR ผ่าน ARKit เมื่ออุปกรณ์รองรับ หรือใช้โมเดล Depth Anything V3 Metric เมื่อไม่มีหรือไม่ได้เลือกใช้ LiDAR
- สร้างคำบรรยายฉากด้วย Qwen ที่ทำงานในเครื่อง และมีคำบรรยายสำรองแบบ deterministic
- รับคำถามและคำสั่งเสียงด้วย Whisper ที่บรรจุในแอป นอกจากนี้ iOS บางรุ่นรองรับ Apple SpeechTranscriber ซึ่งอาจดาวน์โหลด asset ภาษาที่ Apple จัดการก่อนใช้งานครั้งแรก
- อ่านป้ายและเอกสารด้วยระบบอ่านข้อความและเสียงพูดบนอุปกรณ์
- เตือนสิ่งกีดขวางด้วยการสั่นและเสียงบอกทิศทาง
- รองรับภาษาไทยและอังกฤษ โดยคำตอบจะใช้ภาษาตามคำถามเมื่อระบบระบุได้
- มีการตั้งค่าการเข้าถึง ความเป็นส่วนตัว สถานะการเตรียมโมเดล และทางเลือกสำหรับอุปกรณ์ทรัพยากรจำกัด

### ความต้องการของระบบ

- macOS ที่ติดตั้ง Xcode และ iOS SDK โดยใช้ scheme `VisionGuide` ใน `../VisionGuide.xcodeproj`
- iOS deployment target **iOS 18.0**
- ต้องใช้ Mac Apple Silicon สำหรับไลบรารี llama.cpp ของ iOS Simulator ที่เตรียมไว้เป็น arm64
- ต้องใช้ iPhone จริงเพื่อตรวจสอบกล้อง LiDAR ไมโครโฟน ความร้อน หน่วยความจำ การเข้าถึง และพฤติกรรมโมเดลในสถานการณ์จริง
- แอปขอสิทธิ์กล้องและไมโครโฟน ไม่ขอตำแหน่ง รายชื่อ รูปภาพ Bluetooth การติดตาม หรือข้อมูลสุขภาพ

### เริ่มต้นใช้งาน

1. clone หรือดาวน์โหลด repository แล้วเปิด `../VisionGuide.xcodeproj` ด้วย Xcode
2. ให้ Xcode resolve Swift package dependencies เมื่อมีข้อความแจ้ง
3. ตรวจว่ามีโมเดลที่จำเป็นใน `../VisionGuide/Resources/Models/` (ดูหัวข้อ [โมเดลและความเป็นส่วนตัว](#models-and-privacy)) ไฟล์โมเดลมีขนาดใหญ่และอาจถูกตัดออกจาก Git ดังนั้น clone ใหม่อาจยังรันไม่ได้
4. เลือก scheme `VisionGuide` และ iPhone Simulator หรือ iPhone ที่เชื่อมต่อ แล้วสั่ง build และ run
5. อนุญาตการใช้กล้องและไมโครโฟน แล้วรอขั้นตอนเตรียมโมเดลก่อนเริ่มวิเคราะห์ฉาก

สคริปต์ตั้งค่าโมเดลยังไม่ดาวน์โหลดโมเดลโดยอัตโนมัติ และตั้งใจหยุดไว้เพื่อให้ตรวจ revision, hash, เงื่อนไขการเข้าถึง และไลเซนส์ก่อน ดู [`../Documentation/ModelSetup.md`](../Documentation/ModelSetup.md)

### โมเดลและความเป็นส่วนตัว

แอปใช้ไฟล์โมเดลในเครื่องสำหรับตรวจจับวัตถุ YOLO26n, ประเมินความลึก Depth Anything V3 Metric, รู้จำเสียง Whisper Small, บรรยายฉาก Qwen3.5-2B และเสียงไทย VachanaTTS สี่เสียง โมเดลมีขนาดใหญ่และบางไฟล์ถูก ignore โดย Git โปรดดู `../.gitignore` และ `../Documentation/ModelManifest.md` ก่อนคาดหวังว่า clone ใหม่จะพร้อมใช้งาน

การดาวน์โหลดและแปลงโมเดลเป็นงานสำหรับผู้พัฒนา แอปที่ใช้งานจริงไม่ได้ตั้งใจดาวน์โหลดโมเดลผ่านเครือข่าย ชื่อไฟล์ revision วิธีแปลง หลักฐานไลเซนส์ และ SHA-256 บันทึกอยู่ใน:

- [`../Documentation/ModelSetup.md`](../Documentation/ModelSetup.md)
- [`../Documentation/ModelManifest.md`](../Documentation/ModelManifest.md)
- [`../Documentation/ThirdPartyLicenses.md`](../Documentation/ThirdPartyLicenses.md)

เฟรมภาพและเนื้อหาการวิเคราะห์อยู่ในหน่วยความจำระหว่างงาน หากเลือก Apple SpeechTranscriber บนระบบที่รองรับ Apple อาจดาวน์โหลดหรืออัปเดต asset ภาษาที่ระบบจัดการ ส่วน Whisper เป็นตัวเลือกรู้จำเสียงที่โมเดลถูกรวมไว้ในแอปแล้ว การทำงานในโหมดเครื่องบินยังต้องยืนยันบนอุปกรณ์จริง

### สถานะการทดสอบ

repository มีทั้ง unit tests และ UI tests รายงานการตรวจสอบล่าสุดที่บันทึกไว้ระบุว่า generic Simulator build และ iPhoneOS builds ผ่าน รวมถึง unit tests 317 รายการ ข้าม 3 รายการ และไม่พบรายการที่ล้มเหลว (บันทึกเมื่อ 2026-08-11) มีการตรวจ inference ของบางโมเดลผ่าน Core ML หรือ ONNX Runtime แต่ผลดังกล่าวไม่ยืนยันความเร็วหรือความแม่นยำบน iPhone จริง

สิ่งที่ยังต้องทดสอบบน iPhone จริง:

- การขอสิทธิ์กล้อง การจับภาพผ่าน ARKit และการจัดแนว LiDAR
- พฤติกรรม YOLO, Whisper, Qwen และเสียงพูดบน iPhone รุ่นที่รองรับ
- ความแม่นยำของระยะบนอุปกรณ์ไม่มี LiDAR ทั้งในอาคารและกลางแจ้ง
- VoiceOver/การเข้าถึง หน่วยความจำ ความร้อน ความหน่วง และโหมดเครื่องบิน

ดูรายละเอียดและข้อจำกัดที่ [`../Documentation/VerificationReport.md`](../Documentation/VerificationReport.md), [`../Documentation/ImplementationAudit.md`](../Documentation/ImplementationAudit.md) และ [`../Documentation/PhysicalDeviceTesting.md`](../Documentation/PhysicalDeviceTesting.md)

### เอกสารเพิ่มเติม

- [`../Documentation/Architecture.md`](../Documentation/Architecture.md) — สถาปัตยกรรมและลำดับการทำงาน
- [`../Documentation/Privacy.md`](../Documentation/Privacy.md) — การจัดการข้อมูลและสิทธิ์ที่แอปขอ
- [`../Documentation/Dependencies.md`](../Documentation/Dependencies.md) — dependencies แบบ native และ Swift packages
- [`../Documentation/ModelSetup.md`](../Documentation/ModelSetup.md) — แหล่งที่มาและสถานะการเตรียมโมเดล
- [`../Documentation/ThirdPartyLicenses.md`](../Documentation/ThirdPartyLicenses.md) — หลักฐานไลเซนส์ของโมเดลและ dependencies บุคคลที่สาม
- [`../Documentation/VerificationReport.md`](../Documentation/VerificationReport.md) — ผล build/test และข้อจำกัดที่บันทึกไว้

### ไลเซนส์

โค้ดต้นฉบับของโปรเจ็กต์เผยแพร่ภายใต้ **GNU General Public License รุ่น 3.0 (GPL-3.0)** ดูไฟล์ [`../LICENSE`](../LICENSE) โมเดล ไฟล์ทรัพยากรที่สร้างขึ้น และ dependencies อาจใช้ไลเซนส์อื่น โดยไลเซนส์ของโปรเจ็กต์ไม่ได้เปลี่ยนไลเซนส์ของไฟล์เหล่านั้น โปรดตรวจ [`../Documentation/ThirdPartyLicenses.md`](../Documentation/ThirdPartyLicenses.md) โดยเฉพาะเงื่อนไขการแจกจ่ายโมเดล YOLO26 ที่ยังต้องตรวจสอบก่อนเผยแพร่แอปหรือไฟล์โมเดล
