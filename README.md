# LunaV

An on-device visual question assistant for iPhone, developed as a SCiUS Forums project. LunaV accepts spoken Thai and English questions, reads text from photographs, and shows the transcript and answer on screen. Its current implementation uses Qwen3-VL-2B-Instruct through MLX/Metal, Whisper large-v3 turbo through Core ML, and Apple Vision OCR.

[Visit the project website](https://visionassistant.koomean.com/) · [Enquire about the iPhone app source](https://github.com/koomean/visionassistant/issues/new?title=Source%20code%20enquiry%20%E2%80%94%20LunaV)

## Repository scope

This repository contains the **public project website and its licensing notices**. It does not contain the iPhone app, Xcode project, or model weights. Source enquiries open a public GitHub issue form; this is a contact channel, not an immediate app-source download. This repository does not provide an App Store release.

The website describes the current LunaV implementation rather than the earlier VisionGuide design. Capability descriptions were checked against the supplied app documentation and source on 21 October 2026. They describe implementation, not a guarantee of accuracy or device compatibility.

## Current capabilities

- **Ask about a photograph.** Hold the shutter for about 0.35 seconds to capture a new image and its available depth data. Speak after the haptic cue. After speech recognition finishes, the app displays both the question and LunaV's answer.
- **Thai and English voice input.** Bundled multilingual Whisper models transcribe questions locally. Silence can end recording automatically; transcription is not streamed live.
- **Read and summarise text.** Apple Vision extracts text locally. Tools in Settings can select a region, group text from signs, menus, and labels, and summarise the selected OCR text.
- **Measure supported LiDAR captures.** On a compatible rear LiDAR camera, the app can locate an object and read depth associated with that photograph. It reports a camera-to-surface distance at capture time. Without usable LiDAR data, it does not fabricate a metric distance; visual questions remain available.
- **Keep inference on the phone.** The app bundles its image and speech models and does not require a cloud AI service or an API key. Temporary recordings are removed after transcription or cancellation. Temporary image files are kept in the app sandbox during use.

The current interface presents answers as text. It does not implement spoken answer playback, continuous obstacle alerts, directional guidance, or non-LiDAR metric depth estimation. LiDAR's accepted application range of 0.2–5 metres is a validation bound, not an accuracy certification. A new capture is needed for a new measurement.

## Development requirements and status

The supplied app project currently targets **iOS 27** and uses **Xcode 27 or later**. These are the project's configured targets, not a claim that every iPhone with that operating system can run the models. Sufficient available memory, the device's memory entitlement, and its thermal state affect model availability. Simulator checks do not replace validation of camera capture, LiDAR, microphone input, and model inference on a supported physical iPhone.

LunaV is an active research prototype. The website does not claim an App Store release, certified distance accuracy, universal iPhone support, or real-world accessibility validation. Its descriptions and measurements should not replace established mobility aids or an independent measurement where accuracy matters.

See [PROJECT-STATUS.md](PROJECT-STATUS.md) for the dated validation results and their limits.

## Website development and deployment

The website is static and needs no build step. Serve this directory with a local HTTP server, for example:

```sh
python3 -m http.server 8080
```

GitHub Pages publishes the repository root from `main` to [visionassistant.koomean.com](https://visionassistant.koomean.com/). Keep `CNAME` when publishing changes. The existing GitHub Actions workflow purges the Cloudflare cache after a successful Pages build.

## Licence

Copyright © 2026 Wachirawich Kripindakul ([koomean](https://github.com/koomean)).

Unless a file identifies different terms, the original work in this repository is licensed under the **GNU Affero General Public License, version 3 or (at your option) any later version (`AGPL-3.0-or-later`)**. See [LICENSE](LICENSE) for the complete licence text.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. It is distributed in the hope that it will be useful, but **WITHOUT ANY WARRANTY**; without even the implied warranty of **MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE**. You should have received a copy of the GNU Affero General Public License along with this program; see [LICENSE](LICENSE). The corresponding website source is available in [this public repository](https://github.com/koomean/visionassistant).

AGPL permits commercial use when its terms are followed. An optional separate commercial licence may be available by written agreement for permissions beyond the AGPL; see [COMMERCIAL-LICENSE.md](COMMERCIAL-LICENSE.md). This notice is not a signed commercial contract. Third-party models, libraries, and resources retain their own licences. No model weights are distributed by this repository.

## ภาษาไทย

LunaV เป็นโครงการผู้ช่วยถามตอบจากภาพบน iPhone ประมวลผลโมเดลภาพ เสียง และ OCR บนอุปกรณ์ ผู้ใช้กดค้างที่ชัตเตอร์เพื่อถ่ายภาพใหม่ แล้วพูดคำถามภาษาไทยหรืออังกฤษหลังสัญญาณสั่น แอปแสดงข้อความที่ถอดเสียงและคำตอบบนหน้าจอ เครื่องมือในตั้งค่าสามารถอ่านข้อความ เลือกพื้นที่ แยกป้าย เมนู และฉลาก แล้วสรุปจาก OCR ได้

การถามระยะใช้ข้อมูล LiDAR ที่จับคู่กับภาพจากกล้องที่รองรับ วัดจากกล้องถึงพื้นผิววัตถุ ณ เวลาถ่ายภาพ หากไม่มีข้อมูลที่เชื่อถือได้ แอปจะแจ้งข้อจำกัดโดยไม่เดาตัวเลข รุ่นไม่มี LiDAR ยังถามจากภาพได้ แต่ไม่มีการประมาณระยะเป็นเมตรแทนเซนเซอร์ ในเวอร์ชันปัจจุบันยังไม่มีการอ่านคำตอบออกเสียง การเตือนสิ่งกีดขวางต่อเนื่อง หรือเสียงบอกทิศทาง

Repo นี้เก็บ **เว็บไซต์โครงการ** ไม่ได้รวมซอร์สแอป Xcode หรือไฟล์โมเดล สามารถใช้[ช่องทางสอบถามซอร์สแอปบน GitHub](https://github.com/koomean/visionassistant/issues/new?title=Source%20code%20enquiry%20%E2%80%94%20LunaV)ได้ โดยเป็น issue สาธารณะ ไม่ใช่ลิงก์ดาวน์โหลดทันที โปรเจกต์แอปที่ตรวจสอบกำหนด iOS 27 และ Xcode 27 ขึ้นไป และยังต้องตรวจความพร้อมของหน่วยความจำกับฮาร์ดแวร์จริง

โค้ดต้นฉบับใน repo นี้ใช้ **AGPL-3.0-or-later** ตามไฟล์ [LICENSE](LICENSE) ใช้เชิงพาณิชย์ได้เมื่อปฏิบัติตามเงื่อนไข AGPL หากต้องการสิทธิ์เพิ่มเติมสามารถ[ติดต่อเรื่อง commercial licence](COMMERCIAL-LICENSE.md) โดยต้องตกลงเป็นลายลักษณ์อักษรแยกต่างหาก โมเดลและ dependencies บุคคลที่สามยังใช้ไลเซนส์ของตนเอง
