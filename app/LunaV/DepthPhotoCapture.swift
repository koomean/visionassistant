import AVFoundation
import Foundation
import ImageIO

struct CapturedPhoto: Sendable {
    let data: Data
    var depth: LiDARSnapshot?
    var lidarRequested = false
    var depthIssue: String?
    var depthDiagnostics: [String: String] = [:]
    var cameraIntrinsics: PhotoCameraIntrinsics?
    var cameraIdentifier: String?
    var capturedAt = Date()
    var captureTimestamp: Double = 0
}

enum CameraDepthMode: Sendable {
    case colorOnly, lidar, unavailable
    var title: String {
        switch self {
        case .colorOnly: "ภาพสี"
        case .lidar: "พร้อม LiDAR"
        case .unavailable: "ภาพสี · LiDAR ไม่พร้อม"
        }
    }
}

enum DepthPhotoCapture {
    static func extract(photo: AVCapturePhoto, data: Data, lidarRequested: Bool,
                        videoIntrinsics: PhotoCameraIntrinsics? = nil,
                        includeDiagnostics: Bool? = nil) -> CapturedPhoto {
        var result = CapturedPhoto(data: data, lidarRequested: lidarRequested,
                                   captureTimestamp: CMTimeGetSeconds(photo.timestamp))
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            result.cameraIntrinsics = cameraIntrinsics(properties: properties,
                                                        calibration: photo.cameraCalibrationData ?? photo.depthData?.cameraCalibrationData,
                                                        videoIntrinsics: videoIntrinsics)
            result.depthDiagnostics["focalProvenance"] = result.cameraIntrinsics?.provenance.rawValue ?? "unavailable"
        }
        guard lidarRequested else { return result }
        if let raw = photo.depthData {
            result.depthDiagnostics.merge([
                "quality": String(raw.depthDataQuality.rawValue),
                "accuracy": String(raw.depthDataAccuracy.rawValue),
                "filtered": String(raw.isDepthDataFiltered),
                "nativeDepthType": String(raw.depthDataType),
                "nativeMap": "\(CVPixelBufferGetWidth(raw.depthDataMap))x\(CVPixelBufferGetHeight(raw.depthDataMap))",
                "calibration": String(raw.cameraCalibrationData != nil),
                "inverseTableBytes": String(raw.cameraCalibrationData?.inverseLensDistortionLookupTable?.count ?? 0)
            ]) { _, new in new }
            if let calibration = raw.cameraCalibrationData {
                result.depthDiagnostics["referenceSize"] = "\(calibration.intrinsicMatrixReferenceDimensions)"
            }
        } else { result.depthDiagnostics["depthData"] = "missing" }
        guard let raw = photo.depthData else {
            result.depthIssue = "ภาพนี้ไม่มี depth จาก LiDAR ที่มีคุณภาพพอ กรุณาถ่ายใหม่"
            return result
        }
        let depth = raw.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        result.depthDiagnostics["convertedDepthType"] = String(depth.depthDataType)
        let map = depth.depthDataMap
        let width = CVPixelBufferGetWidth(map), height = CVPixelBufferGetHeight(map)
        guard width > 0, height > 0, CVPixelBufferGetPixelFormatType(map) == kCVPixelFormatType_DepthFloat32 else {
            result.depthIssue = LiDARMeasurementError.invalidMap.localizedDescription
            return result
        }
        guard CVPixelBufferLockBaseAddress(map, .readOnly) == kCVReturnSuccess else { return result }
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return result }
        let stride = CVPixelBufferGetBytesPerRow(map) / MemoryLayout<Float>.stride
        let values = base.assumingMemoryBound(to: Float.self)
        var copy: [Float] = []
        copy.reserveCapacity(width * height)
        for row in 0..<height { copy.append(contentsOf: UnsafeBufferPointer(start: values + row * stride, count: width)) }
        // Sorting the entire map is useful for sensor diagnostics, not ranging.
        // Ordinary capture retains the same raw samples and validation below.
        if includeDiagnostics ?? diagnosticsEnabled(arguments: CommandLine.arguments) {
            let finite = copy.filter(\.isFinite).sorted()
            let total = Double(copy.count)
            result.depthDiagnostics["finiteFraction"] = String(Double(finite.count) / total)
            result.depthDiagnostics["inRangeFraction"] = String(Double(finite.lazy.filter { $0 >= 0.2 && $0 <= 5 }.count) / total)
            result.depthDiagnostics["nearFraction"] = String(Double(finite.lazy.filter { $0 >= 0.2 && $0 <= 2 }.count) / total)
            result.depthDiagnostics["centerZ"] = String(copy[(height / 2) * width + width / 2])
            if !finite.isEmpty {
                result.depthDiagnostics["finiteMin"] = String(finite[0])
                result.depthDiagnostics["finiteMax"] = String(finite[finite.count - 1])
                for percentile in [10, 25, 50, 75, 90] {
                    result.depthDiagnostics["depthP\(percentile)"] = String(finite[(finite.count - 1) * percentile / 100])
                }
            }
        }
        guard raw.depthDataAccuracy == .absolute, raw.depthDataQuality == .high else {
            result.depthIssue = "ภาพนี้ไม่มี depth จาก LiDAR ที่มีคุณภาพพอ กรุณาถ่ายใหม่"
            return result
        }
        guard let calibration = depth.cameraCalibrationData,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let imageWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let imageHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            result.depthIssue = "ไม่มีข้อมูลเทียบตำแหน่งภาพกับ LiDAR กรุณาถ่ายใหม่"
            return result
        }
        result.depthDiagnostics["rgbRawSize"] = "\(imageWidth.intValue)x\(imageHeight.intValue)"
        let orientationValue = (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        guard let orientation = DepthImageOrientation(rawValue: orientationValue) else { return result }
        let reference = calibration.intrinsicMatrixReferenceDimensions
        let imageAspect = imageWidth.doubleValue / imageHeight.doubleValue
        guard width > 0, height > 0, reference.width > 0, reference.height > 0,
              abs(Double(width) / Double(height) / imageAspect - 1) < 0.01,
              abs(Double(reference.width / reference.height) / imageAspect - 1) < 0.01 else {
            result.depthIssue = LiDARMeasurementError.invalidMap.localizedDescription
            return result
        }
        let matrix = calibration.intrinsicMatrix
        let inverse = calibration.inverseLensDistortionLookupTable.map { data in
            data.withUnsafeBytes { bytes in
                (0..<(data.count / MemoryLayout<Float>.size)).map { bytes.loadUnaligned(fromByteOffset: $0 * 4, as: Float.self) }
            }
        }
        result.depth = .init(width: width, height: height, depthMeters: copy, orientation: orientation,
                             calibration: .init(referenceWidth: reference.width, referenceHeight: reference.height,
                                                fx: Double(matrix.columns.0.x), fy: Double(matrix.columns.1.y),
                                                cx: Double(matrix.columns.2.x), cy: Double(matrix.columns.2.y),
                                                distortionCenter: calibration.lensDistortionCenter, inverseDistortion: inverse),
                             capturedAt: Date(), photoTimestamp: CMTimeGetSeconds(photo.timestamp),
                             isAbsolute: true, isHighQuality: true, isFiltered: depth.isDepthDataFiltered)
        if inverse == nil || (inverse?.count ?? 0) < 2 {
            result.depthIssue = LiDARMeasurementError.missingCalibration.localizedDescription
        } else if !copy.contains(where: { $0.isFinite && $0 >= 0.2 && $0 <= 5 }) {
            result.depthIssue = "ภาพนี้ไม่มีค่า LiDAR ในช่วงที่แอพวัดได้ (0.2–5 เมตร) กรุณาเล็งวัตถุและถ่ายใหม่"
        }
        return result
    }

    static func diagnosticsEnabled(arguments: [String]) -> Bool {
        arguments.contains("--validate-lidar") || arguments.contains("--validate-memory")
    }

    private static func cameraIntrinsics(properties: [CFString: Any], calibration: AVCameraCalibrationData?,
                                         videoIntrinsics: PhotoCameraIntrinsics?) -> PhotoCameraIntrinsics? {
        guard let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0,
              let orientation = DepthImageOrientation(rawValue: (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1)
        else { return nil }
        let aspect = Double(width) / Double(height)
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let focal35 = (exif?[kCGImagePropertyExifFocalLenIn35mmFilm] as? NSNumber)?.doubleValue
        if let calibration {
            let reference = calibration.intrinsicMatrixReferenceDimensions
            if reference.width > 0, reference.height > 0,
               abs(Double(reference.width / reference.height) / aspect - 1) < 0.01 {
                let matrix = calibration.intrinsicMatrix
                let result = PhotoCameraIntrinsics(referenceWidth: Double(reference.width), referenceHeight: Double(reference.height),
                                                   fx: Double(matrix.columns.0.x), fy: Double(matrix.columns.1.y),
                                                   cx: Double(matrix.columns.2.x), cy: Double(matrix.columns.2.y),
                                                   orientation: orientation, provenance: .cameraCalibration)
                if result.isValid { return result }
            }
        }
        if let video = videoIntrinsics, video.isValid, let focal35, focal35.isFinite, focal35 > 0,
           abs(video.referenceWidth / video.referenceHeight / aspect - 1) < 0.01,
           abs((video.fx + video.fy) / 2 * hypot(36, 24)
               / hypot(video.referenceWidth, video.referenceHeight) / focal35 - 1) < 0.12 {
            // Aspect alone does not prove the video and photo have the same
            // field of view: also check the still photo's EXIF focal estimate.
            // Rounding of EXIF's integer-mm value is allowed, large crops aren't.
            return .init(referenceWidth: Double(width), referenceHeight: Double(height),
                         fx: video.fx * Double(width) / video.referenceWidth,
                         fy: video.fy * Double(height) / video.referenceHeight,
                         cx: video.cx * Double(width) / video.referenceWidth,
                         cy: video.cy * Double(height) / video.referenceHeight,
                         orientation: orientation, provenance: .videoIntrinsicMatrix)
        }
        guard let focal35 else { return nil }
        return .exif35mm(focalLength: focal35, width: width, height: height, orientation: orientation)
    }
}
