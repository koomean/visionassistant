import Foundation
import os
@preconcurrency import WhisperKit

/// Whole-operation stages. Callbacks must not wait for the main actor: Core ML
/// may still be compiling when the screen cancels the question.
enum LocalSpeechStage: String, Codable, Sendable {
    case preparingAudio, loadingTokenizer, loadingModel, warmingModel, transcribing, releasingModel

    var message: String {
        switch self {
        case .preparingAudio: "กำลังเตรียมเสียง…"
        case .loadingTokenizer: "กำลังเตรียมภาษาไทย / English…"
        case .loadingModel: "กำลังเตรียมโมเดลเสียงบนเครื่อง…"
        case .warmingModel: "กำลังเตรียมระบบฟังเสียงให้พร้อม…"
        case .transcribing: "กำลังแปลงเสียงเป็นคำถาม…"
        case .releasingModel: "กำลังคืนหน่วยความจำโมเดลเสียง…"
        }
    }
}

/// Idle prepared models can remain resident; only actual work owns the global lease.
/// A cancelled noncooperative Core ML call keeps that lease until it really returns.
actor LocalSpeechDecoder {
    static let shared = LocalSpeechDecoder(preferGPU: ProcessInfo.processInfo.arguments.contains("--validate-speech-gpu"))
    private static let log = Logger(subsystem: "com.koomean.lunav", category: "SpeechPreparation")
    private let preferGPU: Bool
    private var preparationStarted = ContinuousClock.now
    private var preparationEvents: [PreparationEvent] = []
    private var isDecoding = false
    private var releaseRequested = false
    private var kit: WhisperKit?
    private var modelFolder: URL?
    private var modelsLoaded = false
    private var warmed = false
    private var modelLoads = 0
    private var warmups = 0
    private var cacheHits = 0
    private nonisolated static let workLease = LocalSpeechWorkLease()
    nonisolated static var isWorking: Bool { workLease.isWorking }
    private(set) var lastSegments: [LocalSpeechSegmentQuality] = []
    nonisolated static let cameraVocabulary = "ภาพ กล้อง วัตถุ ระยะห่าง อยู่ห่าง ห่างจาก ขวดน้ำ ป้าย อ่าน อ่านข้อความ สรุป ข้อความ ไทย อังกฤษ Photo camera object distance bottle sign read summarize text Thai English."

    /// The launch flag isolates Core ML backend validation on an actual phone.
    /// Ordinary callers keep the existing Neural Engine configuration.
    init(preferGPU: Bool = false) { self.preferGPU = preferGPU }

    private struct PreparationEvent: Codable {
        let stage: String
        let timestamp: Date
        let elapsedSeconds: Double
        let availableBytes: Int?
        let physicalBytes: UInt64
        let errorDomain: String?
        let errorCode: Int?
        let errorDescription: String?
    }

    private struct PreparationReport: Codable {
        let encoderCompute: String
        let decoderCompute: String
        let melCompute: String
        let validationGPU: Bool
        let processID: Int32
        let events: [PreparationEvent]
    }

    struct PreparationStats: Codable, Sendable {
        let modelLoads: Int
        let warmups: Int
        let cacheHits: Int
        let isPrepared: Bool
    }

    func preparationStats() -> PreparationStats {
        .init(modelLoads: modelLoads, warmups: warmups, cacheHits: cacheHits,
              isPrepared: modelsLoaded && warmed)
    }

    nonisolated static var bundledModelURL: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("WhisperLargeTurbo"),
              requiredFiles.allSatisfy({ FileManager.default.fileExists(atPath: url.appendingPathComponent($0).path) })
        else { return nil }
        return url
    }

    nonisolated static let requiredFiles = [
        "AudioEncoder.mlmodelc/weights/weight.bin", "MelSpectrogram.mlmodelc/coremldata.bin",
        "TextDecoder.mlmodelc/weights/weight.bin", "tokenizer.json", "tokenizer_config.json"
    ]

    /// Runs real mel/encoder/decoder work before the camera becomes ready. This
    /// never reads the microphone, downloads assets, or emits the synthetic result.
    func prepare(modelURL: URL? = nil, timeout: Duration = .seconds(180),
                 progress: (@Sendable (LocalSpeechStage) -> Void)? = nil) async throws {
        guard !isDecoding, Self.workLease.acquire() else { throw LocalSpeechDecoderError.busy }
        isDecoding = true
        defer { isDecoding = false; Self.workLease.release() }
        preparationStarted = .now
        preparationEvents = []
        recordPreparation("begin")
        let deadline = ContinuousClock.now.advanced(by: timeout)
        do {
            _ = try await preparedKit(modelURL: modelURL, warm: true, deadline: deadline, progress: progress)
            try check(deadline)
            if releaseRequested { throw CancellationError() }
        } catch {
            recordPreparation("error", error: error)
            await unloadPrepared()
            throw error
        }
    }

    /// Memory warnings and a low-memory VLM handoff must not wait for a stuck
    /// decoder. Its owner performs the deferred unload when Core ML returns.
    func releasePreparedModel() async {
        releaseRequested = true
        guard !isDecoding, Self.workLease.acquire() else { return }
        isDecoding = true
        defer { isDecoding = false; Self.workLease.release() }
        await unloadPrepared()
    }

    func transcribe(audioURL: URL, modelURL: URL? = nil,
                    contextPrompt: String? = LocalSpeechDecoder.cameraVocabulary,
                    timeout: Duration = .seconds(120),
                    progress: (@Sendable (LocalSpeechStage) -> Void)? = nil) async throws -> String {
        guard !isDecoding, Self.workLease.acquire() else { throw LocalSpeechDecoderError.busy }
        isDecoding = true
        defer { isDecoding = false; Self.workLease.release() }
        lastSegments = []
        // UI additionally races this entire operation against a nonjoining watchdog.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        do {
            try check(deadline)
            progress?(.preparingAudio)
            let rawAudio = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
            guard rawAudio.count <= LocalSpeechAudio.maximumSamples else {
                throw LocalSpeechDecoderError.recordingTooLong
            }
            guard let audio = LocalSpeechAudio.prepare(rawAudio) else { throw LocalSpeechDecoderError.noSpeech }
            let kit = try await preparedKit(modelURL: modelURL, warm: false, deadline: deadline, progress: progress)
            guard let adapter = kit.tokenizer else { throw LocalSpeechDecoderError.invalidTokenizer }
            let promptTokens = contextPrompt.map { adapter.encode(text: $0) }
            if let contextPrompt, let promptTokens,
               adapter.decode(tokens: promptTokens) != contextPrompt { throw LocalSpeechDecoderError.invalidTokenizer }
            try check(deadline)
            let decodingDeadline = min(deadline, clock.now.advanced(by: .seconds(75)))
            let options = DecodingOptions(
                task: .transcribe, language: nil, temperatureFallbackCount: 1,
                sampleLength: 448, usePrefillPrompt: true, detectLanguage: true,
                skipSpecialTokens: true, withoutTimestamps: true,
                windowClipTime: audio.count > 480_000 ? 0 : 1,
                promptTokens: promptTokens,
                suppressBlank: true, concurrentWorkerCount: 1
            )
            progress?(.transcribing)
            let stopSignal = LocalSpeechStopSignal()
            let results = try await withTaskCancellationHandler {
                try await kit.transcribe(audioArray: audio, decodeOptions: options) { _ in
                    stopSignal.isCancelled || clock.now >= decodingDeadline ? false : nil
                }
            } onCancel: { stopSignal.cancel() }
            lastSegments = results.flatMap(\.segments).map {
                LocalSpeechSegmentQuality(text: $0.text, averageLogProbability: $0.avgLogprob,
                                          compressionRatio: $0.compressionRatio, tokenCount: $0.tokens.count)
            }
            try check(deadline)
            guard clock.now < decodingDeadline else { throw LocalSpeechDecoderError.timedOut }
            guard LocalSpeechSegmentQuality.isReliable(lastSegments) else {
                throw LocalSpeechDecoderError.uncertainSpeech
            }
            let text = results.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw LocalSpeechDecoderError.noSpeech }
            warmed = true
            if releaseRequested {
                progress?(.releasingModel)
                await unloadPrepared()
            }
            try check(deadline)
            return text
        } catch {
            // Invalid/silent input does not damage an already prepared model.
            let inputFailure = [LocalSpeechDecoderError.noSpeech, .uncertainSpeech, .recordingTooLong]
                .contains { $0 == error as? LocalSpeechDecoderError }
            if releaseRequested || !inputFailure {
                progress?(.releasingModel)
                await unloadPrepared()
            }
            throw error
        }
    }

    private func check(_ deadline: ContinuousClock.Instant) throws {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw LocalSpeechDecoderError.timedOut }
    }

    private func preparedKit(modelURL: URL?, warm: Bool, deadline: ContinuousClock.Instant,
                             progress: (@Sendable (LocalSpeechStage) -> Void)?) async throws -> WhisperKit {
        try check(deadline)
        guard let folder = modelURL ?? Self.bundledModelURL,
              Self.requiredFiles.allSatisfy({ FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) })
        else { throw LocalSpeechDecoderError.missingAssets }
        if modelFolder != folder { await unloadPrepared(); kit = nil; modelFolder = nil }
        // Tokenizer parsing is strictly local. WhisperKit's network-capable
        // tokenizer fallback is never entered, including a warm reload.
        if kit == nil {
            progress?(.loadingTokenizer)
            recordPreparation("loadingTokenizer")
            let tokenizer = try await AutoTokenizerWrapper.from(modelFolder: folder)
            try check(deadline)
            let adapter = try LocalWhisperTokenizer(tokenizer)
            let value = try await WhisperKit(WhisperKitConfig(
                modelFolder: folder.path, tokenizerFolder: folder,
                computeOptions: ModelComputeOptions(melCompute: .cpuAndGPU,
                    audioEncoderCompute: preferGPU ? .cpuAndGPU : .cpuAndNeuralEngine,
                    textDecoderCompute: preferGPU ? .cpuAndGPU : .cpuAndNeuralEngine),
                verbose: false, prewarm: false, load: false, download: false
            ))
            value.tokenizer = adapter
            value.textDecoder.isModelMultilingual = true
            kit = value
            modelFolder = folder
            recordPreparation("tokenizer-ready")
        }
        guard let kit else { throw LocalSpeechDecoderError.missingAssets }
        do {
            if !modelsLoaded {
                progress?(.loadingModel)
                recordPreparation("loadingModel")
                try await kit.loadModels()
                modelsLoaded = true
                modelLoads += 1
                recordPreparation("model-ready")
            } else { cacheHits += 1 }
            try check(deadline)
            if warm && !warmed {
                progress?(.warmingModel)
                recordPreparation("warming")
                let stopSignal = LocalSpeechStopSignal()
                // One synthetic second goes through all three Core ML models;
                // a single decoder token is enough to specialize its kernels.
                let options = DecodingOptions(task: .transcribe, language: "en", temperatureFallbackCount: 0,
                    sampleLength: 1, usePrefillPrompt: true, detectLanguage: false,
                    skipSpecialTokens: true, withoutTimestamps: true, windowClipTime: 0,
                    suppressBlank: true, concurrentWorkerCount: 1)
                _ = try await withTaskCancellationHandler {
                    try await kit.transcribe(audioArray: Array(repeating: 0, count: 16_000), decodeOptions: options) { _ in
                        stopSignal.isCancelled || ContinuousClock.now >= deadline ? false : nil
                    }
                } onCancel: { stopSignal.cancel() }
                try check(deadline)
                warmed = true
                warmups += 1
                recordPreparation("warm-ready")
            }
            if releaseRequested { throw CancellationError() }
            return kit
        } catch {
            await unloadPrepared()
            throw error
        }
    }

    private func unloadPrepared() async {
        if let kit { await kit.unloadModels(); kit.clearState() }
        modelsLoaded = false
        warmed = false
        releaseRequested = false
        // Keep the small, file-only tokenizer adapter for the next load.
    }

    /// No audio, transcript, prompt, or model weights enter this local report.
    /// Persist each boundary before Core ML can enter a lengthy device compile.
    private func recordPreparation(_ stage: String, error: Error? = nil) {
        let duration = preparationStarted.duration(to: .now).components
        let elapsed = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        let failure = error.map { $0 as NSError }
        let availableBytes: Int?
        #if os(iOS)
        availableBytes = Int(os_proc_available_memory())
        #else
        availableBytes = nil
        #endif
        let event = PreparationEvent(stage: stage, timestamp: Date(), elapsedSeconds: elapsed,
            availableBytes: availableBytes, physicalBytes: ProcessInfo.processInfo.physicalMemory,
            errorDomain: failure?.domain, errorCode: failure?.code,
            errorDescription: failure?.localizedDescription)
        preparationEvents.append(event)
        if preparationEvents.count > 64 { preparationEvents.removeFirst(preparationEvents.count - 64) }
        let backend = preferGPU ? "cpuAndGPU" : "cpuAndNeuralEngine"
        Self.log.info("stage=\(stage, privacy: .public) compute=\(backend, privacy: .public) elapsed=\(elapsed) availableBytes=\(availableBytes ?? -1)")
        if let failure {
            Self.log.error("domain=\(failure.domain, privacy: .public) code=\(failure.code) error=\(failure.localizedDescription, privacy: .public)")
        }
        #if os(iOS)
        let report = PreparationReport(encoderCompute: backend, decoderCompute: backend,
            melCompute: "cpuAndGPU", validationGPU: preferGPU,
            processID: ProcessInfo.processInfo.processIdentifier, events: preparationEvents)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(report).write(to: URL.documentsDirectory.appending(path: "SpeechPreparationCheck.json"), options: .atomic)
        } catch {
            Self.log.error("Could not save speech preparation diagnostics: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }
}

/// Queryable without entering the decoder actor, including while MLModel.load is
/// suspended. The lock protects only this boolean, never Core ML or an await.
private final class LocalSpeechWorkLease: @unchecked Sendable {
    private let lock = NSLock()
    private var working = false
    var isWorking: Bool { lock.withLock { working } }
    func acquire() -> Bool {
        lock.withLock {
            guard !working else { return false }
            working = true
            return true
        }
    }
    func release() { lock.withLock { working = false } }
}

private final class LocalSpeechStopSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}

struct LocalSpeechSegmentQuality: Codable, Sendable {
    var text: String
    var averageLogProbability: Float
    var compressionRatio: Float
    var tokenCount: Int

    static func isReliable(_ segments: [Self]) -> Bool {
        // The SDK retries bad decoding but returns the final attempt even when
        // its threshold still fails. Never submit that exhausted fallback as a question.
        !segments.isEmpty && segments.allSatisfy {
            $0.averageLogProbability.isFinite && $0.averageLogProbability >= -1
                && $0.compressionRatio.isFinite && $0.compressionRatio <= 2.4
        }
    }
}

/// Preserve the first consonant and make quiet measurement-mode input audible to ASR.
/// WhisperKit processes longer recordings in successive 30-second windows; never
/// discard the end of a held question just to fit its first window.
enum LocalSpeechAudio {
    static let maximumSamples = 120 * 16_000

    /// Only frame statistics survive this scan; native ASR reads the original WAV.
    /// Keep the same Float operations/frame boundaries as the legacy audio gate.
    struct ValidationScan {
        private var peak: Float = 0
        private var energy: Float = 0
        private var crossings = 0
        private var frameCount = 0
        private var previous: Float = 0
        private var frames: [(rms: Float, crossings: Float)] = []

        mutating func observe(centered value: Float) {
            peak = max(peak, abs(value))
            energy += value * value
            if frameCount > 0, (value < 0) != (previous < 0) { crossings += 1 }
            previous = value
            frameCount += 1
            if frameCount == 320 {
                frames.append((sqrt(energy / 320), Float(crossings) / 319))
                energy = 0
                crossings = 0
                frameCount = 0
            }
        }

        var acceptsSpeech: Bool { peak >= 0.005 && LocalSpeechAudio.hasSpeechVariation(frames: frames) }
    }

    static func prepare(_ samples: [Float]) -> [Float]? {
        guard samples.count >= 4_800, samples.count <= maximumSamples,
              samples.allSatisfy(\.isFinite) else { return nil }
        let mean = samples.reduce(Float(0), +) / Float(samples.count)
        let centered = samples.map { $0 - mean }
        let peak = centered.reduce(Float(0)) { max($0, abs($1)) }
        guard peak >= 0.005 else { return nil }
        guard hasSpeechVariation(centered) else { return nil }
        let gain = max(1, min(12, 0.85 / peak))
        // Preserve the existing single-window case without forcing a full 30s
        // question into a second window solely for silence padding.
        let limit = centered.count <= 480_000 ? 480_000 : maximumSamples
        let padding = min(1_600, max(0, (limit - centered.count) / 2))
        var result = Array(repeating: Float(0), count: padding)
        result.append(contentsOf: centered.map { $0 * gain })
        result.append(contentsOf: Array(repeating: Float(0), count: padding))
        return result
    }

    /// Conservative exclusions for constant tones/fans and broadband noise.
    /// WhisperKit's noSpeechProb is currently hardcoded to zero, so an energy
    /// threshold by itself can turn audible non-speech into invented questions.
    private static func hasSpeechVariation(_ samples: [Float]) -> Bool {
        let frameSize = 320 // 20 ms at 16 kHz
        var frames: [(rms: Float, crossings: Float)] = []
        for start in stride(from: 0, through: samples.count - frameSize, by: frameSize) {
            var energy: Float = 0
            var crossings = 0
            for index in start..<(start + frameSize) {
                let value = samples[index]
                energy += value * value
                if index > start && (value < 0) != (samples[index - 1] < 0) { crossings += 1 }
            }
            frames.append((sqrt(energy / Float(frameSize)), Float(crossings) / Float(frameSize - 1)))
        }
        return hasSpeechVariation(frames: frames)
    }

    private static func hasSpeechVariation(frames: [(rms: Float, crossings: Float)]) -> Bool {
        guard let maximum = frames.map(\.rms).max(), maximum > 0 else { return false }
        let active = frames.filter { $0.rms > maximum * 0.1 }
        guard active.count >= 4 else { return false }
        let mean = active.reduce(Float(0)) { $0 + $1.rms } / Float(active.count)
        let variance = active.reduce(Float(0)) { $0 + ($1.rms - mean) * ($1.rms - mean) } / Float(active.count)
        let modulation = sqrt(variance) / mean
        let crossings = active.map(\.crossings).sorted()
        return modulation >= 0.06 && crossings[crossings.count / 2] < 0.35
    }
}

enum LocalSpeechDecoderError: LocalizedError, Equatable {
    case missingAssets, invalidTokenizer, busy, noSpeech, uncertainSpeech, timedOut, recordingTooLong
    var errorDescription: String? {
        switch self {
        case .missingAssets: "ไม่พบไฟล์โมเดลเสียงในแอพ กรุณา build พร้อม WhisperLargeTurbo"
        case .invalidTokenizer: "ไฟล์ tokenizer ของโมเดลเสียงไม่สมบูรณ์ กรุณา build แอพใหม่"
        case .busy: "กำลังถอดเสียงคำถามก่อนหน้า"
        case .noSpeech: "ถอดคำถามไม่ได้ ลองกดค้างแล้วพูดใหม่"
        case .uncertainSpeech: "เสียงคำถามไม่ชัดเจน ลองพูดใกล้ไมโครโฟนอีกครั้ง"
        case .timedOut: "ถอดเสียงนานเกินไป ลองถามเป็นประโยคสั้นลง"
        case .recordingTooLong: "คำถามยาวเกิน 2 นาที กรุณากดค้างแล้วถามให้สั้นลง"
        }
    }
}

/// Adapts a file-only tokenizer without entering WhisperKit's network-capable loader.
private struct LocalWhisperTokenizer: WhisperTokenizer {
    let tokenizer: TokenizerWrapper
    let specialTokens: SpecialTokens
    let allLanguageTokens: Set<Int>

    init(_ tokenizer: TokenizerWrapper) throws {
        self.tokenizer = tokenizer
        func required(_ name: String) throws -> Int {
            guard let value = tokenizer.convertTokenToId(name) else { throw LocalSpeechDecoderError.invalidTokenizer }
            return value
        }
        specialTokens = try SpecialTokens(
            endToken: required("<|endoftext|>"), englishToken: required("<|en|>"),
            noSpeechToken: required("<|nospeech|>"), noTimestampsToken: required("<|notimestamps|>"),
            specialTokenBegin: required("<|endoftext|>"), startOfPreviousToken: required("<|startofprev|>"),
            startOfTranscriptToken: required("<|startoftranscript|>"), timeTokenBegin: required("<|0.00|>"),
            transcribeToken: required("<|transcribe|>"), translateToken: required("<|translate|>"),
            whitespaceToken: required("Ġ")
        )
        allLanguageTokens = Set(Constants.languageCodes.compactMap { tokenizer.convertTokenToId("<|\($0)|>") })
        guard tokenizer.convertTokenToId("<|th|>") != nil else { throw LocalSpeechDecoderError.invalidTokenizer }
    }

    func encode(text: String) -> [Int] { tokenizer.encode(text: text, addSpecialTokens: false) }
    func decode(tokens: [Int]) -> String { tokenizer.decode(tokens: tokens) }
    func convertTokenToId(_ token: String) -> Int? { tokenizer.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { tokenizer.convertIdToToken(id) }

    func splitToWordTokens(tokenIds: [Int]) -> (words: [String], wordTokens: [[Int]]) {
        // Word timestamps are disabled. Keep Unicode byte pieces together if queried.
        var words: [String] = []
        var groups: [[Int]] = []
        var pending: [Int] = []
        for token in tokenIds {
            pending.append(token)
            let text = decode(tokens: pending)
            if !text.contains("\u{fffd}") {
                words.append(text)
                groups.append(pending)
                pending = []
            }
        }
        if !pending.isEmpty { words.append(decode(tokens: pending)); groups.append(pending) }
        return (words, groups)
    }
}
