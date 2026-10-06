# 🌿 VisionGuide Offline

> **A little more awareness for every step.**
>
> VisionGuide is an iPhone companion for people who are blind or have low vision. It uses the camera to describe nearby objects, estimate distance, read text, and answer spoken questions in Thai and English.

**Thai and English · On-device AI · Privacy-minded · GPL-3.0**

<p><a href="https://shorturl.koomean.com/sourcecodevisionassistant"><img alt="Download project source code" src="https://img.shields.io/badge/%E2%AC%87%EF%B8%8F%20Download-Source%20code-41685d?style=for-the-badge"></a></p>

Source code download: https://shorturl.koomean.com/sourcecodevisionassistant

---

## ✨ What it can do

- 🧭 **Describe the scene** — identify people, objects, and obstacles, then summarize what matters.
- 📏 **Estimate distance** — use LiDAR when available, or estimate metric depth from the camera on other devices.
- 🎙️ **Listen to questions** — ask what is ahead or request help finding an object.
- 🔎 **Read text aloud** — hear signs, menus, and printed text.
- 📳 **Give obstacle alerts** — combine vibration with directional audio cues.
- 🌏 **Speak Thai and English** — respond in the language of the question when it can be identified.
- 🔐 **Keep analysis on the device** — core features use local models rather than a cloud AI service.

## 🪄 From camera to guidance

```text
📷 Camera view
      ↓
🧩 Objects + distance
      ↓
🗺️ A clearer picture of the scene
      ↓
🗣️ Speech · 📳 haptics · 🔔 directional cues
```

The app combines object detection, depth estimation, scene analysis, and spoken output. If the language model is unavailable, a predictable local description can still provide guidance.

## 🛠️ Getting started

1. Open the VisionGuide Xcode project on a Mac with Xcode and the iOS SDK.
2. Let Xcode resolve the project’s Swift packages.
3. Choose the VisionGuide scheme and an iPhone simulator or connected iPhone, then build and run.
4. Allow camera and microphone access, and wait for the model preparation step.

The app targets **iOS 18 or later**. An Apple Silicon Mac is needed for the included arm64 simulator libraries. A physical iPhone is needed to assess real camera, LiDAR, speech, accessibility, memory, and thermal behavior.

### 📦 About the models

VisionGuide uses local models and runtimes for object detection, depth estimation, speech recognition, scene descriptions, and Thai speech synthesis. These assets are large, so a source checkout may not include every model needed to run the app.

Model acquisition and conversion are development tasks. The app is designed to use bundled models; it does not automatically download model files during setup. On supported iOS versions, Apple SpeechTranscriber may download Apple-managed language assets before first use. Bundled Whisper remains available as the fully packaged speech-recognition option.

## 🛡️ Privacy and safety

Camera frames, depth maps, transcripts, prompts, and descriptions are handled in memory for the active analysis or command. The app does not provide a cloud AI analysis path and does not request location, contacts, photo library, tracking, or health data.

Distance estimates and obstacle alerts are assistive features. Their accuracy and timing can vary with the device, environment, lighting, and sensor availability. Do not treat them as a replacement for a cane, guide dog, or established mobility practices.

## 🧪 Project status

VisionGuide is under active development. Recorded checks include successful generic iOS builds and a unit-test run with **317 tests, 3 skipped, and 0 failures**. Some model inference paths have also been exercised through Core ML or ONNX Runtime.

Physical-device validation is still needed for camera permissions, live detection and speech, LiDAR alignment, non-LiDAR distance accuracy, VoiceOver flows, memory, thermal behavior, and airplane-mode operation. Build and simulator results alone do not establish real-world performance or production readiness.

## 🤝 Open source

The project’s original source code is licensed under **GNU General Public License v3.0 (GPL-3.0)**. You may use, study, modify, and redistribute covered code under its terms. When distributing covered modified versions, the GPL’s source and license requirements apply.

Models, generated resources, and third-party dependencies may have their own licenses. The project’s GPL license does not change those terms. In particular, the distribution terms for the bundled object-detection model still need review before redistribution.

## 🇹🇭 ภาษาไทย

> **เข้าใจสิ่งรอบตัว เพื่อก้าวต่อไปอย่างมั่นใจ**
>
> VisionGuide เป็นผู้ช่วยบน iPhone สำหรับผู้พิการทางสายตา ใช้กล้องบรรยายสิ่งของและสิ่งกีดขวาง ประเมินระยะ อ่านข้อความ และตอบคำถามด้วยเสียง รองรับภาษาไทยและอังกฤษ

**ไทยและอังกฤษ · AI บนอุปกรณ์ · คำนึงถึงความเป็นส่วนตัว · GPL-3.0**

<p><a href="https://shorturl.koomean.com/sourcecodevisionassistant"><img alt="ดาวน์โหลดซอร์สโค้ดโปรเจ็กต์" src="https://img.shields.io/badge/%E2%AC%87%EF%B8%8F%20%E0%B8%94%E0%B8%B2%E0%B8%A7%E0%B8%99%E0%B9%8C%E0%B9%82%E0%B8%AB%E0%B8%A5%E0%B8%94-%E0%B8%8B%E0%B8%AD%E0%B8%A3%E0%B9%8C%E0%B8%AA%E0%B9%82%E0%B8%84%E0%B9%89%E0%B8%94-41685d?style=for-the-badge"></a></p>

ลิงก์ดาวน์โหลดซอร์สโค้ด: https://shorturl.koomean.com/sourcecodevisionassistant

### ✨ ทำอะไรได้บ้าง

- 🧭 **บรรยายฉาก** — ตรวจจับคน วัตถุ และสิ่งกีดขวาง แล้วสรุปสิ่งที่ควรรู้
- 📏 **ประเมินระยะ** — ใช้ LiDAR เมื่ออุปกรณ์รองรับ หรือประเมินความลึกจากภาพบนอุปกรณ์รุ่นอื่น
- 🎙️ **ฟังคำถาม** — ถามได้ว่าข้างหน้ามีอะไร หรือให้ช่วยหาสิ่งของ
- 🔎 **อ่านข้อความให้ฟัง** — ฟังป้าย เมนู และเอกสาร
- 📳 **เตือนสิ่งกีดขวาง** — ใช้การสั่นร่วมกับเสียงบอกทิศทาง
- 🌏 **รองรับไทยและอังกฤษ** — ตอบตามภาษาของคำถามเมื่อระบบตรวจจับได้
- 🔐 **ประมวลผลบนอุปกรณ์** — ฟีเจอร์หลักใช้โมเดลในเครื่อง ไม่เรียกบริการ AI บนคลาวด์

### 🛠️ เริ่มต้นใช้งาน

1. เปิดโปรเจ็กต์ VisionGuide ด้วย Xcode บน Mac ที่มี iOS SDK
2. ให้ Xcode เตรียม Swift packages ของโปรเจ็กต์
3. เลือก scheme VisionGuide และ iPhone Simulator หรือ iPhone ที่เชื่อมต่อ แล้วสั่ง build และ run
4. อนุญาตให้ใช้กล้องและไมโครโฟน แล้วรอขั้นตอนเตรียมโมเดล

แอปรองรับ **iOS 18 ขึ้นไป** การ build ด้วยไลบรารี Simulator ที่เตรียมไว้ต้องใช้ Mac Apple Silicon ส่วนการตรวจสอบกล้อง LiDAR เสียง การเข้าถึง หน่วยความจำ และความร้อนต้องใช้อุปกรณ์จริง

### 📦 โมเดลและการทำงาน

แอปใช้โมเดลและ runtime ภายในเครื่องสำหรับตรวจจับวัตถุ ประเมินความลึก รู้จำเสียง บรรยายฉาก และสังเคราะห์เสียงภาษาไทย ไฟล์โมเดลมีขนาดใหญ่ จึงอาจไม่ได้รวมอยู่ใน source checkout ทุกชุด

การดาวน์โหลดและแปลงโมเดลเป็นงานสำหรับผู้พัฒนา แอปไม่ได้ดาวน์โหลดไฟล์โมเดลเองระหว่างติดตั้งหรือเริ่มใช้งาน หากเลือก Apple SpeechTranscriber บน iOS ที่รองรับ Apple อาจดาวน์โหลด asset ภาษาที่ระบบจัดการก่อนใช้ครั้งแรก ส่วน Whisper เป็นตัวเลือกที่บรรจุโมเดลไว้ในแอป

### 🛡️ ความเป็นส่วนตัวและความปลอดภัย

ภาพจากกล้อง แผนที่ความลึก เสียงถอดข้อความ prompt และคำบรรยายจะอยู่ในหน่วยความจำระหว่างการวิเคราะห์ แอปไม่มีเส้นทางวิเคราะห์ AI บนคลาวด์ และไม่ขอสิทธิ์ตำแหน่ง รายชื่อ รูปภาพ การติดตาม หรือข้อมูลสุขภาพ

ระยะทางและการเตือนเป็นตัวช่วย ความแม่นยำและจังหวะการเตือนขึ้นอยู่กับอุปกรณ์ สภาพแวดล้อม แสง และเซนเซอร์ อย่าใช้แทนไม้เท้า สุนัขนำทาง หรือวิธีเดินทางที่ใช้อยู่

### 🧪 สถานะโครงการ

VisionGuide ยังอยู่ระหว่างพัฒนา ผลการตรวจสอบที่บันทึกไว้ประกอบด้วย generic iOS builds ที่ผ่าน และ unit tests **317 รายการ ผ่าน 314 ข้าม 3 และไม่พบรายการล้มเหลว** มีการทดสอบเส้นทาง inference ของบางโมเดลผ่าน Core ML หรือ ONNX Runtime ด้วย

ยังต้องทดสอบบน iPhone จริง ทั้งสิทธิ์กล้อง การตรวจจับและเสียง LiDAR ความแม่นยำของระยะในเครื่องที่ไม่มี LiDAR การใช้งาน VoiceOver หน่วยความจำ ความร้อน และโหมดเครื่องบิน ผล build หรือ simulator ยังยืนยันประสิทธิภาพจริงและความพร้อมสำหรับเผยแพร่ไม่ได้

### 🤝 โอเพนซอร์ส

โค้ดต้นฉบับของโปรเจ็กต์ใช้ **GNU General Public License รุ่น 3.0 (GPL-3.0)** สามารถใช้ ศึกษา แก้ไข และแจกจ่ายโค้ดส่วนที่อยู่ภายใต้ไลเซนส์ได้ตามเงื่อนไข เมื่อแจกจ่ายงานดัดแปลงที่ GPL ครอบคลุม ต้องทำตามข้อกำหนดเรื่องซอร์สโค้ดและไลเซนส์

โมเดล ไฟล์ทรัพยากรที่สร้างขึ้น และ dependencies บุคคลที่สามอาจมีไลเซนส์ของตนเอง GPL ของโปรเจ็กต์ไม่ได้เปลี่ยนเงื่อนไขเหล่านั้น โดยเฉพาะโมเดลตรวจจับวัตถุที่รวมไว้ยังต้องตรวจสอบสิทธิ์การแจกจ่ายก่อนเผยแพร่ต่อ
