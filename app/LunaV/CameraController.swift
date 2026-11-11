import AVFoundation
import Observation
import SwiftUI
import UIKit
import simd

@MainActor @Observable
final class CameraController {
    var isReady = false
    var isCapturing = false
    var message: String?
    var permissionDenied = false
    var depthMode: CameraDepthMode = .colorOnly
    let engine = CaptureEngine()
    let obstacles = ObstacleHaptics()
    @ObservationIgnored private var obstacleRevision = UUID()
    @ObservationIgnored private var stopRevision = UUID()
    var session: AVCaptureSession { engine.session }

    func start() async {
        #if targetEnvironment(simulator)
        message = "เลือกรูปเพื่อทดสอบบน Simulator"
        return
        #else
        let revision = stopRevision
        let allowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: allowed = true
        case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
        default: allowed = false
        }
        guard revision == stopRevision, !Task.isCancelled else { return }
        guard allowed else {
            permissionDenied = true
            message = "อนุญาตการใช้กล้องใน Settings หรือเลือกรูปจากคลังภาพ"
            return
        }
        do {
            let mode = try await engine.start()
            guard revision == stopRevision else { return }
            depthMode = mode
            isReady = true
            message = nil
        } catch {
            if revision == stopRevision { message = error.localizedDescription }
        }
        #endif
    }

    func stop() async {
        stopRevision = UUID()
        obstacleRevision = UUID()
        // A shutter press during asynchronous shutdown must queue a restart,
        // instead of seeing the old ready flag and capturing after stopRunning.
        isReady = false
        obstacles.suspend()
        await engine.stop()
    }

    func flip() async {
        do { depthMode = try await engine.flip() }
        catch { message = error.localizedDescription }
    }

    /// Called when foreground/live-camera/voice state or the saved settings
    /// change. A scalar callback is the only data crossing onto the UI actor.
    func setObstacleMonitoring(active: Bool) async {
        let revision = UUID()
        obstacleRevision = revision
        obstacles.suspend()
        let attach = obstacles.configuration.enabled && obstacles.isSupported
        let thermal = ProcessInfo.processInfo.thermalState
        let eligible = active && isReady && !isCapturing && thermal != .serious && thermal != .critical
        let enabled = attach && eligible && depthMode == .lidar
        let available = await engine.setObstacleMonitoring(attach: attach, enabled: enabled) { [weak self] distance, timestamp in
            Task { @MainActor [weak self] in
                guard let self, self.obstacleRevision == revision else { return }
                self.obstacles.receive(distance: distance, timestamp: timestamp)
            }
        }
        guard obstacleRevision == revision else { return }
        obstacles.setActive(eligible, streamAvailable: available && depthMode == .lidar)
    }

    func capture() async throws -> CapturedPhoto {
        guard !isCapturing else { throw CameraError.busy }
        isCapturing = true
        obstacleRevision = UUID()
        obstacles.suspend()
        defer { isCapturing = false }
        return try await engine.capture()
    }
}

enum CameraError: LocalizedError {
    case unavailable, captureFailed, busy
    var errorDescription: String? {
        switch self {
        case .unavailable: "เปิดกล้องไม่ได้ ลองเลือกรูปจากคลังภาพ"
        case .captureFailed: "ถ่ายภาพไม่สำเร็จ กรุณาลองอีกครั้ง"
        case .busy: "กล้องกำลังถ่ายภาพ"
        }
    }
}

/// AVCaptureSession is only configured/run on this dedicated serial queue.
final class CaptureEngine: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.lunav.camera", qos: .userInitiated)
    private let output = AVCapturePhotoOutput()
    private let intrinsicOutput = AVCaptureVideoDataOutput()
    private let intrinsicCollector = CameraIntrinsicCollector()
    private let obstacleOutput = AVCaptureDepthDataOutput()
    private let obstacleCollector = ObstacleDepthCollector()
    private var input: AVCaptureDeviceInput?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var delegates: [Int64: PhotoDelegate] = [:]
    private var depthMode: CameraDepthMode = .colorOnly

    func start() async throws -> CameraDepthMode {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CameraDepthMode, Error>) in
            queue.async { [self] in
                do {
                    if input == nil { try configure() }
                    refreshOutputSettings()
                    if !session.isRunning { session.startRunning() }
                    continuation.resume(returning: depthMode)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // This session captures video/depth only. The independent voice recorder
        // owns AVAudioSession while a press starts camera and microphone together.
        session.automaticallyConfiguresApplicationAudioSession = false
        session.sessionPreset = .photo
        if !session.outputs.contains(output) {
            guard session.canAddOutput(output) else { throw CameraError.unavailable }
            session.addOutput(output)
        }
        try setInput(position: .back)
        output.maxPhotoQualityPrioritization = .balanced
        output.isContentAwareDistortionCorrectionEnabled = false
    }

    private func setInput(position: AVCaptureDevice.Position) throws {
        obstacleCollector.enabled = false
        if session.outputs.contains(obstacleOutput) { session.removeOutput(obstacleOutput) }
        let previous = input
        if let previous { session.removeInput(previous) }
        input = nil
        let lidar = position == .back ? AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) : nil
        guard let wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            if let previous { session.addInput(previous); input = previous }
            throw CameraError.unavailable
        }
        func attach(_ device: AVCaptureDevice, useDepth: Bool) throws {
            let next = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(next) else { throw CameraError.unavailable }
            if useDepth { try configureLiDARFormat(device) }
            session.addInput(next)
            input = next
        }
        do {
            if let lidar {
                do { try attach(lidar, useDepth: true); depthMode = .lidar }
                catch { try attach(wide, useDepth: false); depthMode = .unavailable }
            } else { try attach(wide, useDepth: false); depthMode = .colorOnly }
            output.isDepthDataDeliveryEnabled = depthMode == .lidar && output.isDepthDataDeliverySupported
            if depthMode == .lidar && !output.isDepthDataDeliveryEnabled { depthMode = .unavailable }
            configureVideoIntrinsics(isLiDAR: input?.device.deviceType == .builtInLiDARDepthCamera)
            // Capture rotation follows the actual sensor, including a display
            // change on a folding phone. It must not assume a portrait sensor.
            if let device = input?.device {
                rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
            }
            if output.isCameraSensorOrientationCompensationSupported {
                output.isCameraSensorOrientationCompensationEnabled = false
            }
        } catch {
            if let previous { session.addInput(previous); input = previous }
            throw error
        }
    }

    private func configureVideoIntrinsics(isLiDAR: Bool) {
        intrinsicCollector.latest = nil
        if isLiDAR {
            // Sensor capture keeps its existing output configuration and uses
            // the calibration paired with AVDepthData instead of a video proxy.
            if session.outputs.contains(intrinsicOutput) { session.removeOutput(intrinsicOutput) }
            return
        }
        if !session.outputs.contains(intrinsicOutput), session.canAddOutput(intrinsicOutput) {
            intrinsicOutput.alwaysDiscardsLateVideoFrames = true
            intrinsicOutput.automaticallyConfiguresOutputBufferDimensions = false
            intrinsicOutput.deliversPreviewSizedOutputBuffers = true
            intrinsicOutput.setSampleBufferDelegate(intrinsicCollector, queue: queue)
            session.addOutput(intrinsicOutput)
        }
        guard let connection = intrinsicOutput.connection(with: .video) else { return }
        if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .off }
        if connection.isVideoRotationAngleSupported(0) { connection.videoRotationAngle = 0 }
        if connection.isCameraIntrinsicMatrixDeliverySupported { connection.isCameraIntrinsicMatrixDeliveryEnabled = true }
    }

    private func refreshOutputSettings() {
        guard let device = input?.device else { return }
        let isLiDAR = device.deviceType == .builtInLiDARDepthCamera
        output.isDepthDataDeliveryEnabled = isLiDAR && output.isDepthDataDeliverySupported
        if isLiDAR { depthMode = output.isDepthDataDeliveryEnabled ? .lidar : .unavailable }
        let video = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let aspect = Double(video.width) / Double(video.height)
        // Preserve the same field of view as the depth map while keeping detailed
        // text in the still photo. Preview resolution does not cap photo resolution.
        let sizes = device.activeFormat.supportedMaxPhotoDimensions.filter {
            max($0.width, $0.height) <= 4_608 && $0.height > 0
                && (!isLiDAR || abs(Double($0.width) / Double($0.height) / aspect - 1) < 0.01)
        }
        if let best = sizes.max(by: { Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height) }) {
            output.maxPhotoDimensions = best
        }
    }

    private func configureLiDARFormat(_ device: AVCaptureDevice) throws {
        let candidates = device.formats.filter { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dimensions.width >= 1_280 && dimensions.width <= 2_560
                && format.supportedDepthDataFormats.contains { depth in
                    let type = CMFormatDescriptionGetMediaSubType(depth.formatDescription)
                    return type == kCVPixelFormatType_DepthFloat16 || type == kCVPixelFormatType_DepthFloat32
                }
        }.sorted {
            let a = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            let b = CMVideoFormatDescriptionGetDimensions($1.formatDescription)
            return abs(a.width - 1_920) < abs(b.width - 1_920)
        }
        guard let format = candidates.first,
              let depthFormat = format.supportedDepthDataFormats.filter({
                  let type = CMFormatDescriptionGetMediaSubType($0.formatDescription)
                  return type == kCVPixelFormatType_DepthFloat16 || type == kCVPixelFormatType_DepthFloat32
              }).max(by: {
                  let a = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                  let b = CMVideoFormatDescriptionGetDimensions($1.formatDescription)
                  return a.width * a.height < b.width * b.height
              }) else { throw CameraError.unavailable }
        session.sessionPreset = .inputPriority
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.activeFormat = format
        device.activeDepthDataFormat = depthFormat
        device.videoZoomFactor = 1
        if device.isGeometricDistortionCorrectionSupported { device.isGeometricDistortionCorrectionEnabled = false }
    }

    /// The output shares the already configured rear LiDAR camera. It remains
    /// disconnected while paused and is removed completely when switched off.
    func setObstacleMonitoring(attach: Bool, enabled: Bool,
                              sample: @escaping @Sendable (Double?, TimeInterval) -> Void) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                obstacleCollector.enabled = false
                obstacleCollector.onSample = nil
                guard attach, input?.device.deviceType == .builtInLiDARDepthCamera else {
                    if session.outputs.contains(obstacleOutput) {
                        session.beginConfiguration()
                        session.removeOutput(obstacleOutput)
                        session.commitConfiguration()
                    }
                    continuation.resume(returning: false)
                    return
                }
                if !session.outputs.contains(obstacleOutput) {
                    session.beginConfiguration()
                    if session.canAddOutput(obstacleOutput) {
                        obstacleOutput.alwaysDiscardsLateDepthData = true
                        obstacleOutput.isFilteringEnabled = true
                        obstacleCollector.session = session
                        obstacleOutput.setDelegate(obstacleCollector, callbackQueue: queue)
                        session.addOutput(obstacleOutput)
                    }
                    session.commitConfiguration()
                    // Attaching an output must not alter the still-photo
                    // dimensions/depth-delivery policy established at startup.
                    refreshOutputSettings()
                }
                guard let connection = obstacleOutput.connection(with: .depthData) else {
                    continuation.resume(returning: false)
                    return
                }
                connection.isEnabled = enabled && session.isRunning
                obstacleCollector.onSample = sample
                obstacleCollector.lastSampleTime = -.infinity
                obstacleCollector.enabled = connection.isEnabled
                continuation.resume(returning: true)
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                obstacleCollector.enabled = false
                obstacleCollector.onSample = nil
                obstacleOutput.connection(with: .depthData)?.isEnabled = false
                if session.isRunning { session.stopRunning() }
                continuation.resume()
            }
        }
    }

    func flip() async throws -> CameraDepthMode {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CameraDepthMode, Error>) in
            queue.async { [self] in
                let wasRunning = session.isRunning
                if wasRunning { session.stopRunning() }
                session.beginConfiguration()
                do {
                    try setInput(position: input?.device.position == .back ? .front : .back)
                    session.commitConfiguration()
                    refreshOutputSettings()
                    if wasRunning { session.startRunning() }
                    continuation.resume(returning: depthMode)
                } catch {
                    session.commitConfiguration()
                    if wasRunning { session.startRunning() }
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func capture() async throws -> CapturedPhoto {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard session.isRunning else {
                    continuation.resume(throwing: CameraError.unavailable)
                    return
                }
                obstacleCollector.enabled = false
                obstacleOutput.connection(with: .depthData)?.isEnabled = false
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                settings.photoQualityPrioritization = .balanced
                settings.maxPhotoDimensions = output.maxPhotoDimensions
                settings.isDepthDataDeliveryEnabled = depthMode == .lidar && output.isDepthDataDeliveryEnabled
                // Native, photo-aligned filtering fills the LiDAR projector's sparse
                // near-range samples. The snapshot preserves this provenance so the
                // range reader can apply its filtered-surface corroboration rules.
                settings.isDepthDataFiltered = !CommandLine.arguments.contains("--lidar-unfiltered")
                settings.embedsDepthDataInPhoto = false
                settings.isAutoContentAwareDistortionCorrectionEnabled = false
                if let connection = output.connection(with: .video), let rotationCoordinator {
                    let angle = rotationCoordinator.videoRotationAngleForHorizonLevelCapture
                    if connection.isVideoRotationAngleSupported(angle) {
                        // Photo output records EXIF orientation. Leave the video
                        // intrinsic stream and LiDAR calibration in sensor space.
                        connection.videoRotationAngle = angle
                    }
                }
                let id = settings.uniqueID
                let delegate = PhotoDelegate(lidarRequested: depthMode != .colorOnly,
                                             captureDiagnostics: captureDiagnostics(),
                                             videoIntrinsics: intrinsicCollector.latest) { [weak self] result in
                    guard let self else { continuation.resume(throwing: CameraError.captureFailed); return }
                    self.queue.async { [self] in
                        guard delegates.removeValue(forKey: id) != nil else { return }
                        continuation.resume(with: result)
                    }
                }
                delegates[id] = delegate
                queue.asyncAfter(deadline: .now() + 15) { [self] in
                    guard delegates.removeValue(forKey: id) != nil else { return }
                    continuation.resume(throwing: CameraError.captureFailed)
                }
                output.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    private func captureDiagnostics() -> [String: String] {
        guard let device = input?.device else { return [:] }
        let format = device.activeFormat
        var result = [
            "deviceType": device.deviceType.rawValue,
            "cameraIdentifier": device.uniqueID,
            "videoFormat": String(describing: CMVideoFormatDescriptionGetDimensions(format.formatDescription)),
            "videoPixelType": String(CMFormatDescriptionGetMediaSubType(format.formatDescription)),
            "videoBinned": String(format.isVideoBinned),
            "videoFieldOfView": String(format.videoFieldOfView),
            "zoomFactor": String(Double(device.videoZoomFactor)),
            "focusMode": String(device.focusMode.rawValue),
            "adjustingFocus": String(device.isAdjustingFocus),
            "lensPosition": String(device.lensPosition),
            "minimumFocusMillimeters": String(device.minimumFocusDistance)
        ]
        if let depth = device.activeDepthDataFormat {
            result["activeDepthFormat"] = String(describing: CMVideoFormatDescriptionGetDimensions(depth.formatDescription))
            result["activeDepthPixelType"] = String(CMFormatDescriptionGetMediaSubType(depth.formatDescription))
        }
        return result
    }
}

/// Confined to CaptureEngine's serial queue. Frames are sampled in-place and
/// released before returning; the callback never captures an AVDepthData/map.
private final class ObstacleDepthCollector: NSObject, AVCaptureDepthDataOutputDelegate, @unchecked Sendable {
    weak var session: AVCaptureSession?
    var enabled = false
    var lastSampleTime: TimeInterval = -.infinity
    var onSample: (@Sendable (Double?, TimeInterval) -> Void)?

    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData,
                         timestamp: CMTime, connection: AVCaptureConnection) {
        guard enabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastSampleTime >= 0.2 else { return }
        lastSampleTime = now
        guard timestamp.isNumeric, let clock = session?.synchronizationClock else {
            onSample?(nil, now)
            return
        }
        let hostClock = CMClockGetHostTimeClock()
        let capturedHostTime = CMSyncConvertTime(timestamp, from: clock, to: hostClock)
        let hostNow = CMClockGetTime(hostClock)
        guard capturedHostTime.isNumeric, hostNow.isNumeric,
              let measurementTime = ObstacleWarningPolicy.measurementUptime(callbackUptime: now,
                  hostNow: CMTimeGetSeconds(hostNow), capturedHostTime: CMTimeGetSeconds(capturedHostTime)) else {
            onSample?(nil, now)
            return
        }
        let distance: Double? = autoreleasepool {
            guard depthData.depthDataAccuracy == .absolute, depthData.depthDataQuality == .high else { return nil }
            let map = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32).depthDataMap
            guard CVPixelBufferLockBaseAddress(map, .readOnly) == kCVReturnSuccess else { return nil }
            defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
            let stride = CVPixelBufferGetBytesPerRow(map) / MemoryLayout<Float>.stride
            let floats = base.assumingMemoryBound(to: Float.self)
            return ObstacleDepthSampler.estimate(width: CVPixelBufferGetWidth(map), height: CVPixelBufferGetHeight(map)) {
                floats[$1 * stride + $0]
            }
        }
        onSample?(distance, measurementTime)
    }
}

private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let completion: @Sendable (Result<CapturedPhoto, Error>) -> Void
    let lidarRequested: Bool
    let captureDiagnostics: [String: String]
    let videoIntrinsics: CameraIntrinsicCollector.Sample?
    private var result: Result<CapturedPhoto, Error> = .failure(CameraError.captureFailed)
    init(lidarRequested: Bool, captureDiagnostics: [String: String], videoIntrinsics: CameraIntrinsicCollector.Sample?,
         completion: @Sendable @escaping (Result<CapturedPhoto, Error>) -> Void) {
        self.lidarRequested = lidarRequested
        self.captureDiagnostics = captureDiagnostics
        self.videoIntrinsics = videoIntrinsics
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { result = .failure(error) }
        else if let data = photo.fileDataRepresentation() {
            let timestamp = CMTimeGetSeconds(photo.timestamp)
            let recent = videoIntrinsics.flatMap { sample in
                timestamp.isFinite && sample.timestamp.isFinite && abs(sample.timestamp - timestamp) <= 2 ? sample.intrinsics : nil
            }
            var capture = DepthPhotoCapture.extract(photo: photo, data: data, lidarRequested: lidarRequested,
                                                    videoIntrinsics: recent)
            capture.depthDiagnostics.merge(captureDiagnostics) { captured, _ in captured }
            capture.cameraIdentifier = captureDiagnostics["cameraIdentifier"]
            result = .success(capture)
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        completion(error.map { .failure($0) } ?? result)
    }
}

/// This delegate and `latest` are confined to the camera queue. It retains only
/// 3×3 calibration numbers, never a preview pixel buffer or camera frame.
private final class CameraIntrinsicCollector: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    struct Sample: Sendable {
        let intrinsics: PhotoCameraIntrinsics
        let timestamp: Double
    }
    var latest: Sample?

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let data = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
                                         attachmentModeOut: nil) as? Data,
              data.count == MemoryLayout<simd_float3x3>.size else { return }
        let dimensions = CMVideoFormatDescriptionGetDimensions(format)
        let matrix = data.withUnsafeBytes { $0.loadUnaligned(as: simd_float3x3.self) }
        let intrinsics = PhotoCameraIntrinsics(referenceWidth: Double(dimensions.width), referenceHeight: Double(dimensions.height),
                                               fx: Double(matrix.columns.0.x), fy: Double(matrix.columns.1.y),
                                               cx: Double(matrix.columns.2.x), cy: Double(matrix.columns.2.y),
                                               orientation: .up, provenance: .videoIntrinsicMatrix)
        guard intrinsics.isValid else { return }
        latest = .init(intrinsics: intrinsics, timestamp: CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)))
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.configure(session: session)
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) { uiView.configure(session: session) }
    static func dismantleUIView(_ uiView: PreviewView, coordinator: ()) { uiView.disconnect() }
}

final class PreviewView: UIView {
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var inputObservation: NSKeyValueObservation?
    private var rotationObservation: NSKeyValueObservation?
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    func configure(session: AVCaptureSession) {
        if previewLayer.session !== session {
            inputObservation = nil
            rotationObservation = nil
            rotationCoordinator = nil
            previewLayer.session = session
            previewLayer.videoGravity = .resizeAspectFill
            // Input configuration is performed on the capture queue. Resolve
            // the new preview coordinator on the main actor after it changes.
            inputObservation = session.observe(\.inputs, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.refreshRotationCoordinator() }
            }
        }
        refreshRotationCoordinator()
    }

    func disconnect() {
        inputObservation = nil
        rotationObservation = nil
        rotationCoordinator = nil
        previewLayer.session = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshRotationCoordinator()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshRotationCoordinator()
    }

    private func refreshRotationCoordinator() {
        guard window != nil,
              let device = previewLayer.session?.inputs.compactMap({ $0 as? AVCaptureDeviceInput })
                .first(where: { $0.device.hasMediaType(.video) })?.device else { return }
        if rotationCoordinator?.device !== device {
            rotationObservation = nil
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            rotationCoordinator = coordinator
            rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.applyPreviewRotation() }
            }
        }
        applyPreviewRotation()
    }

    private func applyPreviewRotation() {
        guard let rotationCoordinator else { return }
        let angle = rotationCoordinator.videoRotationAngleForHorizonLevelPreview
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }
}
