import AVFoundation
import Foundation
import Observation
import os

/// Touch-up seals the WAV immediately. Apple Dictation transcribes it locally;
/// cancellation/deadlines retain the file until its worker actually finishes.
@MainActor @Observable
final class LocalSpeechRecognizer {
    private static let log = Logger(subsystem: "com.koomean.lunav", category: "LocalSpeech")
    typealias Prepare = @Sendable (NativeSpeechLanguage, Bool) async throws -> Void
    typealias Decode = @Sendable (URL, @escaping @Sendable (LocalSpeechStage) -> Void) async throws -> String
    private(set) var transcript = ""
    private(set) var isRecording = false
    private(set) var isTranscribing = false
    private(set) var level: Float = 0
    private(set) var status = "ไทย / English · บนเครื่อง"
    private(set) var error: String?
    private(set) var shouldFinish = false {
        didSet { if shouldFinish && !oldValue { onRecordingLimit?() } }
    }
    @ObservationIgnored var onRecordingLimit: (@MainActor () -> Void)?

    static let modelName = "Apple Dictation · บนเครื่อง"
    static let modelDescription = "ใช้โมเดล Dictation ของ iOS · ไม่ส่งเสียงไปเซิร์ฟเวอร์ · เลือกภาษาไทยหรืออังกฤษ"
    private(set) var isPrepared = false
    private(set) var preparationError: String?
    var language: NativeSpeechLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "nativeSpeechLanguage")
            isPrepared = false
            preparationError = nil
        }
    }

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var capturedSpeech = false
    private var recordingTooLong = false
    private var monitor: Task<Void, Never>?
    private var progressMonitor: Task<Void, Never>?
    private var decodingTask: SpeechTask?
    private var preparationTask: SpeechTask?
    private var recoveryTask: Task<Void, Never>?
    private let automaticRecovery: Bool
    private var activation: SpeechTask?
    private var permissionTask: SpeechTask?
    private var deactivation: SpeechTask?
    private var deactivationWaited = false
    private var ownsAudioSession = false
    private var isStarting = false
    private var operationID = UUID()
    private let decode: Decode?
    private let prepareSpeech: Prepare
    private let shouldPrepare: Bool
    private let timeout: Duration
    private var decodingStage: LocalSpeechStage = .preparingAudio
    private var decodingStarted: ContinuousClock.Instant?
    private var interruptionObserver: NSObjectProtocol?
    private var speechWindow = LocalSpeechWindow()

    var hasPendingWork: Bool {
        decodingTask?.isRunning == true || preparationTask?.isRunning == true || (decode == nil && NativeSpeechDecoder.isWorking)
    }

    init(timeout: Duration = .seconds(45), decode: Decode? = nil, prepare: Prepare? = nil) {
        self.timeout = timeout
        self.automaticRecovery = decode == nil && prepare == nil
        self.decode = decode
        self.shouldPrepare = decode == nil || prepare != nil
        self.prepareSpeech = prepare ?? { language, allowDownload in
            try await NativeSpeechDecoder.shared.prepare(language: language, allowDownload: allowDownload)
        }
        self.language = NativeSpeechLanguage(rawValue: UserDefaults.standard.string(forKey: "nativeSpeechLanguage") ?? "") ?? .thai
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                self.cancel()
                self.shouldFinish = true
                self.error = "ไมโครโฟนถูกขัดจังหวะ กดค้างเพื่อถามใหม่"
                self.status = "การรับเสียงหยุดแล้ว"
            }
        }
    }

    /// Apple owns the shared speech assets. No Whisper model is loaded here.
    func prepare(timeout: Duration = .seconds(30), allowDownload: Bool = true,
                 progress: (@Sendable (LocalSpeechStage) -> Void)? = nil) async throws {
        guard shouldPrepare else { return }
        guard !isTranscribing, !hasPendingWork else { throw LocalSpeechError.busy }
        let language = language
        let prepareSpeech = prepareSpeech
        let task = SpeechTask(operation: {
            try await prepareSpeech(language, allowDownload)
            return "prepared"
        }, onCompletion: { [weak self] in
            Task { @MainActor [weak self] in self?.settleFinishedWorkers() }
        })
        preparationTask = task
        defer { if !task.isRunning { preparationTask = nil } }
        do {
            _ = try await task.value(timeout: timeout)
            try Task.checkCancellation()
            guard self.language == language else { throw CancellationError() }
            isPrepared = true
            preparationError = nil
            status = "พร้อมรับเสียง · \(language.label) · บนเครื่อง"
        } catch {
            isPrepared = false
            if error is CancellationError { throw error }
            preparationError = error is SpeechTaskError ? "เตรียมเสียงไม่ทันเวลา ลองเตรียมอีกครั้งในตั้งค่า" : error.localizedDescription
            status = preparationError ?? "ระบบเสียงยังไม่พร้อม"
            throw error
        }
    }

    /// An absent/unsupported Apple language must not trap the camera behind a
    /// launch screen or repeat VLM loading. Voice can be retried in Settings.
    func prepareForStartup() async throws {
        do { try await prepare() }
        catch is CancellationError { throw CancellationError() }
        catch {
            isPrepared = false
            if preparationError == nil { preparationError = error.localizedDescription }
            scheduleRecovery(after: error)
        }
    }

    private func scheduleRecovery(after error: Error) {
        guard automaticRecovery, recoveryTask == nil else { return }
        if let native = error as? NativeSpeechDecoderError, case .unsupportedLanguage = native { return }
        recoveryTask = Task { [weak self] in
            var attempt = 1
            defer { self?.recoveryTask = nil }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(ModelPreparation.retrySeconds(after: attempt))) }
                catch { return }
                guard let self, !self.isPrepared else { return }
                guard !self.hasPendingWork else { continue }
                do { try await self.prepare(); return }
                catch is CancellationError { return }
                catch {
                    if let native = error as? NativeSpeechDecoderError, case .unsupportedLanguage = native { return }
                    self.status = "ภาษาเสียงยังไม่พร้อม · จะลองใหม่อัตโนมัติ"
                }
                attempt += 1
            }
        }
    }

    func releasePreparedModel() async {
        recoveryTask?.cancel()
        recoveryTask = nil
        preparationTask?.cancel()
        await NativeSpeechDecoder.shared.cancel()
        isPrepared = false
        if preparationTask?.isRunning != true { preparationTask = nil }
    }

    func start() async throws {
        guard !isStarting, !isTranscribing, !hasPendingWork,
              activation?.isRunning != true, permissionTask?.isRunning != true else {
            throw LocalSpeechError.busy
        }
        isStarting = true
        defer { isStarting = false }
        cancel()
        transcript = ""
        error = nil
        shouldFinish = false
        capturedSpeech = false
        recordingTooLong = false
        if decode == nil, !isPrepared {
            throw LocalSpeechError.nativeNotReady(preparationError ?? "เตรียมภาษาเสียงในตั้งค่าก่อนใช้งานครั้งแรก")
        }
        status = "กำลังเปิดไมโครโฟน…"
        let id = operationID
        let permissionTask = SpeechTask {
            await AVAudioApplication.requestRecordPermission() ? "allowed" : "denied"
        }
        self.permissionTask = permissionTask
        let permission: Bool
        do { permission = try await permissionTask.value(timeout: .seconds(30)) == "allowed" }
        catch SpeechTaskError.timedOut { throw LocalSpeechError.microphoneTimedOut }
        try Task.checkCancellation()
        guard operationID == id else { throw CancellationError() }
        guard permission else { throw LocalSpeechError.permissionDenied }

        let session = AVAudioSession.sharedInstance()
        var requestedActivation = false
        do {
            if let deactivation, deactivation.isRunning {
                guard !deactivationWaited else { throw LocalSpeechError.busy }
                deactivationWaited = true
                _ = try await deactivation.value(timeout: .seconds(5))
            }
            deactivation = nil
            deactivationWaited = false
            try Task.checkCancellation()
            guard operationID == id else { throw CancellationError() }
            try session.setCategory(.record, mode: .measurement)
            requestedActivation = true
            let activation = SpeechTask {
                let activated = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                    AVAudioSession.sharedInstance().activate(options: []) { activated, error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume(returning: activated) }
                    }
                }
                guard activated else { throw LocalSpeechError.microphoneUnavailable }
                if Task.isCancelled {
                    // Activation may complete after its waiter was cancelled.
                    // Keep the job pending until that late session is closed.
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        AVAudioSession.sharedInstance().deactivate(options: .notifyOthersOnDeactivation) { _, _ in
                            continuation.resume()
                        }
                    }
                    throw CancellationError()
                }
                return "activated"
            }
            self.activation = activation
            _ = try await activation.value(timeout: .seconds(5))
            ownsAudioSession = true
            try Task.checkCancellation()
            guard operationID == id else { throw CancellationError() }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("lunav-question-\(UUID().uuidString).wav")
            let value = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ])
            value.isMeteringEnabled = true
            recordingURL = url
            guard value.prepareToRecord(), value.record() else {
                throw LocalSpeechError.microphoneUnavailable
            }
            recorder = value
            speechWindow = LocalSpeechWindow()
            isRecording = true
            status = "พูดได้เลย · ปล่อยปุ่มเพื่อส่ง"
            monitor = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled, let self, self.operationID == id,
                          let recorder = self.recorder else { return }
                    recorder.updateMeters()
                    let power = recorder.averagePower(forChannel: 0)
                    self.level = max(0, min(1, (power + 55) / 45))
                    self.speechWindow.observe(power: power, elapsed: recorder.currentTime)
                    if self.speechWindow.shouldFinish {
                        self.recordingTooLong = true
                        self.stopInput()
                        self.status = "คำถามเกิน 2 นาที · ปล่อยปุ่มแล้วลองพูดให้สั้นลง"
                        self.shouldFinish = true
                        return
                    }
                    if !recorder.isRecording {
                        self.stopInput()
                        self.shouldFinish = true
                        return
                    }
                }
            }
        } catch {
            activation?.cancel()
            // The callback can succeed just before cancellation wins delivery,
            // before this waiter adopts it. Close a requested session as well.
            if requestedActivation { ownsAudioSession = true }
            stopRecording(deleteFile: true)
            let failure: Error = error as? SpeechTaskError == .timedOut ? LocalSpeechError.microphoneTimedOut : error
            self.error = failure.localizedDescription
            status = "เปิดไมโครโฟนไม่ได้"
            throw failure
        }
    }

    /// Called synchronously at physical touch-up, even while photo processing is
    /// still running. Sealing and decoding are deliberately separate operations.
    func stopInput() {
        if let recorder {
            recorder.updateMeters()
            speechWindow.observe(power: recorder.averagePower(forChannel: 0), elapsed: recorder.currentTime)
            capturedSpeech = speechWindow.hasSpeech
        }
        stopRecording(deleteFile: false)
    }

    func finish() async throws -> String {
        stopInput()
        guard let url = recordingURL else { throw LocalSpeechError.noRecording }
        recordingURL = nil
        if recordingTooLong {
            try? FileManager.default.removeItem(at: url)
            throw LocalSpeechDecoderError.recordingTooLong
        }
        guard capturedSpeech else {
            try? FileManager.default.removeItem(at: url)
            status = "ยังไม่ได้ยินคำถาม กดค้างแล้วพูดใหม่"
            throw LocalSpeechError.noSpeech
        }
        return try await transcribeRecordedAudio(at: url)
    }

    /// Own the sealed file through actual worker completion, including if Core ML
    /// ignores cancellation. Also provides a deterministic boundary for testing.
    func transcribeRecordedAudio(at url: URL) async throws -> String {
        var transferredFile = false
        defer { if !transferredFile { try? FileManager.default.removeItem(at: url) } }
        try Task.checkCancellation()
        guard !isTranscribing, !hasPendingWork else { throw LocalSpeechError.busy }
        let id = operationID
        Self.log.info("ASR started id=\(id.uuidString, privacy: .public)")
        isTranscribing = true
        decodingStage = .preparingAudio
        decodingStarted = .now
        refreshProgress()
        let decode = self.decode
        let language = self.language
        let progress: @Sendable (LocalSpeechStage) -> Void = { [weak self] stage in
                Task { @MainActor [weak self] in
                    guard let self, self.operationID == id, self.isTranscribing else { return }
                    self.decodingStage = stage
                    if NativeSpeechDecoder.detailedDiagnosticsRequested {
                        Self.log.info("ASR id=\(id.uuidString, privacy: .public) stage=\(stage.rawValue, privacy: .public)")
                    }
                    self.refreshProgress()
                }
        }
        let task = SpeechTask(operation: {
            if let decode { return try await decode(url, progress) }
            return try await NativeSpeechDecoder.shared.transcribe(audioURL: url, language: language) { stage in
                progress(stage == .transcribing ? .transcribing : .preparingAudio)
            }
        }, onFinish: { try? FileManager.default.removeItem(at: url) }, onCompletion: { [weak self] in
            Task { @MainActor [weak self] in self?.settleFinishedWorkers() }
        })
        transferredFile = true
        decodingTask = task
        progressMonitor = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, self.operationID == id, self.isTranscribing else { return }
                self.refreshProgress()
            }
        }
        do {
            let result = try await task.value(timeout: timeout)
            try Task.checkCancellation()
            guard operationID == id else { throw CancellationError() }
            transcript = result
            status = "ถอดเสียงแล้ว · บนเครื่อง"
            isTranscribing = false
            progressMonitor?.cancel()
            progressMonitor = nil
            decodingTask = nil
            Self.log.info("ASR completed id=\(id.uuidString, privacy: .public)")
            return result
        } catch {
            Self.log.error("ASR stopped id=\(id.uuidString, privacy: .public) stage=\(self.decodingStage.rawValue, privacy: .public) workerPending=\(task.isRunning) error=\(String(describing: error), privacy: .public)")
            if operationID == id {
                isTranscribing = false
                progressMonitor?.cancel()
                progressMonitor = nil
                if !task.isRunning { decodingTask = nil }
                if !(error is CancellationError) {
                    self.error = error is SpeechTaskError ? LocalSpeechDecoderError.timedOut.localizedDescription : error.localizedDescription
                    status = "ถอดเสียงไม่สำเร็จ"
                }
            }
            if error as? SpeechTaskError == .timedOut { throw LocalSpeechDecoderError.timedOut }
            throw error
        }
    }

    /// Completion publishes an Observation change even when the UI stopped
    /// waiting earlier. Retry controls can then enable without an unrelated tap.
    private func settleFinishedWorkers() {
        if preparationTask?.isRunning == false { preparationTask = nil }
        if decodingTask?.isRunning == false { decodingTask = nil }
    }

    private func refreshProgress() {
        let elapsed = decodingStarted.map { max(0, $0.duration(to: .now).components.seconds) } ?? 0
        status = decodingStage.message + (elapsed > 0 ? " · \(elapsed) วินาที" : "")
    }

    func cancel() {
        operationID = UUID()
        permissionTask?.cancel()
        preparationTask?.cancel()
        activation?.cancel()
        decodingTask?.cancel()
        progressMonitor?.cancel()
        progressMonitor = nil
        isTranscribing = false
        stopRecording(deleteFile: true)
        shouldFinish = false
        status = "ไทย / English · บนเครื่อง"
    }

    /// Keep an idle prepared model reusable. Cancellation must not join an
    /// unresponsive Core ML call; its process-wide lease blocks another model.
    func release() async {
        cancel()
        if decodingTask?.isRunning != true { decodingTask = nil }
        isTranscribing = false
    }

    private func stopRecording(deleteFile: Bool) {
        monitor?.cancel()
        monitor = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        level = 0
        if ownsAudioSession {
            ownsAudioSession = false
            deactivationWaited = false
            deactivation = SpeechTask {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    AVAudioSession.sharedInstance().deactivate(options: .notifyOthersOnDeactivation) { _, _ in
                        continuation.resume()
                    }
                }
                return "deactivated"
            }
        }
        if deleteFile, let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }
    }
}

/// Bounded utterances and a real speech-energy gate prevent silence hallucinations.
struct LocalSpeechWindow {
    static let maximumDuration: TimeInterval = 120
    private(set) var hasSpeech = false
    private(set) var shouldFinish = false
    private var voicedFrames = 0

    mutating func observe(power: Float, elapsed: TimeInterval) {
        if power.isFinite, power > -43 {
            voicedFrames += 1
            if voicedFrames >= 3 { hasSpeech = true }
        } else {
            voicedFrames = 0
        }
        // Silence is allowed while the user is holding the button. Only a hard
        // size limit seals the file; it never submits a partial question.
        shouldFinish = elapsed >= Self.maximumDuration
    }
}

enum LocalSpeechError: LocalizedError {
    case missingModel, busy, permissionDenied, microphoneUnavailable, microphoneTimedOut, noRecording, noSpeech, timedOut
    case nativeNotReady(String)
    var errorDescription: String? {
        switch self {
        case .missingModel: "โมเดลเสียงยังไม่พร้อม กรุณาเปิดตั้งค่าและเตรียมภาษาเสียง"
        case .nativeNotReady(let message): message
        case .busy: "ระบบเสียงกำลังคืนทรัพยากร กรุณารอสักครู่แล้วลองใหม่"
        case .permissionDenied: "อนุญาตไมโครโฟนให้ LunaV ใน Settings ของ iPhone แล้วกดค้างเพื่อถามใหม่"
        case .microphoneUnavailable: "เปิดไมโครโฟนไม่ได้ ตรวจสอบว่าไม่มีแอพอื่นใช้งานอยู่"
        case .microphoneTimedOut: "เปิดไมโครโฟนนานเกินไป ปล่อยปุ่มแล้วลองกดค้างใหม่"
        case .noRecording: "ยังไม่มีเสียงคำถาม กดปุ่มตรงกลางค้างไว้แล้วพูด"
        case .noSpeech: "ยังไม่ได้ยินคำถาม กดค้างแล้วพูดใกล้ไมโครโฟนอีกครั้ง"
        case .timedOut: "ถอดเสียงนานเกินไป ลองถามเป็นประโยคสั้นลง"
        }
    }
}
