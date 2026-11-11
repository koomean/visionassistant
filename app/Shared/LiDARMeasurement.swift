import Foundation
import CoreGraphics

/// The RGB file and this map belong to one photograph. LiDAR maps/calibration
/// retain sensor orientation; model maps are restored to upright full-photo
/// coordinates. Source provenance distinguishes the two measurement paths.
struct LiDARSnapshot: Sendable {
    let width: Int
    let height: Int
    let depthMeters: [Float]
    let orientation: DepthImageOrientation
    let calibration: DepthCalibration
    let capturedAt: Date
    let photoTimestamp: Double
    let isAbsolute: Bool
    let isHighQuality: Bool
    let isFiltered: Bool
    var depthSource: DepthSource = .lidar
    /// A model validity mask is separate from AVFoundation sensor quality. It
    /// records non-sky, finite predictions; it is not learned confidence.
    var modelValidity: [Bool]? = nil
    var focalProvenance: PhotoFocalProvenance? = nil
    var calibrationScale: Double = 1
}

enum DepthSource: String, Sendable, Codable {
    case lidar, depthAnything3Metric

    var title: String { self == .lidar ? "LiDAR" : "Depth Anything 3 Metric" }
    var isEstimated: Bool { self != .lidar }
    var supportedRange: ClosedRange<Float> { self == .lidar ? 0.2...5 : 0.2...10 }
}

enum PhotoFocalProvenance: String, Sendable, Codable {
    case cameraCalibration, videoIntrinsicMatrix, exif35mm
    var isApproximate: Bool { self == .exif35mm }
}

/// Pixel intrinsics for the encoded photograph BEFORE EXIF orientation. Video
/// intrinsics are accepted only after matching the still image's field of view.
struct PhotoCameraIntrinsics: Sendable {
    let referenceWidth: Double
    let referenceHeight: Double
    let fx: Double
    let fy: Double
    let cx: Double
    let cy: Double
    let orientation: DepthImageOrientation
    let provenance: PhotoFocalProvenance

    var isValid: Bool {
        referenceWidth.isFinite && referenceHeight.isFinite && referenceWidth > 0 && referenceHeight > 0
            && fx.isFinite && fy.isFinite && fx > 0 && fy > 0 && cx.isFinite && cy.isFinite
            && (0...referenceWidth).contains(cx) && (0...referenceHeight).contains(cy)
    }

    func uprightCalibration(width: Int, height: Int) -> DepthCalibration? {
        guard isValid, width > 0, height > 0 else { return nil }
        let swaps = orientation.rawValue >= 5
        let nativeWidth = swaps ? referenceHeight : referenceWidth
        let nativeHeight = swaps ? referenceWidth : referenceHeight
        let center = orientation.uprightPoint(fromSensor: CGPoint(x: cx / referenceWidth, y: cy / referenceHeight))
        return .init(referenceWidth: Double(width), referenceHeight: Double(height),
                     fx: (swaps ? fy : fx) * Double(width) / nativeWidth,
                     fy: (swaps ? fx : fy) * Double(height) / nativeHeight,
                     cx: Double(center.x) * Double(width), cy: Double(center.y) * Double(height),
                     distortionCenter: CGPoint(x: Double(center.x) * Double(width), y: Double(center.y) * Double(height)),
                     inverseDistortion: nil)
    }

    /// EXIF's 35mm-equivalent focal length describes equivalent diagonal field
    /// of view. Using width/36 silently biases 4:3 and portrait photographs.
    static func exif35mm(focalLength: Double, width: Int, height: Int,
                         orientation: DepthImageOrientation) -> PhotoCameraIntrinsics? {
        guard focalLength.isFinite, focalLength > 0, width > 0, height > 0 else { return nil }
        let focalPixels = focalLength * hypot(Double(width), Double(height)) / hypot(36, 24)
        return .init(referenceWidth: Double(width), referenceHeight: Double(height), fx: focalPixels, fy: focalPixels,
                     cx: Double(width) / 2, cy: Double(height) / 2, orientation: orientation, provenance: .exif35mm)
    }
}

enum DepthAnythingMetricGeometry {
    /// DA3METRIC predicts canonical axial depth. Focal scaling uses the actual
    /// model input, independently of the resolution of its output depth map.
    /// The output grids and supplied intrinsics must describe the same upright
    /// photo. sky is the model's raw nonnegative score, NOT a probability.
    static func snapshot(rawDepth: [Float], sky: [Float], width: Int, height: Int,
                         modelInputWidth: Int, modelInputHeight: Int, intrinsics: PhotoCameraIntrinsics,
                         calibrationScale: Double = 1, capturedAt: Date = Date(),
                         photoTimestamp: Double = 0) throws -> LiDARSnapshot {
        guard width >= 5, height >= 5, width <= 4_096, height <= 4_096,
              rawDepth.count == width * height, sky.count == rawDepth.count,
              calibrationScale.isFinite, (0.25...4).contains(calibrationScale),
              let modelCamera = intrinsics.uprightCalibration(width: modelInputWidth, height: modelInputHeight),
              let outputCamera = intrinsics.uprightCalibration(width: width, height: height) else {
            throw LiDARMeasurementError.invalidMap
        }
        let scale = (modelCamera.fx + modelCamera.fy) / 2 / 300 * calibrationScale
        guard scale.isFinite, scale > 0 else { throw LiDARMeasurementError.missingCalibration }
        var values = [Float](repeating: .nan, count: rawDepth.count)
        var validity = [Bool](repeating: false, count: rawDepth.count)
        for index in rawDepth.indices {
            let z = Double(rawDepth[index]) * scale
            guard rawDepth[index].isFinite, rawDepth[index] > 0, sky[index].isFinite, sky[index] >= 0,
                  sky[index] < 0.3, z.isFinite, DepthSource.depthAnything3Metric.supportedRange.contains(Float(z)) else { continue }
            values[index] = Float(z)
            validity[index] = true
        }
        return .init(width: width, height: height, depthMeters: values, orientation: .up,
                     calibration: outputCamera, capturedAt: capturedAt, photoTimestamp: photoTimestamp,
                     isAbsolute: false, isHighQuality: false, isFiltered: false,
                     depthSource: .depthAnything3Metric, modelValidity: validity,
                     focalProvenance: intrinsics.provenance, calibrationScale: calibrationScale)
    }
}

struct DepthCalibration: Sendable {
    let referenceWidth: Double
    let referenceHeight: Double
    let fx: Double
    let fy: Double
    let cx: Double
    let cy: Double
    let distortionCenter: CGPoint
    /// Distorted sensor coordinates -> rectilinear coordinates, per Apple's
    /// AVCameraCalibrationData reference implementation (inverse lookup table).
    let inverseDistortion: [Float]?

    func ray(at sensorPoint: CGPoint) -> (x: Double, y: Double)? {
        guard referenceWidth > 0, referenceHeight > 0, fx.isFinite, fy.isFinite,
              fx > 0, fy > 0, cx.isFinite, cy.isFinite,
              let table = inverseDistortion, table.count >= 2, table.allSatisfy(\.isFinite) else { return nil }
        let point = CGPoint(x: sensorPoint.x * referenceWidth, y: sensorPoint.y * referenceHeight)
        let dx = Double(point.x - distortionCenter.x), dy = Double(point.y - distortionCenter.y)
        let radius = hypot(dx, dy)
        let maximum = hypot(max(Double(distortionCenter.x), referenceWidth - Double(distortionCenter.x)),
                            max(Double(distortionCenter.y), referenceHeight - Double(distortionCenter.y)))
        guard radius.isFinite, maximum.isFinite, maximum > 0 else { return nil }
        let position = min(Double(table.count - 1), radius / maximum * Double(table.count - 1))
        let lower = min(Int(position), table.count - 2)
        let fraction = position - Double(lower)
        let magnification = Double(table[lower]) * (1 - fraction) + Double(table[lower + 1]) * fraction
        let x = (Double(distortionCenter.x) + dx * (1 + magnification) - cx) / fx
        let y = (Double(distortionCenter.y) + dy * (1 + magnification) - cy) / fy
        return x.isFinite && y.isFinite ? (x, y) : nil
    }

    /// A rectilinear model image has no Apple distortion lookup table. Only the
    /// explicitly estimated-depth branch may use this camera-ray approximation.
    func rectilinearRay(at point: CGPoint) -> (x: Double, y: Double)? {
        guard referenceWidth.isFinite, referenceHeight.isFinite, referenceWidth > 0, referenceHeight > 0,
              fx.isFinite, fy.isFinite, fx > 0, fy > 0, cx.isFinite, cy.isFinite else { return nil }
        let x = (Double(point.x) * referenceWidth - cx) / fx
        let y = (Double(point.y) * referenceHeight - cy) / fy
        return x.isFinite && y.isFinite ? (x, y) : nil
    }
}

enum DepthImageOrientation: UInt32, Sendable, CaseIterable {
    case up = 1, upMirrored, down, downMirrored, leftMirrored, right, rightMirrored, left

    func sensorPoint(fromUpright point: CGPoint) -> CGPoint {
        let x = point.x, y = point.y
        switch self {
        case .up: return point
        case .upMirrored: return CGPoint(x: 1 - x, y: y)
        case .down: return CGPoint(x: 1 - x, y: 1 - y)
        case .downMirrored: return CGPoint(x: x, y: 1 - y)
        case .leftMirrored: return CGPoint(x: y, y: x)
        case .right: return CGPoint(x: y, y: 1 - x)
        case .rightMirrored: return CGPoint(x: 1 - y, y: 1 - x)
        case .left: return CGPoint(x: 1 - y, y: x)
        }
    }

    func uprightPoint(fromSensor point: CGPoint) -> CGPoint {
        switch self {
        case .right: DepthImageOrientation.left.sensorPoint(fromUpright: point)
        case .left: DepthImageOrientation.right.sensorPoint(fromUpright: point)
        default: sensorPoint(fromUpright: point)
        }
    }
}

struct LiDARMeasurement: Sendable {
    let meters: Double
    let axialMeters: Double
    let point: CGPoint
    let sampleCount: Int
    let capturedAt: Date
    let isFiltered: Bool
    var depthSource: DepthSource = .lidar
    var focalProvenance: PhotoFocalProvenance? = nil
    var calibrationScale: Double = 1

    func answer(subject: String = "จุดที่เลือก", inCentimeters: Bool = false) -> String {
        if depthSource == .depthAnything3Metric {
            let value = inCentimeters ? String(format: "%.0f เซนติเมตร", (meters * 10).rounded() * 10)
                : String(format: "%.1f เมตร", meters)
            let focal = focalProvenance?.isApproximate == true ? " โดยประมาณค่าเลนส์จาก EXIF" : ""
            return "\(subject)อยู่ห่างกล้องประมาณ \(value) ประเมินจาก Depth Anything 3 Metric\(focal) ค่าจริงอาจคลาดเคลื่อน"
        }
        let value = inCentimeters ? String(format: "%.0f เซนติเมตร", meters * 100) : String(format: "%.2f เมตร", meters)
        let source = isFiltered ? "LiDAR ที่ระบบประมวลผลแล้ว" : "LiDAR"
        return "\(subject)อยู่ห่างกล้องประมาณ \(value) วัดจาก \(source) ตอนถ่ายภาพ"
    }
}

enum LiDARMeasurementError: LocalizedError, Equatable {
    case invalidMap, lowQuality, missingCalibration, noReading, mixedSurfaces
    var errorDescription: String? {
        switch self {
        case .invalidMap: "ข้อมูล depth ไม่ตรงกับภาพนี้ กรุณาถ่ายภาพใหม่"
        case .lowQuality: "ข้อมูลระยะภาพนี้มีคุณภาพไม่พอ กรุณาถ่ายใหม่"
        case .missingCalibration: "ไม่มีข้อมูลปรับเทียบเลนส์ที่พอสำหรับวัดระยะตรงจุดนี้"
        case .noReading: "ไม่มีค่าระยะที่ใช้ได้ตรงพื้นผิววัตถุในภาพนี้ กรุณาถ่ายภาพใหม่"
        case .mixedSurfaces: "บริเวณนี้อยู่ใกล้ขอบหรือมีหลายระยะปนกัน จึงยังยืนยันระยะไม่ได้"
        }
    }
}

enum LiDARRangeReader {
    static func measure(_ snapshot: LiDARSnapshot, at point: CGPoint) throws -> LiDARMeasurement {
        guard snapshot.width >= 5, snapshot.height >= 5,
              snapshot.depthMeters.count == snapshot.width * snapshot.height,
              point.x.isFinite, point.y.isFinite, (0...1).contains(point.x), (0...1).contains(point.y) else {
            throw LiDARMeasurementError.invalidMap
        }
        // AVFoundation's native filtered map is still calibrated absolute depth.
        // Its temporal/spatial interpolation is exposed in the measurement rather
        // than advertised as an unprocessed sensor return. All local validation
        // below applies to filtered and unfiltered maps alike.
        switch snapshot.depthSource {
        case .lidar:
            guard snapshot.isAbsolute, snapshot.isHighQuality else { throw LiDARMeasurementError.lowQuality }
        case .depthAnything3Metric:
            guard snapshot.modelValidity?.count == snapshot.depthMeters.count,
                  snapshot.focalProvenance != nil, snapshot.calibrationScale.isFinite,
                  (0.25...4).contains(snapshot.calibrationScale) else { throw LiDARMeasurementError.lowQuality }
        }
        let sensor = snapshot.orientation.sensorPoint(fromUpright: point)
        let x = min(snapshot.width - 1, Int(sensor.x * CGFloat(snapshot.width)))
        let y = min(snapshot.height - 1, Int(sensor.y * CGFloat(snapshot.height)))
        func valid(_ value: Float) -> Bool { value.isFinite && snapshot.depthSource.supportedRange.contains(value) }
        func validSample(_ index: Int) -> Bool {
            valid(snapshot.depthMeters[index]) && (snapshot.depthSource == .lidar || snapshot.modelValidity?[index] == true)
        }
        let center = snapshot.depthMeters[y * snapshot.width + x]
        guard validSample(y * snapshot.width + x) else { throw LiDARMeasurementError.noReading }
        var values: [Double] = []
        var total = 0
        for row in max(0, y - 2)...min(snapshot.height - 1, y + 2) {
            for column in max(0, x - 2)...min(snapshot.width - 1, x + 2) {
                total += 1
                let value = snapshot.depthMeters[row * snapshot.width + column]
                if validSample(row * snapshot.width + column) { values.append(Double(value)) }
            }
        }
        guard values.count >= 9, Double(values.count) / Double(total) >= 0.7 else { throw LiDARMeasurementError.noReading }
        let tolerance = snapshot.depthSource == .lidar ? max(0.04, Double(center) * 0.03)
            : max(0.12, Double(center) * 0.1)
        let cluster = values.filter { abs($0 - Double(center)) <= tolerance }.sorted()
        guard Double(cluster.count) / Double(values.count) >= 0.8 else { throw LiDARMeasurementError.mixedSurfaces }
        let z = cluster[cluster.count / 2]
        let ray = snapshot.depthSource == .lidar ? snapshot.calibration.ray(at: sensor)
            : snapshot.calibration.rectilinearRay(at: sensor)
        guard let ray else { throw LiDARMeasurementError.missingCalibration }
        let range = z * sqrt(1 + ray.x * ray.x + ray.y * ray.y)
        guard range.isFinite, snapshot.depthSource.supportedRange.contains(Float(range)) else { throw LiDARMeasurementError.noReading }
        return .init(meters: range, axialMeters: z, point: point, sampleCount: cluster.count,
                     capturedAt: snapshot.capturedAt, isFiltered: snapshot.isFiltered,
                     depthSource: snapshot.depthSource, focalProvenance: snapshot.focalProvenance,
                     calibrationScale: snapshot.calibrationScale)
    }
}

enum DistanceQuestion {
    static func isBareObjectReference(_ text: String) -> Bool {
        let value = objectReference(text).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return ["ขวด", "ขวดน้ำ", "ขวดน้ำผลไม้", "วัตถุ", "สิ่งของ", "ป้าย", "เมนู", "แก้ว", "คน", "เก้าอี้",
                "bottle", "the bottle", "water bottle", "object", "the object", "thing", "sign", "the sign", "cup", "person", "chair"].contains(value)
    }

    static func needsReferenceContext(_ text: String) -> Bool {
        let value = objectReference(text).lowercased()
        let references = ["ชิ้นนี้", "ชิ้นนั้น", "อันนี้", "อันนั้น", "สิ่งนี้", "สิ่งนั้น", "ตัวนี้", "ตัวนั้น",
                          "ขวดนี้", "ขวดนั้น", "ป้ายนี้", "ป้ายนั้น", "วัตถุนี้", "วัตถุนั้น", "ใบนี้", "ใบนั้น", "ชิ้นเดิม"]
        return value.hasPrefix("มัน") || references.contains(where: value.contains)
            || value.range(of: #"\b(?:it|(?:this|that)\s+(?:one|object|bottle|sign))\b"#,
                           options: .regularExpression) != nil
    }

    /// Grounding asks only which object to locate. A small VLM can otherwise
    /// interpret "how many meters" as an impossible image-only measurement.
    /// Units and the original question remain available to the sensor answer path.
    static func objectReference(_ text: String) -> String {
        var value = text.precomposedStringWithCanonicalMapping
        let requests = [
            #"^(?:ช่วย\s*)?(?:บอก(?:\s*หน่อย)?(?:\s*ว่า)?|ดู(?:\s*ให้\s*หน่อย)?\s*ว่า|อยากรู้ว่า|ขอทราบ(?:\s*ว่า)?)\s*"#,
            #"^please\s+"#,
            #"^(?:can|could|would)\s+you\s+"#,
            #"^tell\s+me\s+"#
        ]
        // Request scaffolding is not an object qualifier. Leaving it in place
        // would let a polite bare noun bypass the multiple-instance safeguard.
        for _ in 0..<3 {
            let previous = value
            for pattern in requests {
                value = value.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
            }
            if value == previous { break }
        }
        let patterns = [
            #"อยู่ห่างกล้องประมาณ\s*[0-9.,]+\s*(?:เมตร|เซนติเมตร)[^\n]*$"#,
            #"(?:อยู่\s*)?(?:ห่าง|ไกล|ใกล้)\s*(?:จาก\s*)?(?:กล้อง|ตัวผม|ตัวฉัน|ผม|ฉัน|เรา|โทรศัพท์)?\s*(?:ประมาณ\s*)?(?:กี่\s*(?:เซนติเมตร|เซน|เมตร)|แค่\s*ไหน|เท่า\s*(?:ไหร่|ไร))[^\n]*$"#,
            #"^(?:ช่วย)?(?:วัด|บอก)?ระยะ(?:ห่าง|ทาง)?(?:จากกล้อง)?(?:ของ)?\s*"#,
            #"\s*(?:เท่าไร|เท่าไหร่|กี่เมตร|กี่เซนติเมตร|กี่เซน)[?？!\.]*$"#,
            #"^how\s+(?:far|close)(?:\s+away)?\s+(?:is|are)\s+"#,
            #"^(?:(?:what(?:'s| is)|measure)\s+)?(?:the\s+)?distance\s+(?:to|of)\s+"#,
            #"\s+(?:away\s+)?(?:from|to)\s+(?:the\s+)?(?:camera|me|us|phone)[?!.]*$"#
        ]
        for pattern in patterns {
            value = value.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return value.isEmpty ? "วัตถุที่ผู้ใช้กำลังกล่าวถึง" : value
    }

    static func isDistance(_ text: String) -> Bool {
        let value = intentText(text)
        let explicitQuestion = matches(#"(?:ห่าง|ไกล|ใกล้)\s*(?:จาก\s*)?(?:กล้อง|ตัวผม|ตัวฉัน|ผม|ฉัน|เรา|โทรศัพท์)?\s*(?:ประมาณ\s*)?(?:กี่\s*(?:เซนติเมตร|เซน|เมตร)|แค่\s*ไหน|เท่า\s*(?:ไหร่|ไร))|\bhow\s+(?:far|close)\b"#, value)
        let measureRequest = matches(#"(?:ช่วย)?วัด\s*ระยะ|\bmeasure\s+(?:the\s+)?distance\b"#, value)
        let negatedRequest = matches(#"(?:ไม่ต้อง|อย่า)\s*(?:วัด|บอก|ตอบ)(?:ค่า)?\s*ระยะ|\b(?:do\s+not|don't|don’t|no\s+need\s+to)\s+(?:measure|tell|give)(?:\s+me)?\s+(?:the\s+)?distance\b"#, value)
        if negatedRequest && !explicitQuestion { return false }
        // Printed distance values and the word "distance" are document content.
        // They must not hijack OCR/translation questions into the sensor path.
        let asksWhatIsPrinted = matches(#"^(?:ช่วย\s*)?(?:อ่าน|แปล|สรุป(?:ข้อความ|ป้าย|ฉลาก))|(?:ป้าย|ฉลาก|เอกสาร|ข้อความ)\s*(?:เขียนว่า|เขียนไว้)|^(?:please\s+)?(?:read|translate|summari[sz]e)\b|^what\s+(?:does|do)\b.+\b(?:say|mean)\b|^what\b.+\b(?:written|printed)\b"#, value)
        if asksWhatIsPrinted { return false }
        let textTask = matches(#"อ่านข้อความ|อ่านคำ|เขียนว่า|เขียนไว้|บนป้าย.*เขียน|ในข้อความ|คำว่า|แปล|สรุป|หมายความ|ความหมาย|\b(?:read|written|printed|says?|means?|translate|translation|summari[sz]e|explain|word|text)\b"#, value)
        if textTask && !explicitQuestion && !measureRequest { return false }
        return explicitQuestion
            || matches(#"ห่าง|ไกล\s*(?:แค่|เท่า)|ใกล้\s*(?:แค่|เท่า)|อยู่ไกล|(?:บอก|วัด)\s*ระยะ|ระยะ\s*(?:ทาง|ห่าง|ระหว่าง|ของ|จาก|ถึง|เท่า)|กี่\s*(?:เมตร|เซน)|\b(?:distance|apart)\b|\bhow\s+many\s+(?:centimet(?:er|re)s?|met(?:er|re)s?)\b"#, value)
    }
    static func isBetweenObjects(_ text: String) -> Bool {
        guard isDistance(text) else { return false }
        let value = intentText(text)
        // "The bottle between two boxes" identifies one target. Only actual
        // measurement endpoints determine whether the camera is one of them.
        let cameraEndpoint = matches(#"(?:ห่าง|ไกล|ใกล้|ระยะ)\s*(?:จาก|ถึง)?\s*(?:กล้อง|ตัวผม|ตัวฉัน|ผม|ฉัน|เรา|โทรศัพท์)|ระยะ\s*(?:ห่าง\s*)?ระหว่าง\s*(?:กล้อง|โทรศัพท์)\s*(?:กับ|และ)|ระยะ\s*(?:ห่าง\s*)?ระหว่าง.+(?:กับ|และ)\s*(?:กล้อง|โทรศัพท์)|\b(?:from|to)\s+(?:the\s+)?(?:camera|phone)\b|\b(?:from|to)\s+(?:me|us)\b|\bdistance\s+between\s+(?:the\s+)?(?:camera|phone)\b|\bdistance\s+between\b.+\band\s+(?:the\s+)?(?:camera|phone)\b"#, value)
        if cameraEndpoint { return false }
        return matches(#"ห่าง\s*กัน|ระยะ\s*(?:ห่าง\s*)?ระหว่าง|(?:ห่าง|ไกล|ระยะ)\s*จาก\s*|\bapart\b|\b(?:distance|separation)\s+between\b|\b(?:far|close)\b.+\b(?:from|to)\s+|\bdistance\s+from\b.+\bto\b"#, value)
    }
    static func usesCentimeters(_ text: String) -> Bool {
        ["เซนติเมตร", "กี่เซน", "centimeter", "centimetre", " cm"].contains { text.lowercased().contains($0) }
    }

    private static func matches(_ pattern: String, _ value: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    private static func intentText(_ text: String) -> String {
        // Ignore quoted print when choosing a tool; keep the original question
        // unchanged for object selection and the visible transcript.
        let value = text.precomposedStringWithCanonicalMapping.lowercased()
        let withoutQuoted = value
            .replacingOccurrences(of: #"\"[^\"]*\"|“[^”]*”|‘[^’]*’|(?<![\p{L}\p{N}])'[^']*'(?![\p{L}\p{N}])"#,
                                  with: " ", options: .regularExpression)
        return withoutQuoted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? value : withoutQuoted
    }
}
