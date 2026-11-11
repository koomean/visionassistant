import CoreImage
import Foundation
import MLX
import MLXLMCommon
import MLXVLM
import os

struct InferenceMetrics: Sendable {
    var tokensPerSecond: Double = 0
    var firstTokenSeconds: Double = 0
    var totalSeconds: Double = 0
    var generatedTokens: Int = 0
    var peakMemoryBytes: Int = 0
    var profileName = ""
    var stoppedForRepetition = false
    var truncated = false
    var contextReset = false
    var retryCount = 0
    var contextTokens = 0
    var recoveryFailed = false
}

enum ModelEvent: Sendable {
    case loading
    case ready
    case text(String)
    case completed(InferenceMetrics)
}

enum ModelRuntimeError: LocalizedError {
    case simulator, missingModel, insufficientMemory, busy, thermal, contextFull, documentTooLong
    var errorDescription: String? {
        switch self {
        case .simulator: "Simulator ใช้ทดสอบหน้าจอได้ กรุณารันบน iPhone เพื่อใช้โมเดลผ่าน Metal"
        case .missingModel: "ไม่พบโมเดล 4-bit กรุณารัน Scripts/prepare-model.sh แล้ว build ใหม่"
        case .insufficientMemory: "หน่วยความจำที่ iOS อนุญาตยังไม่พอ ลองปิดแอพอื่นแล้วเปิด LunaV ใหม่"
        case .busy: "โมเดลกำลังทำงาน กรุณารอให้เสร็จก่อน"
        case .thermal: "เครื่องร้อนมาก กรุณาพักให้เครื่องเย็นลงแล้วลองอีกครั้ง"
        case .documentTooLong: "ข้อความส่วนนี้ยาวเกินขีดจำกัดของเครื่อง กรุณาเลือกพื้นที่ให้เล็กลงแล้วสรุปอีกครั้ง"
        case .contextFull: "คำถามนี้ยาวเกินขีดจำกัดของเครื่อง กรุณาถามให้สั้นลง"
        }
    }
}

/// ChatSession is not Sendable. This private handle is accessed only by ModelRuntime,
/// whose isGenerating gate prevents all concurrent mutation while synchronize suspends.
/// ChatSession itself serializes its cache and waits for the producer's Metal work.
private final class SessionHandle: @unchecked Sendable {
    let value: ChatSession
    init(_ value: ChatSession) { self.value = value }
    func synchronize() async { await value.synchronize() }
    func clear() async { await value.clear() }
}

/// All MLX state stays on this actor. One model and one reusable vision/KV session per photo.
actor ModelRuntime {
    private var container: ModelContainer?
    private var session: SessionHandle?
    private var loadingTask: Task<ModelContainer, Error>?
    private var imageID: URL?
    private var questionTextCache = QuestionTextCache()
    private var sessionProfile: RuntimePolicy?
    private var sessionTask: ModelTask = .question
    private var contextTokens = 0
    private var conversation = ConversationContext()
    private var clearRequested = false
    private var isGenerating = false
    private var visionWarmed = false
    private var releaseRequested = false
    private var modelLoads = 0
    private var warmups = 0
    private var memoryEvents: [RuntimeMemoryEvent] = []
    private let directory: URL
    private let tokenizerLoader: LocalTokenizerLoader
    private let textScanner: @Sendable (URL) async throws -> TextScan
    private let seed: UInt64?
    private let diagnostic: (@Sendable (String) -> Void)?

    init(directory: URL, seed: UInt64? = nil, diagnostic: (@Sendable (String) -> Void)? = nil,
         tokenizerLoader: LocalTokenizerLoader = .init(),
         textScanner: @escaping @Sendable (URL) async throws -> TextScan = { try await DocumentTextReader.scan(image: $0) }) {
        self.directory = directory
        self.tokenizerLoader = tokenizerLoader
        self.textScanner = textScanner
        self.seed = seed
        self.diagnostic = diagnostic
    }

    static func bundledDirectory() -> URL {
        // A converted/fine-tuned replacement can be copied through Finder > Files > LunaV.
        let override = URL.documentsDirectory.appending(path: "Model", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: override.appending(path: "config.json").path) {
            return override
        }
        return (Bundle.main.resourceURL ?? .applicationDirectory)
            .appending(path: "Qwen3-VL-2B-Instruct-4bit", directoryHint: .isDirectory)
    }

    var isPrepared: Bool { container != nil && visionWarmed }
    /// Metal kernels remain warm after weights are evicted. This does not claim
    /// that a model is resident or skip admission for the next actual inference.
    var hasWarmedKernels: Bool { visionWarmed }
    var retainedTextTurnCount: Int { conversation.recent.count }
    var residentMemoryBytes: Int { container == nil ? 0 : Memory.activeMemory }
    var hasPendingWork: Bool { isGenerating || loadingTask != nil }

    struct PreparationStats: Codable, Sendable {
        let modelLoads: Int
        let warmups: Int
        let isPrepared: Bool
        let residentBytes: Int
        let hasWarmedKernels: Bool
    }

    func preparationStats() -> PreparationStats {
        .init(modelLoads: modelLoads, warmups: warmups, isPrepared: isPrepared,
              residentBytes: residentMemoryBytes, hasWarmedKernels: hasWarmedKernels)
    }

    /// Model files alone do not prepare Metal kernels or the vision encoder.
    /// Use a disposable one-token image turn; its synthetic content never enters
    /// user history. The camera gate waits for synchronize before reporting ready.
    func warmUp() async throws {
        try Task.checkCancellation()
        guard !isGenerating else { throw ModelRuntimeError.busy }
        if hasWarmedKernels { return }
        guard ProcessInfo.processInfo.thermalState != .critical else { throw ModelRuntimeError.thermal }
        isGenerating = true
        defer {
            isGenerating = false
            if releaseRequested { releaseLoadedModel(); releaseRequested = false }
        }
        let model = try await load()
        do {
            try Task.checkCancellation()
            guard !releaseRequested else { throw CancellationError() }
        } catch {
            releaseLoadedModel()
            throw error
        }
        let policy = RuntimePolicy.current(residentBytes: Memory.activeMemory)
        let handle = SessionHandle(ChatSession(model, instructions: "Answer briefly.",
            generateParameters: .init(maxTokens: 1, temperature: 0, prefill: .init(stepSize: 64)),
            processing: .init(resize: nil, minPixels: 64 * 32 * 32, maxPixels: 64 * 32 * 32)))
        let image = CIImage(color: CIColor(red: 0.45, green: 0.5, blue: 0.55))
            .cropped(to: CGRect(x: 0, y: 0, width: 256, height: 256))
        do {
            for try await _ in handle.value.streamDetails(to: "Name the color.", images: [.ciImage(image)]) {
                try Task.checkCancellation()
                guard !releaseRequested else { throw CancellationError() }
            }
            await handle.synchronize()
            try Task.checkCancellation()
            guard !releaseRequested else { throw CancellationError() }
            visionWarmed = true
            warmups += 1
            Memory.cacheLimit = policy.cacheBytes
            Memory.clearCache()
        } catch {
            await handle.synchronize()
            releaseLoadedModel()
            throw error
        }
    }

    private func load() async throws -> ModelContainer {
        #if targetEnvironment(simulator)
        throw ModelRuntimeError.simulator
        #else
        if let container { return container }
        if let loadingTask { return try await loadingTask.value }
        guard FileManager.default.fileExists(atPath: directory.appending(path: "config.json").path) else {
            throw ModelRuntimeError.missingModel
        }
        let policy = RuntimePolicy.current()
        let required = 2_350 * RuntimePolicy.megabyte
        var admissionHeadroom = RuntimePolicy.processHeadroom
        if admissionHeadroom > 0 && admissionHeadroom <= required {
            // The CPU tokenizer is optional reusable state. Reclaim it before
            // refusing a cold load; it must never reserve budget against weights.
            tokenizerLoader.clearCache()
            admissionHeadroom = RuntimePolicy.processHeadroom
            recordMemory("load-reclaimed-metadata", policy: policy)
        }
        let headroom = admissionHeadroom
        recordMemory("load-admission", policy: policy)
        guard headroom == 0 || headroom > required else {
            throw ModelRuntimeError.insufficientMemory
        }
        // Cheap CPU headroom rejection precedes Metal device initialization.
        var admittedLimit = policy.safeMemoryLimit()
        if admittedLimit < required {
            tokenizerLoader.clearCache()
            admittedLimit = policy.safeMemoryLimit()
            recordMemory("load-reclaimed-metadata", policy: policy, workingLimit: admittedLimit)
        }
        let memoryLimit = admittedLimit
        recordMemory("load-limit", policy: policy, workingLimit: memoryLimit)
        guard memoryLimit >= required else {
            throw ModelRuntimeError.insufficientMemory
        }
        let directory = directory
        let tokenizerLoader = tokenizerLoader
        let task = Task.detached(priority: .userInitiated) {
            Memory.cacheLimit = policy.cacheBytes
            Memory.memoryLimit = memoryLimit
            return try await VLMModelFactory.shared.loadContainer(
                from: directory, using: tokenizerLoader)
        }
        loadingTask = task
        do {
            let model = try await task.value
            container = model
            modelLoads += 1
            loadingTask = nil
            return model
        } catch {
            loadingTask = nil
            Memory.clearCache()
            throw error
        }
        #endif
    }

    func generate(prompt: String, image: URL?, reset: Bool, task: ModelTask = .question,
                  receive: @Sendable @escaping (ModelEvent) async -> Void) async throws {
        let requestStarted = ContinuousClock.now
        guard !isGenerating else { throw ModelRuntimeError.busy }
        guard ProcessInfo.processInfo.thermalState != .critical else { throw ModelRuntimeError.thermal }
        try Task.checkCancellation()
        isGenerating = true
        defer {
            isGenerating = false
            if clearRequested {
                discardContext()
                questionTextCache.clear()
                clearRequested = false
            }
            if releaseRequested { releaseLoadedModel(); releaseRequested = false }
        }
        // Physical range is sensor evidence, never a plausible number from a VLM.
        // The app's paired-LiDAR path resolves and measures before reaching this
        // image-only question route; objectLocation remains a separate model task.
        if task == .question, DistanceQuestion.isDistance(prompt) {
            discardContext()
            var result = InferenceMetrics(profileName: RuntimePolicy.current().name)
            result.totalSeconds = seconds(requestStarted.duration(to: .now))
            await receive(.text(AnswerPolicy.imageOnlyDistanceAnswer(for: prompt)))
            await receive(.completed(result))
            return
        }
        let needsHistory = task == .question && AnswerPolicy.needsConversationContext(prompt)
        questionTextCache.retainOnly(image: image)
        let incompatible = reset || imageID != image || sessionTask != task || task != .question || !needsHistory
        if incompatible {
            await discardResidentSession()
            discardContext()
        }
        if task == .question, let image, let request = TargetedTextReading.Request.parse(prompt) {
            await discardResidentSession()
            let scan = try await scanQuestionText(image: image)
            let answer = TargetedTextReading.answer(to: request, scan: scan)
            try await recordStructuredAnswer(prompt: prompt, answer: answer, image: image, useTokenizer: false)
            try Task.checkCancellation()
            var result = InferenceMetrics(profileName: RuntimePolicy.current().name)
            result.totalSeconds = seconds(requestStarted.duration(to: .now))
            await receive(.text(answer))
            await receive(.completed(result))
            return
        }
        // OCR owns substantial Vision/image scratch. On compact devices it must
        // settle before cold-loading VLM weights. Its text-only result can outlive
        // those weights, and deterministic refusals need no VLM at all.
        let asksShape = task == .question && image != nil && ShapeAnswer.isQuestion(prompt)
        let printedKind = task == .question && image != nil && !asksShape
            ? PrintedFactKind.requested(by: prompt) : nil
        let aggregateFact = printedKind != nil && prompt.range(
            of: #"รวม|ทั้งหมด|\b(?:total|combined|sum)\b"#,
            options: [.regularExpression, .caseInsensitive]) != nil
        var questionScan: TextScan?
        if task == .question, let image, !asksShape, !aggregateFact, AnswerPolicy.needsTextEvidence(prompt) {
            questionScan = try await scanQuestionText(image: image)
        }
        if let kind = printedKind, let image, aggregateFact || questionScan == nil {
            let answer = kind.unavailable(for: prompt)
            try await recordStructuredAnswer(prompt: prompt, answer: answer, image: image)
            try Task.checkCancellation()
            var result = InferenceMetrics(profileName: RuntimePolicy.current().name)
            result.totalSeconds = seconds(requestStarted.duration(to: .now))
            await receive(.text(answer))
            await receive(.completed(result))
            return
        }
        try Task.checkCancellation()
        if container == nil { await receive(.loading) }
        let model = try await load()
        try Task.checkCancellation()
        await receive(.ready)
        let policy = RuntimePolicy.current(residentBytes: Memory.activeMemory)
        // Reclaim obsolete KV before admission. Cached image/turn state must not
        // reject a fresh request that fits after that state is released.
        Memory.cacheLimit = policy.cacheBytes
        Memory.clearCache()
        let args = ProcessInfo.processInfo.arguments
        let diagnosticCap = args.contains("--validate-memory") ? args.firstIndex(of: "--memory-working-cap-mib").flatMap { index in
            args.indices.contains(index + 1) ? Int(args[index + 1]) : nil
        } : nil
        func admittedLimit() -> Int {
            let base = policy.safeMemoryLimit(residentBytes: Memory.activeMemory)
            return diagnosticCap.map { min(base, max(1, min(8_192, $0)) * RuntimePolicy.megabyte) } ?? base
        }
        var workingLimit = admittedLimit()
        recordMemory("generation-admission", policy: policy, workingLimit: workingLimit)
        if workingLimit < Memory.activeMemory + 256 * RuntimePolicy.megabyte, session != nil {
            await discardResidentSession()
            Memory.clearCache()
            workingLimit = admittedLimit()
            recordMemory("generation-reclaimed-admission", policy: policy, workingLimit: workingLimit)
        }
        try Task.checkCancellation()
        guard workingLimit >= Memory.activeMemory + 256 * RuntimePolicy.megabyte else {
            recordMemory("generation-admission-refused", policy: policy, workingLimit: workingLimit)
            throw ModelRuntimeError.insufficientMemory
        }
        Memory.memoryLimit = workingLimit
        recordMemory("generation-context-ready", policy: policy, workingLimit: workingLimit)
        if task == .question, let image, ShapeAnswer.isQuestion(prompt) {
            Memory.peakMemory = 0
            let output = try await structuredResponse(prompt: conversation.referencePrompt(for: prompt), image: image, task: .shape,
                                                      model: model, policy: policy)
            diagnostic?("[shape evidence] \(prompt): \(output)")
            try Task.checkCancellation()
            var result = InferenceMetrics(profileName: policy.name)
            result.totalSeconds = seconds(requestStarted.duration(to: .now))
            result.peakMemoryBytes = Memory.peakMemory
            let extent = CIImage(contentsOf: image, options: [.applyOrientationProperty: true])?.extent
            let aspect = extent.map { Double($0.width / $0.height) } ?? .nan
            let answer = ShapeAnswer.answer(from: output, question: prompt, imageAspectRatio: aspect)
            try await recordStructuredAnswer(prompt: prompt, answer: answer, image: image, model: model)
            try Task.checkCancellation()
            await receive(.text(answer))
            await receive(.completed(result))
            return
        }
        let parameters = AnswerPolicy.parameters(for: policy, seed: seed, task: task)
        let imageBudget = image != nil ? policy.maxPixels / (32 * 32) : 0
        let instructions = AnswerPolicy.instructions(for: task)
        let instructionBudget = await model.perform { $0.tokenizer.encode(text: instructions).count }
        var preparedPrompt = prompt
        if task == .question, let image, AnswerPolicy.needsTextEvidence(prompt) {
            let scan = questionScan
            if let kind = PrintedFactKind.requested(by: prompt) {
                    Memory.peakMemory = 0
                    let answer: String
                    if let scan {
                        answer = try await printedFactAnswer(question: prompt, image: image,
                            scan: scan, kind: kind, model: model, policy: policy)
                    } else { answer = kind.unavailable(for: prompt) }
                    try Task.checkCancellation()
                    try await recordStructuredAnswer(prompt: prompt, answer: answer, image: image, model: model)
                    try Task.checkCancellation()
                    var result = InferenceMetrics(profileName: policy.name)
                    result.totalSeconds = seconds(requestStarted.duration(to: .now))
                    result.peakMemoryBytes = Memory.peakMemory
                    await receive(.text(answer))
                    await receive(.completed(result))
                    return
            }
            if let scan {
                let available = policy.maxContextTokens - imageBudget - instructionBudget
                    - (parameters.maxTokens ?? AnswerPolicy.maxTokens) - ConversationContext.templateReserve
                let originalTokens = await model.perform { $0.tokenizer.encode(text: prompt).count }
                let tokenBudget = min(available, originalTokens + 600)
                var selected: [TextSource] = []
                for source in scan.sources.prefix(8) {
                    let candidate = AnswerPolicy.textEvidencePrompt(question: prompt, sources: selected + [source])
                    let count = await model.perform { $0.tokenizer.encode(text: candidate).count }
                    guard count <= tokenBudget else { continue }
                    selected.append(source)
                }
                if !selected.isEmpty {
                    preparedPrompt = AnswerPolicy.textEvidencePrompt(question: prompt, sources: selected)
                }
            }
        }
        try Task.checkCancellation()
        let modelPrompt = preparedPrompt
        let promptCount = await model.perform { $0.tokenizer.encode(text: modelPrompt).count }
        let start = requestStarted
        var firstToken = 0.0
        var metrics = InferenceMetrics(profileName: policy.name)
        Memory.peakMemory = 0
        // Short answers are held until validated. A failed attempt therefore never
        // flashes repeated sentences or a cut fragment into the conversation.
        for attempt in 0...1 {
            let retry = attempt > 0
            let retryInstruction = retry ? "\nGive one very short, complete answer. Stop immediately after answering. Do not repeat any phrase." : ""
            let currentInstructions = instructions + retryInstruction
            let extraInstructionTokens = retry ? 40 : 0
            let wasExistingSession = session != nil
            guard let plan = conversation.plan(
                currentTokens: contextTokens, promptTokens: promptCount,
                imageTokens: imageBudget, instructionTokens: instructionBudget + extraInstructionTokens,
                answerTokens: parameters.maxTokens ?? AnswerPolicy.maxTokens,
                limit: policy.maxContextTokens,
                forceRebuild: session == nil || retry || sessionProfile != policy,
                retainHistory: needsHistory && !retry
            ) else {
                throw task == .summary ? ModelRuntimeError.documentTooLong : ModelRuntimeError.contextFull
            }
            if plan.rebuild {
                if wasExistingSession { metrics.contextReset = true }
                let history: [Chat.Message] = plan.history.flatMap {
                    [.user($0.prompt), .assistant($0.answer)]
                }
                session = SessionHandle(ChatSession(
                    model, instructions: currentInstructions, history: history,
                    generateParameters: parameters,
                    processing: .init(resize: nil, minPixels: 64 * 32 * 32, maxPixels: policy.maxPixels)))
                imageID = image
                sessionProfile = policy
                sessionTask = task
                contextTokens = 0
                conversation.didRebuild(retaining: plan.history)
            }
            guard let activeSession = session else { throw ModelRuntimeError.missingModel }
            activeSession.value.generateParameters = parameters
            var output = ""
            var repetition = ResponseRepetitionGuard.StreamChecker(question: task == .summary ? "summarize document" : prompt)
            var repeated = false
            var reachedTokenLimit = false
            do {
                for try await event in activeSession.value.streamDetails(
                    to: modelPrompt, images: plan.rebuild ? image.map { [.url($0)] } ?? [] : []) {
                    try Task.checkCancellation()
                    if let chunk = event.chunk {
                        if firstToken == 0 { firstToken = seconds(start.duration(to: .now)) }
                        output += chunk
                        if !task.isStructured, repetition.append(chunk) {
                            repeated = true
                            break
                        }
                    }
                    if let info = event.info {
                        metrics.tokensPerSecond = info.tokensPerSecond.isFinite ? info.tokensPerSecond : 0
                        metrics.generatedTokens = info.generationTokenCount
                        contextTokens = info.totalPromptTokenCount + info.generationTokenCount
                        reachedTokenLimit = info.stopReason == .length
                    }
                }
                try Task.checkCancellation()
                // Also waits for Metal after a guard breaks the stream's producer.
                await activeSession.synchronize()
            } catch {
                await activeSession.synchronize()
                // A cancelled/failed turn is never retained for a later question.
                discardContext()
                throw error
            }
            let decision = AnswerAttemptRecovery.decide(attempt: attempt, structured: task.isStructured,
                repeated: repeated, reachedLimit: reachedTokenLimit,
                empty: output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if decision != .accept {
                if repeated {
                    let rejectedText = output
                    metrics.generatedTokens = await model.perform { $0.tokenizer.encode(text: rejectedText).count }
                    let decodeSeconds = seconds(start.duration(to: .now)) - firstToken
                    metrics.tokensPerSecond = decodeSeconds > 0 ? Double(metrics.generatedTokens) / decodeSeconds : 0
                }
                metrics.stoppedForRepetition = metrics.stoppedForRepetition || repeated
                discardContext()
                if decision == .retryFresh {
                    metrics.retryCount = 1
                    metrics.contextReset = true
                    continue
                }
                if !task.isStructured {
                    output = "ยังสร้างคำตอบที่สมบูรณ์ไม่ได้ กรุณาถามให้เฉพาะเจาะจงขึ้น"
                    metrics.recoveryFailed = true
                } else {
                    // Parsers reject incomplete JSON; never append prose to tool output.
                    metrics.truncated = reachedTokenLimit
                }
            } else if task == .question {
                let acceptedAnswer = output
                let turnTokens = await model.perform {
                    $0.tokenizer.encode(text: prompt).count + $0.tokenizer.encode(text: acceptedAnswer).count + 32
                }
                do { try Task.checkCancellation() }
                catch { discardContext(); throw error }
                conversation.record(prompt: prompt, answer: output, tokenCount: turnTokens)
            }
            do { try Task.checkCancellation() }
            catch { discardContext(); throw error }
            metrics.contextTokens = contextTokens
            metrics.firstTokenSeconds = firstToken
            metrics.totalSeconds = seconds(start.duration(to: .now))
            metrics.peakMemoryBytes = Memory.peakMemory
            recordMemory("generation-completed", policy: policy, workingLimit: workingLimit)
            await receive(.text(output.trimmingCharacters(in: .whitespacesAndNewlines)))
            await receive(.completed(metrics))
            return
        }
    }

    /// Clears KV state and bounded conversational memory while keeping model weights warm.
    func clearContext() {
        recordMemory("clear-context-start")
        defer { recordMemory("clear-context-finished") }
        if isGenerating {
            clearRequested = true
        } else {
            discardContext()
            questionTextCache.clear()
        }
    }

    private func scanQuestionText(image: URL) async throws -> TextScan? {
        let key = try? QuestionTextCache.Key(image: image)
        if let key, let cached = questionTextCache.value(for: key) {
            recordMemory("question-ocr-cache-hit")
            return cached.scan
        }
        do {
            recordMemory("question-ocr-scan-start")
            let scan = try await textScanner(image)
            try Task.checkCancellation()
            recordMemory("question-ocr-scan-ready")
            if let key, key == (try? QuestionTextCache.Key(image: image)) {
                questionTextCache.store(.text(scan), for: key)
            }
            return scan
        } catch is CancellationError { throw CancellationError() }
        catch DocumentTextError.noText {
            if let key, key == (try? QuestionTextCache.Key(image: image)) {
                questionTextCache.store(.noText, for: key)
            }
            return nil
        } catch {
            // Preserve the existing visual fallback if text could not be read.
            return nil
        }
    }

    private func printedFactAnswer(question: String, image: URL, scan: TextScan, kind: PrintedFactKind,
                                   model: ModelContainer, policy: RuntimePolicy) async throws -> String {
        let aggregate = question.range(of: #"รวม|ทั้งหมด|\b(?:total|combined|sum)\b"#,
                                       options: [.regularExpression, .caseInsensitive]) != nil
        guard !aggregate else { return kind.unavailable(for: question) }
        let locate = """
            Locate the ONE visible object or printed item requested by the question.
            For a menu price, tightly box only the named menu item's printed line, not the entire menu.
            For a bottle's volume or price, box that bottle. For shop hours, box the hours sign.
            Question: \(conversation.referencePrompt(for: question))
            Return the required object-location JSON only. If not unique or not visible, return not_found or ambiguous.
            """
        let location = try await structuredResponse(prompt: locate, image: image,
            task: .objectLocation, model: model, policy: policy)
        diagnostic?("[printed-fact location] \(question): \(location)")
        guard let target = try? ObjectGroundingResponse.parse(location),
              let source = PrintedFactEvidence.source(for: target, in: scan.sources) else { return kind.unavailable(for: question) }
        diagnostic?("[printed-fact source] \(source.id): \(source.text)")
        let extraction = """
            Requested kind: \(kind.rawValue)
            User question: \(question)
            ONE visually located OCR source follows. Values from any other source are forbidden.
            \(AnswerPolicy.textEvidencePrompt(question: question, sources: [source]))
            Return only the required fact JSON with an exact printed line and printed numeric value.
            """
        let response = try await structuredResponse(prompt: extraction, image: nil,
            task: .textFacts, model: model, policy: policy)
        diagnostic?("[printed-fact quote] \(response)")
        return PrintedFactEvidence.answer(from: response, kind: kind, source: source, target: target,
                                          question: question) ?? kind.unavailable(for: question)
    }

    /// Internal structured calls share the admitted model but own disposable KV
    /// state. They do not re-enter the public generation gate or chat history.
    private func structuredResponse(prompt: String, image: URL?, task: ModelTask,
                                    model: ModelContainer, policy: RuntimePolicy) async throws -> String {
        let instructions = AnswerPolicy.instructions(for: task)
        let tokens = await model.perform { $0.tokenizer.encode(text: instructions + prompt).count }
        guard tokens + (image == nil ? 0 : policy.maxPixels / (32 * 32)) + 256 < policy.maxContextTokens
        else { throw ModelRuntimeError.documentTooLong }
        let handle = SessionHandle(ChatSession(model, instructions: instructions,
            generateParameters: AnswerPolicy.parameters(for: policy, seed: seed, task: task),
            processing: .init(resize: nil, minPixels: 64 * 32 * 32, maxPixels: policy.maxPixels)))
        var output = ""
        var truncated = false
        do {
            for try await event in handle.value.streamDetails(to: prompt, images: image.map { [.url($0)] } ?? []) {
                try Task.checkCancellation()
                if let chunk = event.chunk { output += chunk }
                if let info = event.info { truncated = info.stopReason == .length }
            }
            await handle.synchronize()
            try Task.checkCancellation()
            return truncated ? "" : output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            await handle.synchronize()
            throw error
        }
    }

    /// All callers own the generation/cleanup gate while awaiting the session.
    /// Keep only the app's tiny text ledger and image identity for a later rebuild.
    private func discardResidentSession() async {
        let previous = session
        session = nil
        sessionProfile = nil
        contextTokens = 0
        await previous?.synchronize()
        await previous?.clear()
    }

    /// Free large weights while preserving references in a same-photo follow-up.
    /// Destructive clear/background requests that arrive during the await win.
    func releaseWeightsPreservingConversation() async {
        guard !isGenerating, loadingTask == nil, container != nil || session != nil else { return }
        isGenerating = true
        let savedConversation = conversation
        let savedImage = imageID
        let savedTask = sessionTask
        await discardResidentSession()
        releaseLoadedModel(preservingReusableState: !clearRequested && !releaseRequested)
        if !clearRequested && !releaseRequested {
            conversation = savedConversation
            imageID = savedImage
            sessionTask = savedTask
        }
        clearRequested = false
        releaseRequested = false
        isGenerating = false
        recordMemory("idle-weights-released")
    }

    private func discardContext() {
        session = nil
        imageID = nil
        sessionProfile = nil
        contextTokens = 0
        conversation.clear()
    }

    /// Keep accepted user-facing turns while disposing of the internal tools' KV
    /// state, so a subsequent pronoun can refer to the same object.
    private func recordStructuredAnswer(prompt: String, answer: String, image: URL,
                                        model: ModelContainer? = nil, useTokenizer: Bool = true) async throws {
        let count: Int
        if let model {
            count = await model.perform {
                $0.tokenizer.encode(text: prompt).count + $0.tokenizer.encode(text: answer).count + 32
            }
        } else if useTokenizer, let tokenizer = try? await tokenizerLoader.load(from: directory) {
            count = tokenizer.encode(text: prompt).count + tokenizer.encode(text: answer).count + 32
        } else {
            // UTF-8 bytes conservatively bound byte-level BPE tokens, including
            // deterministic OCR requests that should never open model assets.
            count = prompt.utf8.count + answer.utf8.count + 32
        }
        try Task.checkCancellation()
        session = nil
        sessionProfile = nil
        imageID = image
        sessionTask = .question
        contextTokens = 0
        conversation.record(prompt: prompt, answer: answer, tokenCount: count)
    }

    func release() async {
        guard !isGenerating else { releaseRequested = true; return }
        questionTextCache.clear()
        tokenizerLoader.clearCache()
        // An empty runtime owns no GPU buffers. In particular, do not initialize Metal
        // just to clear a cache on the Simulator or after model admission was refused.
        guard container != nil || loadingTask != nil || session != nil else {
            discardContext()
            return
        }
        if let loadingTask {
            _ = try? await loadingTask.value
            self.loadingTask = nil
        }
        releaseLoadedModel()
    }

    private func releaseLoadedModel(preservingReusableState: Bool = false) {
        discardContext()
        if !preservingReusableState {
            questionTextCache.clear()
            tokenizerLoader.clearCache()
        }
        let hadContainer = container != nil
        container = nil
        if hadContainer { Memory.clearCache() }
    }

    private struct RuntimeMemoryEvent: Codable {
        let phase: String
        let timestamp: Date
        let memory: MemoryTelemetry
        let contextTokens: Int
        let retainedTextTurns: Int
        let hasImageIdentity: Bool
        let hasSession: Bool
        let modelLoaded: Bool
        let modelLoads: Int
        let policyMemoryBytes: Int?
        let workingLimit: Int?
    }

    private func recordMemory(_ phase: String, policy: RuntimePolicy? = nil, workingLimit: Int? = nil) {
        guard ProcessInfo.processInfo.arguments.contains("--validate-memory") else { return }
        memoryEvents.append(.init(phase: phase, timestamp: Date(), memory: .current(),
                                  contextTokens: contextTokens, retainedTextTurns: conversation.recent.count,
                                  hasImageIdentity: imageID != nil, hasSession: session != nil,
                                  modelLoaded: container != nil, modelLoads: modelLoads,
                                  policyMemoryBytes: policy?.memoryBytes, workingLimit: workingLimit))
        if memoryEvents.count > 512 { memoryEvents.removeFirst(memoryEvents.count - 512) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(memoryEvents).write(to: URL.documentsDirectory.appending(path: "MemoryRuntimeCheck.json"), options: .atomic)
    }

    private func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
