# LunaV

An on-device visual question assistant for iPhone, developed as a SCiUS Forums project. Hold to ask about a photograph, read and summarise text, estimate supported distances, and hear completed answers. The current app uses Qwen3-VL-2B-Instruct through MLX/Metal, Apple Dictation for speech input, Apple system voices for answer playback, and Depth Anything 3 Metric on devices without LiDAR.

[Visit the project website](https://visionassistant.koomean.com/) · [Request the iPhone app source](https://shorturl.koomean.com/sourcecodevisionassistant)

## Repository scope

This repository contains the **public project website and its licensing notices**. It does not contain the iPhone app, Xcode project, or model weights. The source-request link is the project’s registration/request form, not an immediate app-source download. This repository does not provide an App Store release.

Capability descriptions were checked against the supplied app documentation and source on **24 October 2026**. They describe the current research implementation, not a guarantee of accuracy or compatibility with every iPhone.

## Current capabilities

- **Hold, speak, release.** Hold the centre button to start photo/depth capture and microphone recording together, after microphone permission is granted. Speak while holding, then release to stop recording and submit once the image is ready. Silence while holding does not submit. A short tap takes a photograph only. Recordings over the 2-minute limit are rejected rather than submitting only their beginning.
- **Thai or English Dictation on the phone.** Apple DictationTranscriber through SpeechAnalyzer replaces bundled Whisper. Thai is the default; choose English in Settings. Each request uses the selected language, without automatic language switching. If its Apple language asset is missing, initial preparation may need a download; question transcription then uses installed assets locally.
- **Hear completed answers.** Automatic reading is on by default and uses installed Apple voices for completed AI, OCR, summary, and distance answers. Change or disable voices in Settings. Playback stops before a new capture or microphone session. These are Apple system voices, not a promise of access to the voice selected for Siri.
- **Read and summarise text.** Apple Vision extracts text locally. Settings tools select a region, group text from signs, menus, and labels, and summarise the selected OCR text.
- **Distance with a clear source.** Supported LiDAR captures use sensor depth paired with the photograph. Devices without LiDAR can estimate distance with bundled Depth Anything 3 Metric and the new photograph’s lens information. Model estimates are labelled, rounded to 0.1 metre, and can be scale-calibrated per camera in Settings. Calibration is not an accuracy certification. Imported images without paired depth do not produce numeric distances; LiDAR-equipped devices skip DA3 even if a capture lacks depth.
- **Preparation, progress, and cancellation.** The app prepares image/depth models before questions and retries temporary preparation failures. Speech preparation has a 30-second deadline; if speech is unavailable, photos, typed questions, and OCR remain available once the required visual models are ready. Voice requests show their stage and elapsed time, can be cancelled, and have a 45-second transcription deadline. Temporary audio remains until its worker actually finishes; cancellation does not promise instant deletion.
- **Local analysis.** Image, depth, OCR, question transcription, and answer synthesis run on the device without a cloud AI service or an API key. The app bundles its image and DA3 models, while iOS manages Dictation language assets and installed voices. Fresh installation is not guaranteed to be usable offline before required Apple assets are installed. Temporary images and recordings are kept in the app sandbox during use.

LunaV does not provide continuous obstacle alerts or directional navigation. Model estimates, OCR, transcription, and generated answers can still be wrong. LiDAR readings refer to the camera-to-surface distance when the photo was captured, rather than a continuously updated measurement.

## Development requirements and evidence

The app project targets **iOS 27** and uses **Xcode 27 or later**. Speech support depends on the device and selected language. Qwen and DA3 also need sufficient available memory and supported hardware; warming a model does not guarantee its weights remain resident in memory.

On **24 October**, the Apple answer-speech update passed **224 unit tests**. Its first full run passed 10 of 11 UI tests; an old idle-state expectation was corrected for automatic answer playback, and the focused OCR/two-button rerun passed 2/2. The earlier Dictation regression suite passed **220/220 (209 unit + 11 UI)**, with 6 additional native-integration cases passing separately. These counts describe different runs and should not be added into a single full-suite result.

An iPhone 14 Pro / iOS 27.0.1 was used for local Dictation file tests, installed-voice completion/session checks, and normal startup. These are device checks, not proof of human speech accuracy, human-audible playback, or real-world distance accuracy. DA3 has not yet been validated against measured reference distances on the delivered iPhone app. See [PROJECT-STATUS.md](PROJECT-STATUS.md) for the evidence, limits, and older results.

## Website development and deployment

The website includes a skippable LunaVision-to-LunaV introduction and passive scroll effects. Replay the introduction from the footer; reduced-motion preferences skip it. The sequence is in `intro.js` and `motion.css`, while `script.js` controls language, tabs, and scroll motion.

The website is static and needs no runtime build step. Serve this directory locally, for example:

```sh
python3 -m http.server 8080
```

After editing the Markdown notices, regenerate their readable HTML pages with:

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

LunaV เป็นผู้ช่วยถามตอบจากภาพบน iPhone ในโครงการ SCiUS Forums ข้อมูลปัจจุบันตรวจถึง **24 ตุลาคม 2026** กดปุ่มกลางค้างเพื่อถ่ายภาพ/depth และรับเสียงพร้อมกัน พูดระหว่างถือแล้วปล่อยเพื่อส่ง ความเงียบไม่ส่งเอง คำถามยาวได้ไม่เกิน 2 นาที หากเกินจะแจ้งให้ถามสั้นลง แทนการส่งเฉพาะต้นประโยค

รุ่นปัจจุบันใช้ **Apple Dictation บนเครื่องแทน Whisper** ค่าเริ่มต้นภาษาไทยและเลือก English ได้ในตั้งค่า ใช้ภาษาที่เลือกทีละภาษา ไม่ได้ตรวจสลับภาษาอัตโนมัติ หากไม่มีโมเดลภาษาของ Apple อาจต้องดาวน์โหลดระหว่างเตรียมครั้งแรก จึงยังไม่รับประกันว่าเพิ่งติดตั้งแล้วจะถามด้วยเสียงแบบออฟไลน์ได้ทันที การถอดคำถามหลังติดตั้ง asset แล้วทำในเครื่อง มีเส้นตาย 45 วินาทีและยกเลิกได้

**อ่านคำตอบออกเสียงอัตโนมัติเป็นค่าเริ่มต้น** ใช้เสียง Apple ที่ติดตั้งแล้ว อ่านเมื่อคำตอบ AI/OCR/สรุป/ระยะเสร็จ และหยุดก่อนเริ่มถ่ายหรือรับเสียงใหม่ เปลี่ยนเสียงไทย/อังกฤษหรือปิดการอ่านได้ในตั้งค่า ไม่อ้างว่าใช้เสียง Siri ที่ผู้ใช้เลือกไว้

เครื่องไม่มี LiDAR ประมาณระยะจากภาพใหม่ด้วย **Depth Anything 3 Metric และข้อมูลเลนส์** ระบุแหล่งว่าเป็นค่าประมาณ ปัดเป็น 0.1 เมตร และปรับสเกลแยกตามกล้องได้ในตั้งค่า แต่ยังไม่รับรองความแม่นยำเท่า LiDAR เครื่องที่มี LiDAR ใช้ข้อมูลเซนเซอร์และข้าม DA3 แม้ถ่ายด้วยกล้องหน้าหรือจับ depth ไม่สำเร็จ ภาพนำเข้าที่ไม่มีคู่ depth ไม่รายงานระยะเป็นตัวเลข ยังไม่มีการเตือนสิ่งกีดขวางต่อเนื่องหรือเสียงนำทาง

แอปอุ่นโมเดลและลองเตรียมใหม่อัตโนมัติเมื่อเกิดปัญหาชั่วคราว หากระบบเสียงไม่พร้อมยังใช้ภาพ พิมพ์ถาม และ OCR ได้เมื่อโมเดลภาพพร้อม ภาพและเสียงมีไฟล์ชั่วคราวใน sandbox เสียงถูกลบเมื่องานเดิมสิ้นสุดจริง ไม่รับประกันว่ากดยกเลิกแล้วจะลบทันที

Repo นี้เก็บ **เว็บไซต์โครงการ** ไม่ได้รวมซอร์สแอป Xcode หรือไฟล์โมเดล ใช้[แบบฟอร์มลงทะเบียนขอซอร์สแอป](https://shorturl.koomean.com/sourcecodevisionassistant)เพื่อติดต่อได้ โดยเป็นแบบฟอร์มคำขอ ไม่ใช่ลิงก์ดาวน์โหลดทันที แอปกำหนด iOS 27 / Xcode 27 ขึ้นไป และยังขึ้นกับภาษา ฮาร์ดแวร์ และหน่วยความจำของแต่ละเครื่อง อ่าน[สถานะและผลทดสอบ](PROJECT-STATUS.md)เพื่อดูขอบเขตหลักฐาน

โค้ดต้นฉบับใน repo นี้ใช้ **AGPL-3.0-or-later** ตามไฟล์ [LICENSE](LICENSE) ใช้เชิงพาณิชย์ได้เมื่อปฏิบัติตามเงื่อนไข AGPL หากต้องการสิทธิ์เพิ่มเติมสามารถ[ติดต่อเรื่อง commercial licence](COMMERCIAL-LICENSE.md) โดยต้องตกลงเป็นลายลักษณ์อักษรแยกต่างหาก โมเดลและ dependencies บุคคลที่สามยังใช้ไลเซนส์ของตนเอง
