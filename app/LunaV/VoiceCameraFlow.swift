import Foundation
import Observation
import UIKit

/// Records questions about the current image or starts photo/depth capture
/// alongside the microphone. Touch-up seals the audio before decoding.
@MainActor @Observable
final class VoiceCameraFlow {
    enum Phase: Equatable { case idle, capturing, listening, transcribing, answering }
    static let minimumVoiceHoldDuration: Duration = .milliseconds(250)

    @MainActor struct Operations {
        var capture: () async throws -> Void
        var startListening: () async throws -> Void
        var finishListening: () async throws -> String
        var stopListening: () -> Void = {}
        var cancelListening: () -> Void
        var releaseSpeech: () async -> Void
        var submitQuestion: (String) async throws -> Void
        var liveTranscript: () -> String = { "" }
        var inputLevel: () -> Float = { 0 }
        var shouldFinish: () -> Bool = { false }
        var speechStatus: () -> String = { "กำลังถอดเสียงบนเครื่อง…" }
        var cancelQuestion: () -> Void = {}
        var stopAnswerSpeech: () -> Void = {}
        var setRecordingLimitHandler: (@escaping @MainActor () -> Void) -> Void = { _ in }
        var requiresFreshPhoto: (String) -> Bool = { _ in false }
    }

    private(set) var phase: Phase = .idle
    private(set) var status = "กดค้างเพื่อถาม · แตะเพื่อถ่าย"
    private(set) var error: String?
    private var recognizedQuestion = ""
    private var isCancelling = false
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []
    private var runID = UUID()
    private var operation: Task<Void, Never>?
    private var operationRevision = 0
    private var photoOperation: Task<Void, Error>?
    private var reusesCurrentPhoto = false
    private var microphoneReady = false
    private var releaseDecision: Bool?
    private var hasStartedFinish = false
    private var isDecodingSpeech = false
    private let operations: Operations

    var isBusy: Bool { phase != .idle || isCancelling }
    var isListening: Bool { phase == .listening }
    var displayStatus: String { isDecodingSpeech || isListening ? operations.speechStatus() : status }
    var level: Float { isListening ? min(1, max(0, operations.inputLevel())) : 0 }
    var transcript: String {
        if phase == .listening || phase == .transcribing {
            let live = operations.liveTranscript()
            if !live.isEmpty { return live }
        }
        return recognizedQuestion
    }

    init(operations: Operations) {
        self.operations = operations
        operations.setRecordingLimitHandler { [weak self] in self?.recordingDidReachLimit() }
    }

    convenience init(camera: CameraController, chat: ChatViewModel,
                     speech: LocalSpeechRecognizer = LocalSpeechRecognizer()) {
        self.init(operations: Operations(
            capture: {
                await chat.prepareForCapture()
                try Task.checkCancellation()
                if !camera.isReady { await camera.start() }
                try Task.checkCancellation()
                guard camera.isReady else { throw VoiceCameraError.cameraUnavailable }
                let capture = try await camera.capture()
                try Task.checkCancellation()
                await camera.stop()
                try Task.checkCancellation()
                await chat.setCapturedPhoto(capture, openConversation: false)
                try Task.checkCancellation()
                guard chat.photoURL != nil, chat.error == nil else {
                    throw VoiceCameraError.photoPreparation
                }
                chat.action = .question
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            },
            startListening: { try await speech.start() },
            finishListening: { try await speech.finish() },
            stopListening: { speech.stopInput() },
            cancelListening: { speech.cancel() },
            releaseSpeech: { await speech.release() },
            submitQuestion: { question in
                try await chat.enterModelPhase(.vision)
                try Task.checkCancellation()
                chat.action = .question
                chat.send(question)
                await chat.waitForPendingResponse()
                try Task.checkCancellation()
                if let error = chat.error { throw VoiceCameraError.inference(error) }
            },
            liveTranscript: { speech.transcript },
            inputLevel: { speech.level },
            shouldFinish: { speech.shouldFinish },
            speechStatus: { speech.status },
            cancelQuestion: { chat.stop() },
            stopAnswerSpeech: { chat.answerSpeech?.stop() },
            setRecordingLimitHandler: { speech.onRecordingLimit = $0 },
            requiresFreshPhoto: { NearbyObjectRequest.parse($0) != nil }
        ))
    }

    func captureOnly() { begin(listenAfterCapture: false) }
    func beginVoiceQuestion(reusingCurrentPhoto: Bool = false) {
        begin(listenAfterCapture: true, reusingCurrentPhoto: reusingCurrentPhoto)
    }

    private func begin(listenAfterCapture: Bool, reusingCurrentPhoto: Bool = false) {
        guard !isBusy else { return }
        operations.stopAnswerSpeech()
        let pressDecisionDeadline = ContinuousClock.now + Self.minimumVoiceHoldDuration
        let id = UUID()
        runID = id
        error = nil
        recognizedQuestion = ""
        microphoneReady = false
        releaseDecision = nil
        hasStartedFinish = false
        isDecodingSpeech = false
        reusesCurrentPhoto = reusingCurrentPhoto
        phase = .capturing
        if reusingCurrentPhoto { status = "กำลังเปิดไมโครโฟน…" }
        else { status = listenAfterCapture ? "กำลังเปิดไมโครโฟนและถ่ายภาพ…" : "กำลังถ่ายภาพและเตรียมระยะ…" }
        let photo: Task<Void, Error>? = reusingCurrentPhoto ? nil : Task {
            try checkRun(id)
            try await operations.capture()
            try checkRun(id)
        }
        photoOperation = photo
        operationRevision += 1
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                try checkRun(id)
                if listenAfterCapture {
                    if reusingCurrentPhoto && releaseDecision == false {
                        startFinishing(id: id)
                        return
                    }
                    try await operations.startListening()
                    try checkRun(id)
                    microphoneReady = true
                    phase = .listening
                    status = "พูดได้เลย · ปล่อยปุ่มเพื่อส่ง"
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    if releaseDecision != nil {
                        // A fast release can precede permission/audio startup.
                        // Seal the newly available recorder before any ASR work.
                        operations.stopListening()
                        startFinishing(id: id)
                        return
                    }
                    recordingDidReachLimit()
                    try await photo?.value
                    try checkRun(id)
                } else {
                    try await photo?.value
                    try checkRun(id)
                    phase = .idle
                    status = "ถ่ายแล้ว · กดค้างเพื่อถ่ายและถามด้วยเสียง"
                }
            } catch {
                guard runID == id else { return }
                // Once touch-up transfers ownership, the finishing task handles
                // photo failure and resources; do not race its presentation.
                if hasStartedFinish { return }
                if listenAfterCapture && !microphoneReady {
                    // A brief touch requests a photo even without microphone
                    // permission/model. Only the startup-error path waits for
                    // that touch decision; normal recording starts immediately.
                    if releaseDecision == nil, ContinuousClock.now < pressDecisionDeadline {
                        do { try await Task.sleep(until: pressDecisionDeadline, clock: .continuous) }
                        catch { return }
                    }
                    guard runID == id, !Task.isCancelled else { return }
                    if releaseDecision == false {
                        startFinishing(id: id)
                        return
                    }
                }
                photo?.cancel()
                operations.cancelListening()
                _ = try? await photo?.value
                await operations.releaseSpeech()
                fail(error, id: id)
            }
        }
    }

    func finishVoiceQuestion() {
        finishPress(submit: true)
    }

    /// A brief touch still takes a photo but does not send a voice question.
    func finishCaptureOnlyPress() { finishPress(submit: false) }

    private func finishPress(submit: Bool) {
        guard (phase == .capturing || isListening), !isCancelling,
              releaseDecision == nil else { return }
        releaseDecision = submit
        // Physical touch-up stops input now, even if photo preparation is slow.
        operations.stopListening()
        if microphoneReady { startFinishing(id: runID) }
        else if !submit && reusesCurrentPhoto { operations.cancelListening() }
    }

    private func startFinishing(id: UUID) {
        guard !hasStartedFinish, let shouldSubmit = releaseDecision else { return }
        let photo = photoOperation
        let reuse = reusesCurrentPhoto
        guard photo != nil || reuse else { return }
        hasStartedFinish = true
        phase = shouldSubmit ? .transcribing : .capturing
        if reuse { status = shouldSubmit ? "กำลังถอดเสียงบนเครื่อง…" : "กำลังถ่ายภาพและเตรียมระยะ…" }
        else { status = "กำลังเตรียมภาพและระยะ…" }
        operationRevision += 1
        operation = Task { [weak self] in
            guard let self else { return }
            var releasedSpeech = false
            do {
                if !shouldSubmit {
                    operations.cancelListening()
                    await operations.releaseSpeech()
                    releasedSpeech = true
                    try checkRun(id)
                    if reuse { try await operations.capture() }
                    else { try await photo?.value }
                    try checkRun(id)
                    phase = .idle
                    status = "ถ่ายแล้ว · กดค้างเพื่อถ่ายและถามด้วยเสียง"
                    return
                }
                // Recording has stopped. Avoid loading ASR while the old visual
                // model or image preparation still owns its working memory.
                try await photo?.value
                try checkRun(id)
                isDecodingSpeech = true
                let text = try await operations.finishListening().trimmingCharacters(in: .whitespacesAndNewlines)
                await operations.releaseSpeech()
                releasedSpeech = true
                try checkRun(id)
                isDecodingSpeech = false
                guard !text.isEmpty else { throw VoiceCameraError.emptySpeech }
                recognizedQuestion = String(text.prefix(2_000))
                if reuse && operations.requiresFreshPhoto(recognizedQuestion) {
                    // Find requests describe the current camera frame. Capture
                    // after releasing the speech worker and check the same run.
                    phase = .capturing
                    status = "กำลังถ่ายภาพและเตรียมระยะ…"
                    try await operations.capture()
                    try checkRun(id)
                }
                phase = .answering
                status = "กำลังดูภาพและตอบ…"
                // The production submit boundary exchanges weights only when
                // the device cannot safely retain the prepared models together.
                try await operations.submitQuestion(recognizedQuestion)
                try checkRun(id)
                phase = .idle
                status = reuse ? "ถามต่อเกี่ยวกับภาพนี้ได้" : "ตอบแล้ว · กดค้างเพื่อถามภาพใหม่"
            } catch {
                guard runID == id else { return }
                operations.cancelListening()
                if !releasedSpeech { await operations.releaseSpeech() }
                fail(error, id: id)
            }
        }
    }

    private func recordingDidReachLimit() {
        guard isListening, operations.shouldFinish() else { return }
        status = "รับเสียงครบเวลาที่กำหนด · ปล่อยปุ่มเพื่อส่ง"
    }

    /// Invalidate first, then join teardown so a delayed capture/ASR result cannot
    /// submit a question after backgrounding or replace a newer interaction.
    func cancel() async {
        if isCancelling {
            await withCheckedContinuation { cancellationWaiters.append($0) }
            return
        }
        isCancelling = true
        operations.stopAnswerSpeech()
        runID = UUID()
        let pending = operation
        pending?.cancel()
        let photo = photoOperation
        photo?.cancel()
        operations.cancelListening()
        operations.cancelQuestion()
        await pending?.value
        _ = try? await photo?.value
        await operations.releaseSpeech()
        operation = nil
        photoOperation = nil
        reusesCurrentPhoto = false
        microphoneReady = false
        releaseDecision = nil
        hasStartedFinish = false
        isDecodingSpeech = false
        phase = .idle
        isCancelling = false
        recognizedQuestion = ""
        error = nil
        status = "หยุดแล้ว · กดค้างเพื่อถามใหม่"
        let waiters = cancellationWaiters
        cancellationWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    func resetPresentation() {
        guard !isBusy else { return }
        recognizedQuestion = ""
        error = nil
        status = "กดค้างเพื่อถาม · แตะเพื่อถ่าย"
    }

    func waitForCurrentOperation() async {
        // Touch-up may replace microphone startup with the finishing task while
        // a caller is waiting. Join that successor as well.
        while let pending = operation {
            let revision = operationRevision
            await pending.value
            if operationRevision == revision { return }
        }
    }

    private func checkRun(_ id: UUID) throws {
        try Task.checkCancellation()
        guard runID == id else { throw CancellationError() }
    }

    private func fail(_ failure: Error, id: UUID) {
        guard runID == id else { return }
        isDecodingSpeech = false
        phase = .idle
        if failure is CancellationError { status = "หยุดแล้ว · กดค้างเพื่อถามใหม่" }
        else {
            error = failure.localizedDescription
            status = "กดค้างเพื่อลองถามใหม่"
        }
    }
}

enum VoiceCameraError: LocalizedError {
    case cameraUnavailable, photoPreparation, emptySpeech, inference(String)
    var errorDescription: String? {
        switch self {
        case .cameraUnavailable: "เปิดกล้องไม่ได้ ตรวจสิทธิ์กล้องในตั้งค่า หรือใช้เครื่องมือทดสอบภาพในตั้งค่า"
        case .photoPreparation: "เตรียมภาพไม่สำเร็จ กรุณาถ่ายใหม่"
        case .emptySpeech: "ไม่ได้ยินคำถาม กดค้างไว้แล้วพูด จากนั้นปล่อยปุ่มเพื่อส่ง"
        case .inference(let message): message
        }
    }
}
