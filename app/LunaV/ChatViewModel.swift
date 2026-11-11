import Foundation
import Observation
import UIKit

struct ChatMessage: Identifiable {
    let id = UUID()
    let isUser: Bool
    var text: String
    var interrupted = false
    var action: PhotoAction = .question
    var region: PhotoRegion?
    var sourceText: String?
    var truncated = false
    var sources: [TextSource] = []
    var sourceTitle: String?
    var distance: LiDARMeasurement?
    var distanceTarget: ObjectGroundingTarget?
}

@MainActor @Observable
final class ChatViewModel {
    var photo: UIImage?
    var photoURL: URL?
    var messages: [ChatMessage] = []
    var question = ""
    var action: PhotoAction = .question {
        didSet {
            if oldValue != action {
                question = ""
                resetSession = true
                error = nil
                status = action == .question ? "พร้อมถามเกี่ยวกับภาพนี้" : "เลือกพื้นที่แล้วกด\(action.title)ได้เลย"
            }
        }
    }
    private(set) var region: PhotoRegion = .full
    var isWorking = false
    var isPreparingPhoto = false
    var status = "ถ่ายภาพ แล้วถามได้เลย"
    var error: String?
    var metrics: InferenceMetrics?
    var policy = RuntimePolicy.current()
    var showConversation = false
    var showDetails = false
    var showDistanceSelection = false
    private(set) var depth: LiDARSnapshot?
    private(set) var lidarRequested = false
    private(set) var monocularRequested = false
    private(set) var depthCameraIdentifier: String?
    private(set) var depthIssue: String?
    private(set) var selectedDistancePoint: CGPoint?
    private var pendingDistanceQuestion: String?
    private(set) var sourceAnalysis: TextSourceAnalysis?
    private(set) var isDiscoveringSources = false
    private(set) var activeSourceID: Int?
    var selectedSourceTitle: String? { sourceAnalysis?.sources.first { $0.id == activeSourceID }?.title }
    let answerSpeech: AnswerSpeechPlayer?
    private let runtime = ModelRuntime(directory: ModelRuntime.bundledDirectory())
    typealias DistanceGrounder = @Sendable (String, URL) async throws -> String
    private let distanceGrounder: DistanceGrounder?
    typealias DepthPredictor = @Sendable (URL, PhotoCameraIntrinsics, Double, Date, Double) async throws -> LiDARSnapshot
    private let depthPredictor: DepthPredictor?
    private let usesMonocularDepth: Bool
    private var contextClearTask: Task<Void, Never>?
    private var generation: Task<Void, Never>?
    private var resetSession = true
    private var runID = UUID()
    private var originalURL: URL?
    private var photoCapturedAt: Date?
    private var croppedURL: URL?
    private var document: DocumentText?
    private var sourceImageURL: URL?
    private var pendingDepth: PendingDepth?
    static let retainedMessageLimit = 40

    private struct PendingDepth: Sendable {
        let image: URL
        let intrinsics: PhotoCameraIntrinsics
        let scale: Double
        let capturedAt: Date
        let timestamp: Double
    }

    init(distanceGrounder: DistanceGrounder? = nil, depthPredictor: DepthPredictor? = nil,
         usesMonocularDepth: Bool? = nil, answerSpeech: AnswerSpeechPlayer? = nil) {
        self.answerSpeech = answerSpeech
        self.distanceGrounder = distanceGrounder
        self.depthPredictor = depthPredictor
        self.usesMonocularDepth = usesMonocularDepth ?? ModelPreparation.requiresMonocularDepth
    }

    var canSend: Bool {
        photoURL != nil && (action != .question || !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && !isWorking && !isPreparingPhoto
    }

    func setPhoto(_ data: Data, depth: LiDARSnapshot? = nil, lidarRequested: Bool = false, depthIssue: String? = nil,
                  openConversation: Bool = true, capturedAt: Date? = nil) async {
        guard !isWorking && !isPreparingPhoto else { return }
        isPreparingPhoto = true
        defer { isPreparingPhoto = false }
        do {
            let prepared = try await PhotoStore.prepare(data)
            if Task.isCancelled {
                PhotoStore.remove(prepared)
                throw CancellationError()
            }
            removePhotoFiles()
            photoURL = prepared.url
            originalURL = prepared.originalURL
            photoCapturedAt = capturedAt
            photo = UIImage(data: prepared.data)
            self.depth = depth
            self.lidarRequested = lidarRequested
            self.depthIssue = depthIssue
            monocularRequested = false
            depthCameraIdentifier = nil
            region = .full
            clearConversation()
            error = nil
            status = "เลือกถามภาพ อ่าน หรือสรุปข้อความได้เลย"
            showConversation = openConversation
            policy = .current()
        } catch is CancellationError {
            // A cancelled import/capture must leave the previous photo untouched.
        } catch { self.error = error.localizedDescription }
    }

    func setCapturedPhoto(_ capture: CapturedPhoto, openConversation: Bool = true) async {
        await setPhoto(capture.data, depth: capture.depth, lidarRequested: capture.lidarRequested,
                       depthIssue: capture.depthIssue, openConversation: openConversation, capturedAt: capture.capturedAt)
        guard !Task.isCancelled, photoURL != nil, error == nil else { return }
        depthCameraIdentifier = capture.cameraIdentifier
        // A failed sensor capture stays a sensor failure; never relabel an AI
        // prediction as LiDAR. Only devices without LiDAR use the model fallback;
        // switching a LiDAR-equipped phone to its front camera keeps it disabled.
        guard !capture.lidarRequested, usesMonocularDepth else { return }
        monocularRequested = true
        guard let intrinsics = capture.cameraIntrinsics, intrinsics.isValid else {
            depthIssue = "ภาพนี้ไม่มีข้อมูลเลนส์สำหรับคำนวณระยะ กรุณาถ่ายด้วยกล้องในแอพอีกครั้ง"
            return
        }
        pendingDepth = PendingDepth(image: originalURL ?? photoURL!, intrinsics: intrinsics,
            scale: DepthCalibrationStore.shared.scale(for: capture.cameraIdentifier),
            capturedAt: capture.capturedAt, timestamp: capture.captureTimestamp)
        status = "พร้อมถาม · ประเมินระยะจากภาพนี้เมื่อต้องใช้"
    }

    var canRequestDistanceMeasurement: Bool {
        (depth != nil && depthIssue == nil) || pendingDepth != nil
    }

    /// The immutable capture calibration and timestamps belong to this photo.
    /// Ordinary questions never run DA3 or keep a second large model resident.
    private func ensureDepthForCurrentPhoto() async throws -> LiDARSnapshot {
        if let depth { return depth }
        guard let pendingDepth else { throw MonocularDepthError.invalidIntrinsics }
        do {
            status = "กำลังประเมินระยะจาก Depth Anything 3…"
            try await enterModelPhase(.depth)
            try Task.checkCancellation()
            let snapshot: LiDARSnapshot
            if let depthPredictor {
                snapshot = try await depthPredictor(pendingDepth.image, pendingDepth.intrinsics,
                    pendingDepth.scale, pendingDepth.capturedAt, pendingDepth.timestamp)
            } else {
                let result = DepthPredictionResult()
                let work = SpeechTask {
                    try await MonocularDepthRuntime.shared.prepare()
                    let snapshot = try await MonocularDepthRuntime.shared.predict(
                        imageURL: pendingDepth.image, intrinsics: pendingDepth.intrinsics,
                        calibrationScale: pendingDepth.scale,
                        capturedAt: pendingDepth.capturedAt, photoTimestamp: pendingDepth.timestamp)
                    await result.set(snapshot)
                    return "depth ready"
                }
                _ = try await work.value(timeout: .seconds(120))
                guard let value = await result.value else { throw MonocularDepthError.invalidModel }
                snapshot = value
            }
            try Task.checkCancellation()
            depth = snapshot
            depthIssue = nil
            status = "พร้อมถาม · ระยะประมาณจาก Depth Anything 3"
            if RuntimePolicy.prefersEphemeralModels { await MonocularDepthRuntime.shared.release() }
            return snapshot
        } catch {
            if RuntimePolicy.prefersEphemeralModels { await MonocularDepthRuntime.shared.release() }
            if !(error is CancellationError) {
                depthIssue = "ประเมินระยะภาพนี้ไม่ได้: \(error.localizedDescription)"
            }
            throw error
        }
    }

    var visualHasPendingWork: Bool { get async { await runtime.hasPendingWork } }
    func prepareVisualModel() async throws {
        try await runtime.warmUp()
        await releaseVisualResourcesWhenIdle()
    }

    func prepareForCapture() async {
        answerSpeech?.stop()
        await contextClearTask?.value
        await releaseVisualResourcesWhenIdle()
    }

    private func releaseVisualResourcesWhenIdle() async {
        if RuntimePolicy.prefersEphemeralModels {
            await runtime.releaseWeightsPreservingConversation()
        }
    }

    /// Admit the next model using measured process headroom. Never exchange
    /// weights during a worker: callers join capture/decode before this handoff.
    func enterModelPhase(_ phase: LocalModelPhase) async throws {
        let depthBusy = await MonocularDepthRuntime.shared.hasPendingWork
        let visionBusy = await runtime.hasPendingWork
        guard !LocalSpeechDecoder.isWorking, !depthBusy, !visionBusy else { throw ModelRuntimeError.busy }
        // Native Dictation does not reserve or load the bundled Whisper weights.
        // Recording/recognition is managed by iOS; only MLX and DA3 exchange here.
        if phase == .speech { return }
        let depthReady = await MonocularDepthRuntime.shared.isPrepared
        let visualBytes = await runtime.residentMemoryBytes
        let depthReserve = usesMonocularDepth && !depthReady ? MonocularDepthRuntime.reservedBytes : 0
        let keep = RuntimePolicy.canKeepPreparedModels(
            availableBytes: RuntimePolicy.processHeadroom, physicalBytes: ProcessInfo.processInfo.physicalMemory,
            visionResidentBytes: visualBytes, speechPrepared: true,
            additionalReservedBytes: depthReserve)
        if !keep {
            if phase != .vision { await runtime.release(); resetSession = true }
            if phase != .depth { await MonocularDepthRuntime.shared.release() }
        }
    }

    func calibrateDepth(knownMeters: Double) {
        guard !isWorking, !isPreparingPhoto, let depth, let identifier = depthCameraIdentifier else { return }
        do {
            let scale = try DepthCalibrationStore.calibratedScale(snapshot: depth, point: CGPoint(x: 0.5, y: 0.5), knownMeters: knownMeters)
            let updated = try depth.applyingCalibrationScale(scale)
            try DepthCalibrationStore.shared.setScale(scale, for: identifier)
            self.depth = updated
            clearConversation()
            status = "บันทึกการเทียบระยะสำหรับกล้องนี้แล้ว"
        } catch { self.error = error.localizedDescription }
    }

    func resetDepthCalibration() {
        guard !isWorking, let identifier = depthCameraIdentifier else { return }
        do {
            let updated = try depth?.applyingCalibrationScale(1)
            DepthCalibrationStore.shared.reset(for: identifier)
            depth = updated
            clearConversation()
        } catch { self.error = error.localizedDescription }
    }

    func requestDistanceMeasurement() {
        guard !isWorking, !isPreparingPhoto, canRequestDistanceMeasurement else { return }
        pendingDistanceQuestion = "จุดที่เลือกอยู่ห่างกล้องแค่ไหน?"
        if depth != nil { showDistanceSelection = true; return }
        let id = UUID()
        runID = id
        isWorking = true
        error = nil
        generation = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.ensureDepthForCurrentPhoto()
                try Task.checkCancellation()
                guard self.runID == id else { return }
                self.showDistanceSelection = true
            } catch is CancellationError { self.status = "หยุดเตรียมระยะแล้ว" }
            catch { self.error = self.depthIssue ?? error.localizedDescription }
            if self.runID == id { self.isWorking = false; self.generation = nil }
        }
    }

    func cancelDistanceSelection() { pendingDistanceQuestion = nil }

    func confirmDistancePoint(_ point: CGPoint) {
        guard !isWorking, let depth else { return }
        let prompt = pendingDistanceQuestion ?? "จุดที่เลือกอยู่ห่างกล้องแค่ไหน?"
        do {
            let value = try LiDARRangeReader.measure(depth, at: point)
            selectedDistancePoint = point
            appendDistanceAnswer(prompt: prompt, answer: value.answer(inCentimeters: DistanceQuestion.usesCentimeters(prompt)), measurement: value)
            pendingDistanceQuestion = nil
            question = ""
            showDistanceSelection = false
        } catch { self.error = error.localizedDescription }
    }

    private func appendDistanceAnswer(prompt: String, answer: String, measurement: LiDARMeasurement? = nil) {
        trimMessagesForNewExchange()
        messages.append(.init(isUser: true, text: prompt, region: region, sourceTitle: selectedSourceTitle))
        messages.append(.init(isUser: false, text: answer, distance: measurement))
        question = ""
        metrics = nil
        error = nil
        resetSession = true
        status = measurement.map { "อ่านระยะจาก \($0.depthSource.title) ของภาพนี้แล้ว" } ?? "ยังวัดระยะจุดนี้ไม่ได้"
        speakCompletedAnswer(at: messages.count - 1)
    }

    private func handleDistanceQuestion(_ prompt: String) -> Bool {
        guard lidarRequested || monocularRequested || depth != nil,
              DistanceQuestion.isDistance(prompt) else { return false }
        if let depthIssue, pendingDepth == nil {
            appendDistanceAnswer(prompt: prompt, answer: depthIssue)
        } else if DistanceQuestion.isBetweenObjects(prompt) {
            appendDistanceAnswer(prompt: prompt, answer: "ตอนนี้วัดจากกล้องถึงวัตถุได้ การวัดระหว่างวัตถุสองชิ้นยังไม่รองรับ")
        } else if let image = photoURL, depth != nil || pendingDepth != nil {
            startAutomaticDistanceQuestion(prompt, image: image)
        } else {
            appendDistanceAnswer(prompt: prompt, answer: depthIssue ?? "ภาพนี้ไม่มีข้อมูลระยะที่ใช้ได้ กรุณาถ่ายภาพใหม่")
        }
        return true
    }

    private func startAutomaticDistanceQuestion(_ prompt: String, image: URL) {
        // Each question locates its own target; a previous manually selected point never
        // silently becomes the location of a different object.
        let context = messages.suffix(4).filter { !$0.interrupted && !$0.truncated }
            .map { ($0.isUser ? "User: " : "Assistant: ") + String($0.text.prefix(180)) }
            .joined(separator: "\n")
        trimMessagesForNewExchange()
        messages.append(.init(isUser: true, text: prompt))
        messages.append(.init(isUser: false, text: ""))
        let index = messages.count - 1
        let id = UUID()
        runID = id
        question = ""
        error = nil
        metrics = nil
        isWorking = true
        status = "กำลังหาวัตถุและอ่านระยะ…"
        let clearTask = contextClearTask
        let injectedGrounder = distanceGrounder
        generation = Task { [weak self, runtime] in
            guard let self else { return }
            do {
                await clearTask?.value
                let depth = try await self.ensureDepthForCurrentPhoto()
                try Task.checkCancellation()
                if injectedGrounder == nil { try await self.enterModelPhase(.vision) }
                let ground = self.objectGrounder(for: .objectLocation)
                let result = try await AutomaticDistanceResolver.resolve(
                    question: prompt, image: image, depth: depth, conversationContext: context,
                    beforeRefine: {
                        await runtime.releaseWeightsPreservingConversation()
                        try Task.checkCancellation()
                    }, ground: ground)
                try Task.checkCancellation()
                guard self.runID == id, self.messages.indices.contains(index) else { return }
                let value = result.measurement
                self.messages[index].text = result.answer(inCentimeters: DistanceQuestion.usesCentimeters(prompt))
                self.messages[index].distance = value
                self.messages[index].distanceTarget = result.target
                self.status = "อ่านระยะจากตำแหน่งวัตถุอัตโนมัติแล้ว"
                await self.releaseVisualResourcesWhenIdle()
                try Task.checkCancellation()
                self.speakCompletedAnswer(at: index)
            } catch is CancellationError {
                self.markInterrupted(index: index, id: id)
            } catch {
                guard self.runID == id, self.messages.indices.contains(index) else { return }
                if error is ModelRuntimeError {
                    self.error = error.localizedDescription
                    self.messages.remove(at: index)
                } else {
                    self.messages[index].text = self.depthIssue ?? error.localizedDescription
                    await self.releaseVisualResourcesWhenIdle()
                    if !Task.isCancelled { self.speakCompletedAnswer(at: index) }
                }
                self.status = "ยังระบุระยะวัตถุนี้ไม่ได้"
            }
            if self.runID == id {
                await self.releaseVisualResourcesWhenIdle()
                self.resetSession = true
                self.isWorking = false
                self.generation = nil
            }
        }
    }

    private func objectGrounder(for task: ModelTask) -> DistanceGrounder {
        distanceGrounder ?? { [runtime] prompt, image in
            let output = GroundingOutput()
            try await runtime.generate(prompt: prompt, image: image, reset: true, task: task) { event in
                await output.receive(event)
            }
            return await output.text
        }
    }

    /// Allows integration tests and lifecycle work to join the active operation.
    func waitForPendingResponse() async { await generation?.value }

    func selectRegion(_ selection: PhotoRegion) {
        guard !isWorking else { return }
        activeSourceID = nil
        selectedDistancePoint = nil
        region = selection
        if let croppedURL { try? FileManager.default.removeItem(at: croppedURL) }
        croppedURL = nil
        document = nil
        resetSession = true
        error = nil
        status = "เลือก\(selection.label)แล้ว"
    }

    func selectSource(_ source: TextSource) {
        guard !isWorking else { return }
        selectRegion(source.region)
        activeSourceID = source.id
        document = DocumentText(text: source.text, lineCount: source.lines.count)
        status = "เลือก\(source.title)แล้ว"
    }

    func discoverSources() {
        guard !isWorking, photoURL != nil, sourceAnalysis == nil else { return }
        isWorking = true
        error = nil
        generation = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.analyzePhotoSources()
                self.status = "พบข้อความ \(self.sourceAnalysis?.sources.count ?? 0) กลุ่ม"
            } catch is CancellationError { self.status = "หยุดแยกข้อความแล้ว" }
            catch { self.error = error.localizedDescription }
            await self.releaseVisualResourcesWhenIdle()
            self.isWorking = false
            self.generation = nil
        }
    }

    private func analyzePhotoSources() async throws -> TextSourceAnalysis {
        if let sourceAnalysis { return sourceAnalysis }
        guard !LocalSpeechDecoder.isWorking else { throw LocalSpeechError.busy }
        try await enterModelPhase(.vision)
        guard ProcessInfo.processInfo.thermalState != .critical else { throw ModelRuntimeError.thermal }
        isDiscoveringSources = true
        defer { isDiscoveringSources = false }
        status = "กำลังหากลุ่มข้อความในภาพ…"
        let image: URL
        if let cached = sourceImageURL { image = cached }
        else {
            guard let original = originalURL ?? photoURL else { throw DocumentTextError.unreadableImage }
            let prepared = try await PhotoStore.crop(original: original, region: .full, forText: true)
            if Task.isCancelled { try? FileManager.default.removeItem(at: prepared.url); throw CancellationError() }
            image = prepared.url
            sourceImageURL = image
        }
        let scan = try await DocumentTextReader.scan(image: image)
        try Task.checkCancellation()
        await contextClearTask?.value
        status = "พบ \(scan.sources.count) กลุ่ม · กำลังดูว่าอยู่บนวัตถุใด…"
        let analysis = try await TextSourceAnalyzer.classify(scan.sources, image: image, runtime: runtime) { [weak self] done, total in
            await self?.sourceProgress(done: done, total: total)
        }
        try Task.checkCancellation()
        sourceAnalysis = analysis
        resetSession = true
        return analysis
    }

    private func sourceProgress(done: Int, total: Int) {
        status = "กำลังแยกวัตถุ \(done)/\(total)…"
    }

    private func imageForRequest(action: PhotoAction) async throws -> URL {
        if action == .question && region == .full, let photoURL { return photoURL }
        if let croppedURL { return croppedURL }
        guard let original = originalURL ?? photoURL else { throw DocumentTextError.unreadableImage }
        let cropped = try await PhotoStore.crop(original: original, region: region, forText: true)
        if Task.isCancelled { try? FileManager.default.removeItem(at: cropped.url); throw CancellationError() }
        croppedURL = cropped.url
        return cropped.url
    }

    func send(_ suggested: String? = nil) {
        if let suggested { question = suggested }
        guard canSend else { return }
        guard !LocalSpeechDecoder.isWorking else {
            error = LocalSpeechError.busy.localizedDescription
            return
        }
        answerSpeech?.stop()
        let prompt = String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000))
        if action == .question && handleDistanceQuestion(prompt) { return }
        let requestedAction = action
        let findRequest = requestedAction == .question ? NearbyObjectRequest.parse(prompt) : nil
        let finderImage = photoURL
        let finderCaptureTime = photoCapturedAt
        let selectedRegion = findRequest == nil ? region : .full
        let sourceTitle = findRequest == nil ? selectedSourceTitle : nil
        question = ""
        error = nil
        metrics = nil
        isWorking = true
        policy = .current()
        let displayPrompt = requestedAction == .question ? prompt
            : requestedAction.title + (prompt.isEmpty ? "" : " · " + prompt)
        trimMessagesForNewExchange()
        messages.append(.init(isUser: true, text: displayPrompt, action: requestedAction, region: selectedRegion, sourceTitle: sourceTitle))
        messages.append(.init(isUser: false, text: "", action: requestedAction, sourceTitle: sourceTitle))
        let index = messages.count - 1
        let id = UUID()
        runID = id
        let reset = resetSession
        let clearTask = contextClearTask
        generation = Task { [weak self, runtime] in
            guard let self else { return }
            do {
                await clearTask?.value
                try await self.enterModelPhase(.vision)
                guard ProcessInfo.processInfo.thermalState != .critical else { throw ModelRuntimeError.thermal }
                self.status = requestedAction == .question ? "กำลังเตรียมภาพ…" : "กำลังอ่านข้อความใน\(selectedRegion.label)…"
                try Task.checkCancellation()
                var finderResult: NearbyObjectResult?
                switch requestedAction {
                case .question:
                    if let findRequest, let finderImage {
                        self.status = "กำลังหาของในภาพ…"
                        let result = try await findRequest.find(image: finderImage,
                            countMatches: self.objectGrounder(for: .objectMatchCount),
                            ground: self.objectGrounder(for: .objectLocation))
                        try Task.checkCancellation()
                        guard self.runID == id else { return }
                        self.messages[index].text = result.answer
                        finderResult = result
                        self.resetSession = true
                    } else {
                        let image = try await self.imageForRequest(action: requestedAction)
                        try await runtime.generate(prompt: prompt, image: image, reset: reset) { [weak self] event in
                            await self?.receive(event, index: index, id: id)
                        }
                        self.resetSession = false
                    }
                case .read, .summarize:
                    let recognized: DocumentText
                    if let cached = self.document { recognized = cached }
                    else if selectedRegion == .full && self.activeSourceID == nil {
                        let analysis = try await self.analyzePhotoSources()
                        recognized = DocumentText(text: analysis.text, lineCount: analysis.lineCount)
                        self.document = recognized
                        self.messages[index].sources = analysis.sources
                    } else {
                        let image = try await self.imageForRequest(action: requestedAction)
                        recognized = try await DocumentTextReader.read(image: image)
                        self.document = recognized
                    }
                    try Task.checkCancellation()
                    guard self.runID == id else { return }
                    if selectedRegion == .full, let analysis = self.sourceAnalysis { self.messages[index].sources = analysis.sources }
                    if requestedAction == .read {
                        // Verbatim OCR never goes through a generative model or loop trimming.
                        self.messages[index].text = recognized.text
                        self.resetSession = true
                    } else {
                        self.messages[index].sourceText = recognized.text
                        self.status = "กำลังสรุปข้อความ…"
                        try await runtime.generate(
                            prompt: AnswerPolicy.summaryPrompt(text: recognized.text, focus: prompt),
                            image: nil, reset: true, task: .summary
                        ) { [weak self] event in
                            await self?.receive(event, index: index, id: id)
                        }
                        self.resetSession = true
                    }
                }
                try Task.checkCancellation()
                guard self.runID == id else { return }
                self.messages[index].truncated = self.metrics?.truncated == true
                self.status = requestedAction == .read ? "อ่านแล้ว · \(self.document?.lineCount ?? 0) บรรทัด"
                    : self.metrics?.recoveryFailed == true ? "ล้างบริบทแล้ว · ลองระบุคำถามให้ชัดขึ้น"
                    : (self.metrics?.retryCount ?? 0) > 0 ? "สร้างคำตอบใหม่หลังล้างบริบทแล้ว"
                    : self.metrics?.contextReset == true ? "ปรับบริบทอัตโนมัติแล้ว · ถามต่อได้"
                    : requestedAction == .summarize ? "สรุปแล้ว · เปิดดูข้อความต้นฉบับได้" : "ถามต่อเกี่ยวกับภาพนี้ได้"
                await self.releaseVisualResourcesWhenIdle()
                try Task.checkCancellation()
                if finderResult?.canPlayCenterCue(capturedAt: finderCaptureTime) == true {
                    NearbyObjectCue.play()
                }
                self.speakCompletedAnswer(at: index)
            } catch is CancellationError {
                self.markInterrupted(index: index, id: id)
            } catch {
                guard self.runID == id else { return }
                self.error = error.localizedDescription
                self.resetSession = true
                if self.messages.indices.contains(index), self.messages[index].text.isEmpty {
                    self.messages.remove(at: index)
                }
                self.status = requestedAction == .question ? "ลองถามอีกครั้งได้" : "เลือกพื้นที่เล็กลงหรือถ่ายให้ชัดขึ้นแล้วลองใหม่"
            }
            if self.runID == id {
                await self.releaseVisualResourcesWhenIdle()
                self.isWorking = false
                self.generation = nil
            }
        }
    }

    private func receive(_ event: ModelEvent, index: Int, id: UUID) {
        guard !Task.isCancelled, runID == id, messages.indices.contains(index) else { return }
        switch event {
        case .loading: status = "กำลังเตรียมโมเดล…"
        case .ready: status = action == .summarize ? "กำลังสรุปข้อความ…" : "กำลังดูภาพและตอบ…"
        case .text(let text): messages[index].text = text
        case .completed(let result): metrics = result
        }
    }

    private func markInterrupted(index: Int, id: UUID) {
        guard runID == id, messages.indices.contains(index) else { return }
        if messages[index].text.isEmpty { messages.remove(at: index) }
        else { messages[index].interrupted = true }
        status = "หยุดแล้ว เริ่มใหม่ได้"
    }

    private func speakCompletedAnswer(at index: Int) {
        guard !Task.isCancelled, error == nil, messages.indices.contains(index),
              !messages[index].isUser, !messages[index].interrupted,
              !messages[index].truncated, metrics?.recoveryFailed != true else { return }
        let message = messages[index]
        answerSpeech?.speak(message.text, id: message.id)
    }

    func stop() {
        answerSpeech?.stop()
        generation?.cancel()
    }

    func clearConversation() {
        guard !isWorking else { return }
        answerSpeech?.stop()
        messages = []
        question = ""
        metrics = nil
        resetSession = true
        selectedDistancePoint = nil
        pendingDistanceQuestion = nil
        showDistanceSelection = false
        let previousClear = contextClearTask
        contextClearTask = Task { [runtime] in
            await previousClear?.value
            await runtime.clearContext()
            await ObjectSurfaceRefiner.shared.clear()
        }
        error = nil
        status = "ล้างบริบทแล้ว · ถามภาพนี้ใหม่ได้"
    }

    private func removePhotoFiles() {
        for url in [photoURL, originalURL, croppedURL, sourceImageURL].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
        photoURL = nil
        originalURL = nil
        photoCapturedAt = nil
        croppedURL = nil
        document = nil
        sourceImageURL = nil
        sourceAnalysis = nil
        pendingDepth = nil
        activeSourceID = nil
        depth = nil
        lidarRequested = false
        monocularRequested = false
        depthCameraIdentifier = nil
        depthIssue = nil
        selectedDistancePoint = nil
        pendingDistanceQuestion = nil
        showDistanceSelection = false
    }

    func retake() async {
        guard !isWorking else { return }
        showConversation = false
        clearConversation()
        photo = nil
        region = .full
        removePhotoFiles()
        status = "ถ่ายภาพ แล้วถามได้เลย"
        // Keep the warmed weights for the next photo. Phase admission handles
        // constrained devices; retaking alone must not force a cold model load.
        await contextClearTask?.value
    }

    func suspend() async {
        stop()
        if let generation { await generation.value }
        await contextClearTask?.value
        await runtime.release()
        await ObjectSurfaceRefiner.shared.clear()
        resetSession = true
    }

    func refreshPolicy() {
        policy = .current()
        if ProcessInfo.processInfo.thermalState == .critical { stop() }
    }

    /// UI history is separate from the model's two-turn context. Trim only before
    /// starting work, so an in-flight response's array index never changes.
    private func trimMessagesForNewExchange() {
        let excess = messages.count - (Self.retainedMessageLimit - 2)
        guard excess > 0 else { return }
        messages.removeFirst(excess)
        if messages.first?.isUser == false { messages.removeFirst() }
    }
}

private actor GroundingOutput {
    private(set) var text = ""
    func receive(_ event: ModelEvent) {
        if case .text(let value) = event { text = value }
    }
}

private actor DepthPredictionResult {
    private(set) var value: LiDARSnapshot?
    func set(_ value: LiDARSnapshot) { self.value = value }
}
