import Foundation
import CoreGraphics

enum DepthCalibrationError: LocalizedError, Equatable {
    case missingCamera, invalidScale, unsupportedSource, invalidKnownDistance

    var errorDescription: String? {
        switch self {
        case .missingCamera: "ไม่มีรหัสกล้องสำหรับบันทึกค่าปรับเทียบ กรุณาถ่ายภาพจากกล้องอีกครั้ง"
        case .invalidScale: "ค่าปรับเทียบต้องอยู่ระหว่าง 0.25–4 เท่า"
        case .unsupportedSource: "ปรับสเกลได้เฉพาะระยะประมาณจาก Depth Anything 3 Metric"
        case .invalidKnownDistance: "ระยะจริงสำหรับปรับเทียบต้องอยู่ระหว่าง 0.3–8 เมตร"
        }
    }
}

/// UserDefaults provides synchronized access. The store keeps only that immutable
/// reference, and calibration keys are scoped to a concrete capture device/lens.
final class DepthCalibrationStore: @unchecked Sendable {
    static let shared = DepthCalibrationStore()
    private let defaults: UserDefaults
    private let prefix = "LunaV.DepthAnything3Metric.Calibration.v1."

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func scale(for cameraIdentifier: String?) -> Double {
        guard let key = key(for: cameraIdentifier), let number = defaults.object(forKey: key) as? NSNumber else { return 1 }
        let value = number.doubleValue
        return Self.isValidScale(value) ? value : 1
    }

    func setScale(_ scale: Double, for cameraIdentifier: String) throws {
        guard let key = key(for: cameraIdentifier) else { throw DepthCalibrationError.missingCamera }
        guard Self.isValidScale(scale) else { throw DepthCalibrationError.invalidScale }
        defaults.set(scale, forKey: key)
    }

    func reset(for cameraIdentifier: String) {
        guard let key = key(for: cameraIdentifier) else { return }
        defaults.removeObject(forKey: key)
    }

    /// The reference must be a measured camera-to-surface distance for this
    /// exact point/photo. This fit adjusts one scale; it does not establish an
    /// uncertainty bound or validate other objects, scenes or camera lenses.
    static func calibratedScale(snapshot: LiDARSnapshot, point: CGPoint = CGPoint(x: 0.5, y: 0.5),
                                knownMeters: Double) throws -> Double {
        guard snapshot.depthSource == .depthAnything3Metric else { throw DepthCalibrationError.unsupportedSource }
        guard knownMeters.isFinite, (0.3...8).contains(knownMeters) else { throw DepthCalibrationError.invalidKnownDistance }
        let measurement = try LiDARRangeReader.measure(snapshot, at: point)
        let scale = snapshot.calibrationScale * knownMeters / measurement.meters
        guard isValidScale(scale) else { throw DepthCalibrationError.invalidScale }
        return scale
    }

    static func isValidScale(_ scale: Double) -> Bool {
        scale.isFinite && (0.25...4).contains(scale)
    }

    private func key(for cameraIdentifier: String?) -> String? {
        guard let cameraIdentifier, !cameraIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              cameraIdentifier.utf8.count <= 1_024 else { return nil }
        return prefix + Data(cameraIdentifier.utf8).base64EncodedString()
    }
}

extension LiDARSnapshot {
    /// Reuses an already paired model map. Previously rejected sky/invalid data
    /// stays rejected, including values clipped by earlier range validation.
    func applyingCalibrationScale(_ newScale: Double) throws -> LiDARSnapshot {
        guard depthSource == .depthAnything3Metric else { throw DepthCalibrationError.unsupportedSource }
        guard DepthCalibrationStore.isValidScale(newScale), DepthCalibrationStore.isValidScale(calibrationScale) else {
            throw DepthCalibrationError.invalidScale
        }
        guard width >= 5, height >= 5, width <= 4_096, height <= 4_096,
              depthMeters.count == width * height, let modelValidity, modelValidity.count == depthMeters.count else {
            throw LiDARMeasurementError.invalidMap
        }
        let ratio = newScale / calibrationScale
        var values = [Float](repeating: .nan, count: depthMeters.count)
        var validity = [Bool](repeating: false, count: depthMeters.count)
        for index in depthMeters.indices where modelValidity[index] {
            let value = Double(depthMeters[index]) * ratio
            guard value.isFinite, depthSource.supportedRange.contains(Float(value)) else { continue }
            values[index] = Float(value)
            validity[index] = true
        }
        return .init(width: width, height: height, depthMeters: values, orientation: orientation,
                     calibration: calibration, capturedAt: capturedAt, photoTimestamp: photoTimestamp,
                     isAbsolute: isAbsolute, isHighQuality: isHighQuality, isFiltered: isFiltered,
                     depthSource: depthSource, modelValidity: validity, focalProvenance: focalProvenance,
                     calibrationScale: newScale)
    }
}
