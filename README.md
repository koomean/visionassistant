# LunaV

An on-device visual question assistant for iPhone, developed as a SCiUS Forums project. Hold to ask about a photograph, read and summarise text, estimate supported distances, and hear completed answers. The current app is **3.0.0 (build 3)** and uses Qwen3-VL-2B-Instruct through MLX/Metal, Apple Dictation for speech input, Apple system voices for answer playback, and Depth Anything 3 Metric on devices without LiDAR.

[Visit the project website](https://visionassistant.koomean.com/) · [View the project on GitHub](https://github.com/koomean/visionassistant)

## Repository scope

This repository contains the **public project website and its licensing notices**. It does not contain the iPhone app, Xcode project, or model weights. This repository does not provide an App Store release.

Capability descriptions were checked against the supplied app documentation and source on **29 October 2026**. They describe the current research implementation, not a guarantee of accuracy or compatibility with every iPhone.

## Current capabilities

- **Thai or English interface.** Settings → App language switches screens immediately and remembers the choice across relaunches. This changes interface labels, status, errors, and tools independently of Dictation language, answer language, and reading voices; existing questions, answers, and OCR text retain their original content. The final Settings group opens About, displaying the bundle version 3.0.0/build 3, creator, and website link.

- **A shared lunar identity.** The current SwiftUI interface uses the website’s navy, warm-white, pale-blue/gold palette, Noto Sans Thai, and Manrope. Its icon now shares the crescent-and-star symbol. A native LunaVision-to-LunaV introduction runs for about 4.22 seconds while model preparation proceeds; Reduce Motion uses a brief static mark. Settings puts language and answer voices first, then testing tools. The camera retains two main buttons; the camera-switch menu has been removed.

- **Hold, speak, release.** Hold the centre button to start photo/depth capture and microphone recording together, after microphone permission is granted. Speak while holding, then release to stop recording and submit once the image is ready. Silence while holding does not submit. A short tap takes a photograph only. Recordings over the 2-minute limit are rejected rather than submitting only their beginning.
- **Thai or English Dictation on the phone.** Apple DictationTranscriber through SpeechAnalyzer replaces bundled Whisper. Thai is the default; choose English with the separate speech-language setting in Settings. Each request uses the selected language, without automatic language switching. If its Apple language asset is missing, initial preparation may need a download; question transcription then uses installed assets locally.
- **Hear completed answers.** Automatic reading is on by default and uses installed Apple voices for completed AI, OCR, summary, and distance answers. Change or disable voices in Settings. Playback stops before a new capture or microphone session. These are Apple system voices, not a promise of access to the voice selected for Siri.
- **Read and summarise text.** Apple Vision extracts text locally. Settings tools select a region, group text from signs, menus, and labels, and summarise the selected OCR text.
- **Distance with a clear source.** Supported LiDAR captures use sensor depth paired with the photograph. Devices without LiDAR keep the new photograph’s lens information and run bundled Depth Anything 3 Metric when a distance question or manual point selection needs it. A successful map is reused for that photograph; ordinary visual questions do not trigger a depth prediction. Model estimates are labelled, rounded to 0.1 metre, and can be scale-calibrated per camera in Settings. Calibration is not an accuracy certification. Imported images without paired depth do not produce numeric distances; LiDAR-equipped devices skip DA3 even if a capture lacks depth.
- **Preparation, progress, and cancellation.** The app prepares image/depth models before questions and retries temporary preparation failures. Speech preparation has a 30-second deadline; if speech is unavailable, photos, typed questions, and OCR remain available once the required visual models are ready. Voice requests show their stage and elapsed time, can be cancelled, and have a 45-second transcription deadline. Temporary audio remains until its worker actually finishes; cancellation does not promise instant deletion.
- **Use memory for the current task.** Lower-memory devices release idle visual-model weights and reuse bounded text/OCR/tokenizer metadata instead of retaining large image tensors between questions. This means weights may reload for the next answer. OCR runs before a cold visual-model load; DA3 predictions are deferred until distance is needed. Models, quantisation, image resolution, and answer checks were retained in this optimisation. Cancellation and memory warnings request cleanup in order; they do not promise that in-flight inference releases RAM instantly.
- **Local analysis.** Image, depth, OCR, question transcription, and answer synthesis run on the device without a cloud AI service or an API key. The app bundles its image and DA3 models, while iOS manages Dictation language assets and installed voices. Fresh installation is not guaranteed to be usable offline before required Apple assets are installed. Temporary images and recordings are kept in the app sandbox during use.

LunaV does not provide continuous obstacle alerts or directional navigation. Model estimates, OCR, transcription, and generated answers can still be wrong. LiDAR readings refer to the camera-to-surface distance when the photo was captured, rather than a continuously updated measurement.

## Development requirements and evidence

The app project targets **iOS 27** and uses **Xcode 27 or later**. Speech support depends on the device and selected language. Qwen and DA3 also need sufficient available memory and supported hardware; warming a model does not guarantee its weights remain resident in memory.

The latest version 3 regression recorded on **29 October 2026** passed **269/269 (253 unit + 16 UI)**, with no failures, skips, or recorded runtime warnings. After two runtime-information heading translations were adjusted, a focused catalog/metadata rerun passed **2/2**; it was not another full-suite run and is not added to the 269 total. The signed generic-iOS Release passed strict deep signature verification and contains version 3.0.0/build 3 with Thai/English resources. A physical iPhone 14 installation command was cancelled after more than three minutes without connection or transfer progress, so version 3 is **not yet validated running on a physical phone**. Simulator camera/microphone/ASR boundaries are simulated; it does not run the real VLM or sensors. These are recorded app results, not newly run app tests during this website edit.

The preceding lunar-theme UI build passed **262/262 (249 unit + 13 UI)** earlier on 29 October. Its installation attempt failed with CoreDevice 4000 / transport peer no longer reachable. That earlier failure and source manifest are separate from version 3's results.

The preceding resource-optimisation build passed **259/259 (248 unit + 11 UI)** on 24 October. Its non-LiDAR **iPhone 14 / iOS 27.2** functional check installed that Release and completed two real-camera question cycles using recorded speech fixtures and TTS, plus two fixed-image OCR questions. Ordinary photos did not run DA3; manual depth followed by an automatic distance question reused one prediction for the same photo. Those checks belong to the preceding build, not version 3 or the preceding 29 October UI. Neither update establishes a new long-duration, battery, thermal, human speech, or physical-distance accuracy benchmark.

An earlier compact-memory build completed 30 cycles on iPhone 14 Pro with real captures, recorded speech input, and TTS enabled; **15 cycles returned a safe fallback**, so this is not 30 correct answers or a guarantee of unlimited operation. See [PROJECT-STATUS.md](PROJECT-STATUS.md) for the separate builds, measured scope, prior speech checks, and remaining limits.

## Website development and deployment

The website includes a LunaVision-to-LunaV introduction with a visible red pen and wavy strikeout, plus passive scroll effects. Replay the introduction from the footer; reduced-motion preferences skip it. The sequence is in `intro.js` and `motion.css`, while `script.js` controls homepage language, tabs, and scroll motion. The project-status, licensing, and credits pages offer the same Thai/English choice; `docs-language.js` remembers it across pages and supports `?lang=th` / `?lang=en`. Complete Thai document sources live in `docs/th/`, alongside the English Markdown originals at the repository root.

The website is static and needs no runtime build step. Serve this directory locally, for example:

```sh
python3 -m http.server 8080
```

After editing both language versions of a Markdown notice, regenerate their readable HTML pages with:

```sh
python3 scripts/render-docs.py
```

GitHub Pages publishes the repository root from `main` to [visionassistant.koomean.com](https://visionassistant.koomean.com/). Keep `CNAME` when publishing changes. The existing GitHub Actions workflow purges the Cloudflare cache after a successful Pages build.

## Licence

Copyright © 2026 Wachirawich Kripindakul ([koomean](https://github.com/koomean)).

Unless a file identifies different terms, the original work in this repository is licensed under the **GNU Affero General Public License, version 3 or (at your option) any later version (`AGPL-3.0-or-later`)**. See [LICENSE](LICENSE) for the complete licence text.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. It is distributed in the hope that it will be useful, but **WITHOUT ANY WARRANTY**; without even the implied warranty of **MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE**. You should have received a copy of the GNU Affero General Public License along with this program; see [LICENSE](LICENSE). The corresponding website source is available in [this public repository](https://github.com/koomean/visionassistant).

AGPL permits commercial use when its terms are followed. An optional separate commercial licence may be available by written agreement for permissions beyond the AGPL; see [COMMERCIAL-LICENSE.md](COMMERCIAL-LICENSE.md). This notice is not a signed commercial contract. Third-party models, libraries, and resources retain their own licences. No model weights are distributed by this repository.

## ภาษาไทย

LunaV เป็นผู้ช่วยถามตอบจากภาพบน iPhone ในโครงการ SCiUS Forums รุ่นปัจจุบัน **3.0.0 (บิลด์ 3)** ตรวจข้อมูลถึง **29 ตุลาคม 2026** กดปุ่มกลางค้างเพื่อถ่ายภาพ/depth และรับเสียงพร้อมกัน พูดระหว่างถือแล้วปล่อยเพื่อส่ง ความเงียบไม่ส่งเอง แตะสั้นถ่ายภาพอย่างเดียว รับเสียงไม่เกิน 2 นาที หากเกินจะปฏิเสธแทนการส่งเฉพาะต้นประโยค

ใช้ **ตั้งค่า → ภาษาแอพ** สลับหน้าจอไทย/อังกฤษทันทีและจำค่าข้ามการเปิดใหม่ ครอบคลุมป้าย สถานะ ข้อผิดพลาด และเครื่องมือต่าง ๆ แยกจากภาษา Dictation ภาษาคำตอบ และเสียงอ่านที่เลือกไว้ คำถาม คำตอบ และ OCR เดิมไม่ถูกแปล ส่วนสุดท้ายของ Settings เปิดหน้าเกี่ยวกับ แสดงรุ่นจาก bundle จริง 3.0.0/บิลด์ 3 ผู้จัดทำ และลิงก์เว็บไซต์

แอป SwiftUI ใช้ธีม ฟอนต์ และตราจันทร์เสี้ยว/ดาวเดียวกับเว็บแล้ว มี intro LunaVision-to-LunaV ประมาณ 4.22 วินาทีพร้อมเตรียมโมเดลคู่ขนาน รองรับ Reduce Motion หน้า Settings วางภาษาและเสียงก่อนเครื่องมือทดสอบ และนำเมนูสลับกล้องออก หน้าหลักยังมีสองปุ่ม

ใช้ **Apple Dictation ในเครื่องแทน Whisper** ค่าเริ่มต้นไทย เลือก English ได้ด้วยตัวเลือกภาษาเสียงใน Settings ซึ่งแยกจากภาษาแอป ใช้ภาษาที่เลือกทีละภาษา ไม่สลับภาษาอัตโนมัติ หากไม่มี asset ภาษา Apple อาจต้องดาวน์โหลดครั้งแรก จึงไม่รับรองว่าเพิ่งติดตั้งแล้วใช้เสียงออฟไลน์ได้ทันที การถอดคำถามด้วย asset ที่ติดตั้งแล้วทำในเครื่อง มีเส้นตาย 45 วินาทีและยกเลิกได้

**อ่านคำตอบอัตโนมัติเป็นค่าเริ่มต้น** ด้วยเสียง Apple ที่ติดตั้ง อ่านเมื่อคำตอบ AI/OCR/สรุป/ระยะเสร็จ หยุดก่อนถ่ายหรือรับเสียงใหม่ เปลี่ยนเสียงไทย/อังกฤษหรือปิดได้ใน Settings ไม่รับรองว่าใช้เสียง Siri ที่ผู้ใช้เลือกไว้

เครื่องไม่มี LiDAR เก็บภาพใหม่และข้อมูลเลนส์ แล้วใช้ **Depth Anything 3 Metric** เมื่อถามระยะหรือเลือกจุดเอง หากสำเร็จใช้แผนที่เดิมกับภาพนั้น คำถามทั่วไปไม่คำนวณ depth ทุกครั้ง ระบุแหล่งว่าเป็นค่าประมาณ ปัดเป็น 0.1 เมตร และปรับสเกลแยกกล้องได้ แต่ไม่รับรองความแม่นยำเท่า LiDAR เครื่องที่มี LiDAR ใช้เซ็นเซอร์และข้าม DA3 แม้ไม่มีข้อมูล depth ภาพนำเข้าที่ไม่มีคู่ depth ไม่ตอบระยะตัวเลข ไม่มีการเตือนสิ่งกีดขวางต่อเนื่องหรือนำทาง

เครื่อง RAM น้อยคืน weights เมื่อว่างและเก็บบริบท/OCR/cache แบบมีขอบเขต จึงอาจต้องรอโหลดใหม่ระหว่างคำถาม โดยคงโมเดลและความละเอียดเดิม หากเสียงไม่พร้อมยังใช้ภาพ พิมพ์ถาม และ OCR ได้เมื่อโมเดลพร้อม ภาพและเสียงมีไฟล์ชั่วคราวใน sandbox เสียงลบเมื่องานเดิมจบจริง การยกเลิกไม่รับประกันคืน RAM หรือลบไฟล์ทันทีขณะ inference ยังทำงาน

ผลเวอร์ชัน 3 ล่าสุดวันที่ **29 ตุลาคมผ่าน 269/269 (unit 253 + UI 16)** ไม่มี fail/skip/runtime warning หลังเก็บคำแปลหัวข้อข้อมูลการทำงานสองรายการ รัน catalog/metadata เฉพาะจุดผ่าน **2/2** ไม่ใช่การรันเต็มซ้ำและไม่นำมารวมกับ 269 signed generic-iOS Release ตรวจลายเซ็นผ่านและมีรุ่น 3.0.0/บิลด์ 3 พร้อมทรัพยากรไทย/อังกฤษ แต่ยกเลิกคำสั่งติดตั้ง iPhone 14 หลังเกินสามนาทีโดยไม่มีความคืบหน้าการเชื่อมต่อหรือส่งไฟล์ จึง **ยังไม่ยืนยันเวอร์ชัน 3 บนเครื่องจริง** Simulator จำลองขอบเขตกล้อง/ไมค์/ASR และไม่รัน VLM หรือเซ็นเซอร์จริง ข้อมูลนี้เป็นผลที่บันทึกไว้ ไม่ได้รันทดสอบแอปใหม่ระหว่างแก้เว็บไซต์

ผลธีมดวงจันทร์รุ่นก่อนผ่าน **262/262 (unit 249 + UI 13)** ก่อนหน้านั้นในวันที่ 29 ตุลาคม การติดตั้งครั้งนั้นล้มเหลวด้วย CoreDevice 4000 / ติดต่อ transport peer ไม่ได้ เป็นคนละชุดกับผลและ manifest ของเวอร์ชัน 3

ผลรุ่นลดงานซ้ำ **259/259** และการติดตั้ง/ตรวจฟังก์ชัน iPhone 14 ไม่มี LiDAR เป็นหลักฐาน **24 ตุลาคมของรุ่นก่อนหน้า** รวมกล้องจริง 2 รอบที่ใช้ไฟล์เสียงตัวอย่าง และ OCR ภาพทดสอบ 2 คำถาม ไม่ใช่ผลตรวจเวอร์ชัน 3 หรือธีม UI วันที่ 29 ตุลาคมบนเครื่องจริง ไม่มีผล soak/แบตเตอรี่/ความร้อน หรือความแม่นยำเสียงคน/ระยะกายภาพชุดใหม่ ผลรอบยาว 30 รอบของรุ่น compact ก่อนหน้านั้นมี safe fallback 15 รอบ จึงไม่ใช่คำตอบถูก 30/30 หรือการรับประกันใช้ได้ไม่สิ้นสุด

Repo นี้เก็บ **เว็บไซต์โครงการ** ไม่ได้รวมซอร์สแอป Xcode หรือไฟล์โมเดล ดู[โครงการบน GitHub](https://github.com/koomean/visionassistant)ได้ แอปกำหนด iOS 27 / Xcode 27 ขึ้นไป และยังขึ้นกับภาษา ฮาร์ดแวร์ และหน่วยความจำ อ่าน[สถานะและผลทดสอบ](PROJECT-STATUS.md)เพื่อดูขอบเขตหลักฐาน หน้าสถานะ การอนุญาตใช้สิทธิ และเครดิตมีตัวสลับไทย–อังกฤษครบทั้งเนื้อหา โดยจำภาษาร่วมกับหน้าหลัก

โค้ดต้นฉบับใน repo ใช้ **AGPL-3.0-or-later** ตามไฟล์ [LICENSE](LICENSE) ใช้เชิงพาณิชย์ได้เมื่อทำตามเงื่อนไข AGPL หากต้องการสิทธิ์เพิ่มเติมสามารถ[ติดต่อเรื่อง commercial licence](COMMERCIAL-LICENSE.md) โดยต้องตกลงเป็นลายลักษณ์อักษรแยกต่างหาก โมเดลและ dependencies บุคคลที่สามยังใช้ไลเซนส์ของตนเอง
