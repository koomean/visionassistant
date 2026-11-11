import AVFoundation
import Foundation
import Observation
import os

/// Camera readiness requires warmed vision/depth. Native voice readiness is
/// separate so a missing Apple speech language cannot lock the camera UI.
@MainActor @Observable
final class ModelPreparation {
    private static let log = Logger(subsystem: "com.koomean.lunav", category: "ModelPreparation")
    typealias RetryWait = @MainActor (Duration) async throws -> Void

    struct Operations {
        var vision: @MainActor () async throws -> Void
        var depth: @MainActor () async throws -> Void
        var speech: @MainActor () async throws -> Void
        var pending: @MainActor () async -> Bool
        var release: @MainActor () async -> Void
    }

    private(set) var isReady = false
    private(set) var isPreparing = false
    private(set) var status = "กำลังเตรียมโมเดลบนเครื่อง…"
    private(set) var error: String?
    private(set) var completedStages = 0
    private(set) var attemptCount = 0
    private(set) var failedStage: String?
    private(set) var nextRetrySeconds: Int?
    let needsMonocularDepth: Bool
    let speech: LocalSpeechRecognizer
    private let operations: Operations
    private let simulatorPreview: Bool
    private let automaticRetry: Bool
    private let retryWait: RetryWait
    private var task: Task<Void, Never>?
    private var stageJob: SpeechTask?
    private var suspensionTask: Task<Void, Never>?
    private var revision = UUID()
    private let stageTimeout: Duration
    private var currentStage: String?
    private var recoveryDelay: Duration?
    private(set) var usesDemandLoading = false
    private var validationFailurePending: Bool
    private var validationFailureInjected = false
    private var underlyingErrorDomain: String?
    private var underlyingErrorCode: Int?
    private var underlyingErrorDescription: String?
    private var lastFailure: FailureDiagnostic?
    private var visionWarmupSucceeded = false
    private var depthWarmupSucceeded = false

    static var requiresMonocularDepth: Bool {
        AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) == nil
    }

    init(chat: ChatViewModel, speech: LocalSpeechRecognizer = LocalSpeechRecognizer()) {
        self.speech = speech
        stageTimeout = .seconds(180)
        simulatorPreview = true
        automaticRetry = true
        retryWait = { try await Task.sleep(for: $0) }
        validationFailurePending = Self.startupRetryValidationRequested(arguments: ProcessInfo.processInfo.arguments)
        needsMonocularDepth = Self.requiresMonocularDepth
        operations = Operations(
            vision: {
                try await chat.enterModelPhase(.vision)
                try await chat.prepareVisualModel()
            },
            depth: {
                try await chat.enterModelPhase(.depth)
                try await MonocularDepthRuntime.shared.prepare()
                if RuntimePolicy.prefersEphemeralModels { await MonocularDepthRuntime.shared.release() }
            },
            speech: {
                try await speech.prepareForStartup()
            },
            pending: {
                let visual = await chat.visualHasPendingWork
                let depth = await MonocularDepthRuntime.shared.hasPendingWork
                return visual || depth || speech.hasPendingWork
            },
            release: {
                await chat.suspend()
                await speech.releasePreparedModel()
                await MonocularDepthRuntime.shared.release()
            })
    }

    init(needsMonocularDepth: Bool, operations: Operations, stageTimeout: Duration = .seconds(180),
         automaticRetry: Bool = false, validateStartupRetry: Bool = false,
         retryWait: @escaping RetryWait = { try await Task.sleep(for: $0) }) {
        self.needsMonocularDepth = needsMonocularDepth
        self.operations = operations
        self.stageTimeout = stageTimeout
        self.automaticRetry = automaticRetry
        self.retryWait = retryWait
        validationFailurePending = validateStartupRetry
        simulatorPreview = false
        speech = LocalSpeechRecognizer()
    }

    var stageCount: Int { usesDemandLoading ? 1 : (needsMonocularDepth ? 3 : 2) }
    var hasPendingStageWork: Bool { stageJob?.isRunning == true }

    func prepare() async {
        if let suspensionTask { await suspensionTask.value }
        guard !Task.isCancelled else { return }
        if let task { await task.value; return }
        guard !isReady else { return }
        #if targetEnvironment(simulator)
        // MLX inference is unsupported in Simulator. Production models remain
        // exercised by native smoke tools; UI tests cover the real interaction.
        if simulatorPreview {
            status = "Simulator · ทดสอบ UI ได้ โมเดล AI ต้องใช้เครื่องจริง"
            isReady = true
            return
        }
        #endif
        let id = UUID()
        revision = id
        let next = Task { @MainActor in
            self.isPreparing = true
            self.attemptCount = 0
            self.completedStages = 0
            defer {
                if self.revision == id {
                    self.isPreparing = false
                    self.task = nil
                    self.nextRetrySeconds = nil
                    // The wait may finish before an uninterruptible Core ML call.
                    // Keep its handle until the worker really exits.
                    if self.stageJob?.isRunning != true { self.stageJob = nil }
                    self.record("stopped")
                }
            }
            var delay = self.recoveryDelay
            self.recoveryDelay = nil
            while !Task.isCancelled, self.revision == id {
                do {
                    if let delay {
                        self.nextRetrySeconds = Int(delay.components.seconds)
                        self.status = "เตรียม\(self.failedStage ?? "โมเดล")ไม่สำเร็จ · จะลองครั้งที่ \(self.attemptCount + 1) ใน \(self.nextRetrySeconds ?? 0) วินาที"
                        self.record("backoff")
                        try await self.retryWait(delay)
                        self.nextRetrySeconds = nil
                    }
                    try await self.waitForPreviousWorker()
                    try Task.checkCancellation()
                    self.attemptCount += 1
                    self.completedStages = 0
                    self.currentStage = nil
                    self.failedStage = nil
                    self.error = nil
                    self.underlyingErrorDomain = nil
                    self.underlyingErrorCode = nil
                    self.underlyingErrorDescription = nil
                    self.record("attempt")
                    // Warm only the selected local iOS dictation language.
                    // Its failure remains visible without restarting vision.
                    if !self.usesDemandLoading {
                        if !self.visionWarmupSucceeded {
                            try await self.runStage("AI ภาพ", validateVision: true, operation: self.operations.vision)
                            self.visionWarmupSucceeded = true
                        } else { self.completedStages += 1 }
                        if self.needsMonocularDepth {
                            if !self.depthWarmupSucceeded {
                                try await self.runStage("Depth Anything 3", operation: self.operations.depth)
                                self.depthWarmupSucceeded = true
                            } else { self.completedStages += 1 }
                        }
                    }
                    try await self.runStage("เสียง Dictation ของ iOS", operation: self.operations.speech)
                    try Task.checkCancellation()
                    guard self.revision == id else { return }
                    self.status = "พร้อมใช้งาน · ประมวลผลบนเครื่อง"
                    self.isReady = true
                    self.currentStage = nil
                    self.record("ready")
                    return
                } catch {
                    guard self.revision == id else { return }
                    self.isReady = false
                    let cancelled = error is CancellationError || Task.isCancelled
                    self.error = cancelled ? nil : Self.failureMessage(for: error, stage: self.currentStage)
                    let underlying = error as NSError
                    self.underlyingErrorDomain = cancelled ? nil : underlying.domain
                    self.underlyingErrorCode = cancelled ? nil : underlying.code
                    self.underlyingErrorDescription = cancelled ? nil : underlying.localizedDescription
                    if !cancelled {
                        self.lastFailure = FailureDiagnostic(attempt: self.attemptCount, stage: self.currentStage,
                                                             domain: underlying.domain, code: underlying.code,
                                                             description: underlying.localizedDescription)
                    }
                    self.failedStage = self.currentStage
                    self.status = cancelled ? "ยกเลิกการเตรียมโมเดลแล้ว" : "ยังเตรียม\(self.failedStage ?? "โมเดล")ไม่สำเร็จ"
                    self.record(cancelled ? "cancelled" : "failure")
                    await self.operations.release()
                    guard !cancelled, self.automaticRetry else { return }
                    delay = .seconds(Self.retrySeconds(after: self.attemptCount))
                }
            }
        }
        task = next
        await withTaskCancellationHandler { await next.value } onCancel: { next.cancel() }
    }

    private func runStage(_ title: String, validateVision: Bool = false,
                          operation: @escaping @MainActor () async throws -> Void) async throws {
        try Task.checkCancellation()
        currentStage = title
        status = "กำลังเตรียม\(title)… · ครั้งที่ \(attemptCount)"
        record("stage-start")
        // Explicit launch-only fault injection exercises the recovery path on a
        // real phone. The next successful attempt must still run every model.
        if validateVision, validationFailurePending {
            validationFailurePending = false
            validationFailureInjected = true
            throw ModelRuntimeError.busy
        }
        let work = SpeechTask { try await operation(); return "prepared" }
        stageJob = work
        _ = try await work.value(timeout: stageTimeout)
        try Task.checkCancellation()
        completedStages += 1
        stageJob = nil
        record("stage-ready")
    }

    private func waitForPreviousWorker() async throws {
        while true {
            try Task.checkCancellation()
            if stageJob?.isRunning != true { stageJob = nil }
            let runtimePending = await operations.pending()
            let pending = stageJob?.isRunning == true || runtimePending
            guard pending else { return }
            guard automaticRetry else { throw LocalSpeechError.busy }
            status = "รอโมเดลรอบก่อนคืนทรัพยากร แล้วจะลองใหม่อัตโนมัติ"
            record("waiting-worker")
            try await retryWait(.seconds(1))
        }
    }

    nonisolated static func retrySeconds(after attempt: Int) -> Int {
        let exponent = min(5, max(1, attempt) - 1)
        return min(30, 1 << exponent)
    }

    nonisolated static func startupRetryValidationRequested(arguments: [String]) -> Bool {
        arguments.contains("--validate-startup-retry")
    }

    nonisolated static func failureMessage(for error: Error, stage: String?) -> String {
        let timedOut: Bool
        if let speechTaskError = error as? SpeechTaskError {
            timedOut = speechTaskError == .timedOut
        } else if let decoderError = error as? LocalSpeechDecoderError {
            if case .timedOut = decoderError { timedOut = true } else { timedOut = false }
        } else { timedOut = false }
        if timedOut {
            return "การเตรียม\(stage ?? "โมเดล")ใช้เวลานานเกินกำหนด ระบบจะรอให้งานรอบก่อนจบก่อนเริ่มใหม่"
        }
        return error.localizedDescription
    }

    func cancelPreparation() {
        isReady = false
        task?.cancel()
        stageJob?.cancel()
    }

    func suspend() async {
        if let suspensionTask { await suspensionTask.value; return }
        cancelPreparation()
        let previous = task
        let next = Task { @MainActor in
            await previous?.value
            await self.operations.release()
            self.isReady = false
            self.isPreparing = false
            self.suspensionTask = nil
        }
        suspensionTask = next
        await next.value
    }

    func memoryWarning() async {
        await suspend()
        guard !isReady, !isPreparing else { return }
        usesDemandLoading = true
        error = "คืนหน่วยความจำแล้ว กำลังเตรียมการรับเสียงใหม่ โมเดลภาพจะโหลดเฉพาะตอนถาม"
        status = "โหมดประหยัดหน่วยความจำ · เตรียมพร้อมถามใหม่"
        recoveryDelay = .seconds(1)
        record("memory-warning")
    }

    /// Small local diagnostics only: no photo, microphone, or user text is saved.
    private func record(_ event: String) {
        guard simulatorPreview else { return }
        let detailed = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--validate-") }
        guard detailed || ["ready", "failure", "cancelled", "memory-warning"].contains(event) else { return }
        let snapshot = Diagnostic(event: event, status: status, attempt: attemptCount,
                                  stage: currentStage, failedStage: failedStage, error: error,
                                  errorDomain: underlyingErrorDomain, errorCode: underlyingErrorCode,
                                  errorDescription: underlyingErrorDescription,
                                  lastFailure: lastFailure,
                                  completedStages: completedStages, isReady: isReady,
                                  pendingStageWork: hasPendingStageWork,
                                  needsMonocularDepth: needsMonocularDepth,
                                  speechPrepared: speech.isPrepared,
                                  speechError: speech.preparationError,
                                  nativeSpeechWorkerPending: NativeSpeechDecoder.isWorking,
                                  validationFailureInjected: validationFailureInjected,
                                  availableBytes: RuntimePolicy.processHeadroom,
                                  physicalBytes: ProcessInfo.processInfo.physicalMemory,
                                  timestamp: Date())
        Self.log.info("\(event, privacy: .public) attempt=\(self.attemptCount) stage=\(self.currentStage ?? "none", privacy: .public) depth=\(self.needsMonocularDepth) headroom=\(snapshot.availableBytes) error=\(self.error ?? "none", privacy: .public)")
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: URL.documentsDirectory.appending(path: "ModelPreparationCheck.json"), options: .atomic)
        } catch {
            Self.log.error("Could not save preparation diagnostics: \(error.localizedDescription, privacy: .public)")
        }
    }

    private struct Diagnostic: Codable {
        let event: String
        let status: String
        let attempt: Int
        let stage: String?
        let failedStage: String?
        let error: String?
        let errorDomain: String?
        let errorCode: Int?
        let errorDescription: String?
        let lastFailure: FailureDiagnostic?
        let completedStages: Int
        let isReady: Bool
        let pendingStageWork: Bool
        let needsMonocularDepth: Bool
        let speechPrepared: Bool
        let speechError: String?
        let nativeSpeechWorkerPending: Bool
        let validationFailureInjected: Bool
        let availableBytes: Int
        let physicalBytes: UInt64
        let timestamp: Date
    }

    private struct FailureDiagnostic: Codable {
        let attempt: Int
        let stage: String?
        let domain: String
        let code: Int
        let description: String
    }
}

enum LocalModelPhase { case vision, depth, speech }
