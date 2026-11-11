import Foundation
import CoreGraphics
import CoreVideo
import ImageIO
import os
@preconcurrency import CoreML

enum MonocularDepthError: LocalizedError {
    case missingModel, notPrepared, busy, invalidImage, invalidModel, invalidIntrinsics, insufficientMemory
    var errorDescription: String? {
        switch self {
        case .missingModel: "ไม่พบโมเดล Depth Anything 3 Metric ในแอพ"
        case .notPrepared: "โมเดลประเมินระยะยังไม่พร้อม กรุณารอให้เตรียมระบบเสร็จ"
        case .busy: "ระบบประเมินระยะกำลังทำงาน กรุณารอสักครู่"
        case .invalidImage: "เปิดภาพเพื่อประเมินระยะไม่ได้"
        case .invalidModel: "โมเดลประเมินระยะให้ข้อมูลไม่ตรงรูปแบบ"
        case .invalidIntrinsics: "ไม่มีข้อมูลเลนส์ที่ตรงกับภาพ จึงยังประเมินระยะเป็นเมตรไม่ได้"
        case .insufficientMemory: "หน่วยความจำที่แอพใช้ได้ไม่พอสำหรับโมเดลประเมินระยะ"
        }
    }
}

/// One model owner, one real CoreML operation at a time. Cancellation never
/// releases the model or admits another worker while a synchronous prediction
/// still owns its buffers. A memory release requested during work is deferred.
actor MonocularDepthRuntime {
    static let shared = MonocularDepthRuntime(preferGPU: ProcessInfo.processInfo.arguments.contains("--validate-depth-gpu"))
    private let preferGPU: Bool
    init(preferGPU: Bool = false) { self.preferGPU = preferGPU }
    nonisolated static let reservedBytes: Int = 1_610_612_736
    /// Conservative additional working allowance after the weights are resident;
    /// this is an admission budget, not a claimed iPhone memory measurement.
    nonisolated static let predictionWorkingBytes: Int = 536_870_912
    private var prepared: MonocularDepthModel?
    private var preparedURL: URL?
    private var warmedURL: URL?
    private var working = false
    private var releaseRequested = false
    private var modelLoads = 0
    private var warmups = 0
    private var predictions = 0

    var isPrepared: Bool { prepared != nil && !releaseRequested }
    var hasPendingWork: Bool { working }

    struct PreparationStats: Sendable, Codable {
        let modelLoads: Int
        let warmups: Int
        let predictions: Int
        let isPrepared: Bool
        let hasPendingWork: Bool
    }

    func preparationStats() -> PreparationStats {
        .init(modelLoads: modelLoads, warmups: warmups, predictions: predictions,
              isPrepared: isPrepared, hasPendingWork: hasPendingWork)
    }

    nonisolated static var bundledModelURL: URL? {
        let candidates = [
            Bundle.main.url(forResource: "DepthAnything3Metric", withExtension: "mlmodelc"),
            Bundle.main.url(forResource: "DepthAnything3Metric", withExtension: "mlmodelc", subdirectory: "DepthAnything3Metric")
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Validates the model with an actual prediction once per runtime/model URL.
    /// Later weight reloads reuse that validation; real predictions still run on
    /// the fresh model. No camera, network, or guessed intrinsics enter warm-up.
    func prepare(modelURL: URL? = nil) async throws {
        try Task.checkCancellation()
        guard !working else { throw MonocularDepthError.busy }
        guard let url = modelURL ?? Self.bundledModelURL else { throw MonocularDepthError.missingModel }
        guard url.pathExtension == "mlmodelc" else { throw MonocularDepthError.invalidModel }
        if isPrepared, preparedURL == url { return }
        working = true
        releaseRequested = false
        prepared = nil
        preparedURL = nil
        defer { finishWork() }
        let preferGPU = self.preferGPU
        let needsWarmup = warmedURL != url
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            try Self.requireMemory(Self.reservedBytes)
            let configuration = MLModelConfiguration()
            configuration.computeUnits = preferGPU ? .cpuAndGPU : .all
            Self.record("load-start", preferGPU: preferGPU)
            let box = try MonocularDepthModel(model: MLModel(contentsOf: url, configuration: configuration))
            Self.record("load-ready", preferGPU: preferGPU)
            try Task.checkCancellation()
            if needsWarmup {
                let warmImage = try MonocularDepthPreprocessor.emptyPixelBuffer()
                let input = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: warmImage)])
                Self.record("warm-start", preferGPU: preferGPU)
                let output = try box.model.prediction(from: input)
                _ = try MonocularDepthPreprocessor.grid(output.featureValue(for: "canonicalDepth")?.multiArrayValue)
                _ = try MonocularDepthPreprocessor.grid(output.featureValue(for: "sky")?.multiArrayValue)
            }
            try Task.checkCancellation()
            Self.record(needsWarmup ? "warm-ready" : "warmup-reused", preferGPU: preferGPU)
            return box
        }
        let box = try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: { worker.cancel() }
        guard !releaseRequested else { throw CancellationError() }
        prepared = box
        preparedURL = url
        warmedURL = url
        modelLoads += 1
        if needsWarmup { warmups += 1 }
        Self.record("prepared", preferGPU: preferGPU)
    }

    private nonisolated static func record(_ event: String, preferGPU: Bool) {
        #if os(iOS)
        guard event == "prepared" || ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--validate-") }) else { return }
        let value: [String: Any] = ["event": event, "compute": preferGPU ? "cpuAndGPU" : "all",
            "availableBytes": Int(os_proc_available_memory()), "timestamp": Date().ISO8601Format()]
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            try? data.write(to: URL.documentsDirectory.appending(path: "DepthRuntimeCheck.json"), options: .atomic)
        }
        #endif
    }

    /// Returns immediately during an in-flight CoreML call; its owner unloads
    /// when the call actually ends. hasPendingWork remains true until then.
    func release() async {
        releaseRequested = true
        guard !working else { return }
        prepared = nil
        preparedURL = nil
        releaseRequested = false
    }

    func predict(imageURL: URL, intrinsics: PhotoCameraIntrinsics, calibrationScale: Double = 1,
                 capturedAt: Date = Date(), photoTimestamp: Double = 0) async throws -> LiDARSnapshot {
        try Task.checkCancellation()
        guard intrinsics.isValid else { throw MonocularDepthError.invalidIntrinsics }
        guard !working else { throw MonocularDepthError.busy }
        guard let box = prepared, !releaseRequested else { throw MonocularDepthError.notPrepared }
        working = true
        defer { finishWork() }
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let input = try MonocularDepthPreprocessor.prepare(imageURL: imageURL)
            guard input.geometry.matches(intrinsics: intrinsics) else { throw MonocularDepthError.invalidIntrinsics }
            let features = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: input.pixelBuffer)])
            try Task.checkCancellation()
            try Self.requireMemory(Self.predictionWorkingBytes)
            let result = try box.model.prediction(from: features)
            try Task.checkCancellation()
            let raw = try MonocularDepthPreprocessor.grid(result.featureValue(for: "canonicalDepth")?.multiArrayValue)
            let sky = try MonocularDepthPreprocessor.grid(result.featureValue(for: "sky")?.multiArrayValue)
            let uprightRaw = try input.geometry.uprightGrid(from: raw)
            let uprightSky = try input.geometry.uprightGrid(from: sky)
            return try DepthAnythingMetricGeometry.snapshot(
                rawDepth: uprightRaw, sky: uprightSky,
                width: input.geometry.uprightContentWidth, height: input.geometry.uprightContentHeight,
                modelInputWidth: input.geometry.uprightContentWidth,
                modelInputHeight: input.geometry.uprightContentHeight,
                intrinsics: intrinsics, calibrationScale: calibrationScale,
                capturedAt: capturedAt, photoTimestamp: photoTimestamp)
        }
        let snapshot = try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: { worker.cancel() }
        guard !releaseRequested else { throw CancellationError() }
        predictions += 1
        return snapshot
    }

    private func finishWork() {
        working = false
        if releaseRequested {
            prepared = nil
            preparedURL = nil
            releaseRequested = false
        }
    }

    private nonisolated static func requireMemory(_ requiredBytes: Int) throws {
        let availableBytes: Int?
        #if os(iOS) || os(tvOS) || os(visionOS)
        availableBytes = Int(os_proc_available_memory())
        #else
        // The process-limit API is unavailable on macOS. An unknown budget is
        // distinct from iOS returning zero remaining bytes and allows native QA.
        availableBytes = nil
        #endif
        guard MonocularDepthMemoryPolicy.allows(availableBytes: availableBytes, requiredBytes: requiredBytes) else {
            throw MonocularDepthError.insufficientMemory
        }
    }
}

enum MonocularDepthMemoryPolicy {
    static func allows(availableBytes: Int?, requiredBytes: Int) -> Bool {
        guard requiredBytes > 0 else { return false }
        guard let availableBytes else { return true }
        return availableBytes >= requiredBytes
    }
}

/// CoreML models are immutable during prediction. This narrowly scoped wrapper
/// crosses one detached worker boundary; actor ownership prevents parallel use.
private final class MonocularDepthModel: @unchecked Sendable {
    let model: MLModel
    init(model: MLModel) throws {
        guard let image = model.modelDescription.inputDescriptionsByName["image"]?.imageConstraint,
              image.pixelsWide == MonocularDepthImageGeometry.modelWidth,
              image.pixelsHigh == MonocularDepthImageGeometry.modelHeight,
              model.modelDescription.outputDescriptionsByName["canonicalDepth"] != nil,
              model.modelDescription.outputDescriptionsByName["sky"] != nil else {
            throw MonocularDepthError.invalidModel
        }
        self.model = model
    }
}

/// All coordinates here are top-left raster coordinates. Integer content sizes
/// preserve the actual resize, including subpixel rounding, for focal scaling.
struct MonocularDepthImageGeometry: Sendable {
    static let modelWidth = 392
    static let modelHeight = 294
    let uprightWidth: Int
    let uprightHeight: Int
    let rotated: Bool
    let contentWidth: Int
    let contentHeight: Int
    let padX: Int
    let padY: Int

    init(width: Int, height: Int) throws {
        guard width >= 5, height >= 5, width <= 16_384, height <= 16_384 else {
            throw MonocularDepthError.invalidImage
        }
        uprightWidth = width
        uprightHeight = height
        rotated = height > width
        let w = rotated ? height : width
        let h = rotated ? width : height
        let scale = min(Double(Self.modelWidth) / Double(w), Double(Self.modelHeight) / Double(h))
        contentWidth = min(Self.modelWidth, max(1, Int((Double(w) * scale).rounded())))
        contentHeight = min(Self.modelHeight, max(1, Int((Double(h) * scale).rounded())))
        padX = (Self.modelWidth - contentWidth) / 2
        padY = (Self.modelHeight - contentHeight) / 2
        guard contentWidth >= 5, contentHeight >= 5 else { throw MonocularDepthError.invalidImage }
    }

    var uprightContentWidth: Int { rotated ? contentHeight : contentWidth }
    var uprightContentHeight: Int { rotated ? contentWidth : contentHeight }

    /// A cropped photo must not silently inherit the full sensor's intrinsics.
    /// Thumbnail rounding is allowed; a different frame aspect is rejected.
    func matches(intrinsics: PhotoCameraIntrinsics) -> Bool {
        guard intrinsics.isValid else { return false }
        let swaps = intrinsics.orientation.rawValue >= 5
        let expected = swaps ? intrinsics.referenceHeight / intrinsics.referenceWidth
            : intrinsics.referenceWidth / intrinsics.referenceHeight
        let actual = Double(uprightWidth) / Double(uprightHeight)
        return abs(actual / expected - 1) < 0.02
    }

    func modelPoint(fromUpright point: CGPoint) -> CGPoint {
        let x = rotated ? point.y : point.x
        let y = rotated ? 1 - point.x : point.y
        return CGPoint(x: Double(padX) + x * Double(contentWidth),
                       y: Double(padY) + y * Double(contentHeight))
    }

    func uprightGrid(from model: [Float]) throws -> [Float] {
        guard model.count == Self.modelWidth * Self.modelHeight else { throw MonocularDepthError.invalidModel }
        var output = [Float](repeating: .nan, count: contentWidth * contentHeight)
        for y in 0..<uprightContentHeight {
            for x in 0..<uprightContentWidth {
                let modelX = padX + (rotated ? y : x)
                let modelY = padY + (rotated ? contentHeight - 1 - x : y)
                output[y * uprightContentWidth + x] = model[modelY * Self.modelWidth + modelX]
            }
        }
        return output
    }
}

struct MonocularDepthInput {
    let pixelBuffer: CVPixelBuffer
    let geometry: MonocularDepthImageGeometry
}

enum MonocularDepthPreprocessor {
    static func prepare(imageURL: URL) throws -> MonocularDepthInput {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2_048,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw MonocularDepthError.invalidImage }
        return try prepare(image: image)
    }

    /// Decode once to an explicit RGBA raster, then sample directly into BGRA.
    /// The tiny 392x294 resize avoids CoreImage's bottom-left buffer ambiguity.
    /// Native corner-color tests verify both decoder and portrait inverse map.
    static func prepare(image: CGImage) throws -> MonocularDepthInput {
        let geometry = try MonocularDepthImageGeometry(width: image.width, height: image.height)
        var source = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let decoded: Bool = source.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard decoded else { throw MonocularDepthError.invalidImage }
        let buffer = try emptyPixelBuffer()
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let address = CVPixelBufferGetBaseAddress(buffer) else { throw MonocularDepthError.invalidImage }
        let pixels = address.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<geometry.contentHeight {
            if y % 16 == 0 { try Task.checkCancellation() }
            for x in 0..<geometry.contentWidth {
                let u = (Double(x) + 0.5) / Double(geometry.contentWidth)
                let v = (Double(y) + 0.5) / Double(geometry.contentHeight)
                let sx = (geometry.rotated ? 1 - v : u) * Double(image.width) - 0.5
                let sy = (geometry.rotated ? u : v) * Double(image.height) - 0.5
                let floorX = Int(floor(sx)), floorY = Int(floor(sy))
                let x0 = min(image.width - 1, max(0, floorX)), x1 = min(image.width - 1, max(0, floorX + 1))
                let y0 = min(image.height - 1, max(0, floorY)), y1 = min(image.height - 1, max(0, floorY + 1))
                let tx = sx - Double(floorX), ty = sy - Double(floorY)
                let output = (y + geometry.padY) * stride + (x + geometry.padX) * 4
                for channel in 0..<3 {
                    let a = Double(source[(y0 * image.width + x0) * 4 + channel])
                    let b = Double(source[(y0 * image.width + x1) * 4 + channel])
                    let c = Double(source[(y1 * image.width + x0) * 4 + channel])
                    let d = Double(source[(y1 * image.width + x1) * 4 + channel])
                    let value = (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty
                    pixels[output + (channel == 0 ? 2 : channel == 2 ? 0 : 1)] = UInt8(min(255, max(0, value.rounded())))
                }
                pixels[output + 3] = 255
            }
        }
        return MonocularDepthInput(pixelBuffer: buffer, geometry: geometry)
    }

    static func emptyPixelBuffer() throws -> CVPixelBuffer {
        var result: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, MonocularDepthImageGeometry.modelWidth,
                                        MonocularDepthImageGeometry.modelHeight, kCVPixelFormatType_32BGRA,
                                        [kCVPixelBufferIOSurfacePropertiesKey: [:],
                                         kCVPixelBufferMetalCompatibilityKey: true] as CFDictionary, &result)
        guard status == kCVReturnSuccess, let buffer = result else { throw MonocularDepthError.invalidImage }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw MonocularDepthError.invalidImage }
        base.initializeMemory(as: UInt8.self, repeating: 0,
                              count: CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
        return buffer
    }

    static func grid(_ array: MLMultiArray?) throws -> [Float] {
        guard let array, array.dataType == .float32,
              array.shape.map(\.intValue) == [1, MonocularDepthImageGeometry.modelHeight, MonocularDepthImageGeometry.modelWidth]
        else { throw MonocularDepthError.invalidModel }
        let strides = array.strides.map(\.intValue)
        let source = array.dataPointer.assumingMemoryBound(to: Float.self)
        var result = [Float](repeating: 0, count: array.count)
        for y in 0..<MonocularDepthImageGeometry.modelHeight {
            for x in 0..<MonocularDepthImageGeometry.modelWidth {
                result[y * MonocularDepthImageGeometry.modelWidth + x] = source[y * strides[1] + x * strides[2]]
            }
        }
        return result
    }
}
