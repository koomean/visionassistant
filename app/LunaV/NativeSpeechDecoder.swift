import AVFoundation
import Foundation
import Speech

/// Each Apple dictation session has an explicit locale. Thai is the app default;
/// English is a separate choice, without assuming automatic language detection.
enum NativeSpeechLanguage: String, CaseIterable, Codable, Sendable {
    case thai, english

    var localeIdentifier: String {
        switch self {
        case .thai: "th-TH"
        case .english: "en-US"
        }
    }

    var label: String {
        switch self {
        case .thai: "ภาษาไทย"
        case .english: "English"
        }
    }
}

enum NativeSpeechStage: String, Sendable {
    case checkingAssets, downloadingAssets, warmingModel, preparingAudio, transcribing

    var message: String {
        switch self {
        case .checkingAssets: "กำลังตรวจสอบระบบฟังเสียงบนเครื่อง…"
        case .downloadingAssets: "กำลังดาวน์โหลดภาษาสำหรับการฟังเสียงบนเครื่อง…"
        case .warmingModel: "กำลังเตรียมระบบฟังเสียงบนเครื่องให้พร้อม…"
        case .preparingAudio: "กำลังเตรียมเสียง…"
        case .transcribing: "กำลังแปลงเสียงเป็นคำถามบนเครื่อง…"
        }
    }
}

struct NativeSpeechLanguageCapability: Codable, Sendable {
    let language: NativeSpeechLanguage
    let requestedLocale: String
    let resolvedLocale: String?
    let supported: Bool
    let installed: Bool
}

struct NativeSpeechCapabilityReport: Codable, Sendable {
    let timestamp: Date
    let operatingSystem: String
    let engine: String
    let speechTranscriberAvailable: Bool
    let languages: [NativeSpeechLanguageCapability]
}

struct NativeSpeechResultDiagnostics: Codable, Sendable {
    var resultCount = 0
    var finalResultCount = 0
    var allCharacterCount = 0
    var finalCharacterCount = 0
}

/// This caches installed/reserved asset metadata, never a transcriber or analyzer.
/// A fresh module is required for each finalized native recognition session.
struct NativeSpeechReadinessCache {
    private var entry: (language: NativeSpeechLanguage, locale: Locale)?

    mutating func select(_ language: NativeSpeechLanguage) {
        if entry?.language != language { entry = nil }
    }

    func verifiedLocale(for language: NativeSpeechLanguage) -> Locale? {
        entry?.language == language ? entry?.locale : nil
    }

    mutating func recordVerified(language: NativeSpeechLanguage, locale: Locale) {
        entry = (language, locale)
    }

    mutating func invalidate() { entry = nil }
}

/// Successful warmup belongs to the selected language in this process, rather
/// than to an idle analyzer. Asset checks and real session preparation stay live.
struct NativeSpeechWarmupState {
    private var warmedLanguage: NativeSpeechLanguage?

    mutating func select(_ language: NativeSpeechLanguage) {
        if warmedLanguage != language { warmedLanguage = nil }
    }

    func canSkipIdleWarmup(language: NativeSpeechLanguage, ephemeral: Bool) -> Bool {
        ephemeral && warmedLanguage == language
    }

    mutating func recordSuccess(language: NativeSpeechLanguage) { warmedLanguage = language }
    mutating func invalidate() { warmedLanguage = nil }
}

/// Native results revise an audio range rather than accumulating a transcript.
/// Keep the latest text for overlapping ranges and preserve native whitespace.
/// This helper does no recognition and can be tested with ordinary strings.
struct NativeSpeechTranscriptAccumulator: Sendable {
    private struct Piece: Sendable {
        let start: Double
        let end: Double
        let text: String
        let confidence: Double?
    }
    private var pieces: [Piece] = []

    mutating func update(text: String, startSeconds: Double, endSeconds: Double,
                         confidence: Double? = nil) {
        // Invalid native timestamps still contain useful text. Treat such a
        // result as an update of the whole utterance, rather than dropping it.
        let validRange = startSeconds.isFinite && endSeconds.isFinite && endSeconds >= startSeconds
        let start = validRange ? startSeconds : 0
        let end = validRange ? endSeconds : Double.greatestFiniteMagnitude
        pieces.removeAll { piece in
            let identical = abs(piece.start - start) < 1e-9 && abs(piece.end - end) < 1e-9
            let overlapping = min(piece.end, end) - max(piece.start, start) > 1e-9
            return identical || overlapping
        }
        if !text.isEmpty {
            pieces.append(.init(start: start, end: end, text: text, confidence: confidence))
            pieces.sort { $0.start < $1.start }
        }
    }

    var text: String {
        pieces.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var averageConfidence: Double? {
        let values = pieces.compactMap { piece -> (Double, Int)? in
            guard let confidence = piece.confidence, confidence.isFinite else { return nil }
            return (confidence, max(1, piece.text.count))
        }
        let weight = values.reduce(0) { $0 + $1.1 }
        guard weight > 0 else { return nil }
        return values.reduce(0) { $0 + $1.0 * Double($1.1) } / Double(weight)
    }
}

/// Public Apple dictation models run outside the app process. This decoder never
/// creates a network-capable SFSpeechRecognitionRequest or uses bundled Whisper.
/// Callers own a SpeechTask deadline, including while Apple's services respond.
actor NativeSpeechDecoder {
    static let shared = NativeSpeechDecoder()
    private nonisolated static let workLease = NativeSpeechWorkLease()
    nonisolated static var isWorking: Bool { workLease.isWorking }
    nonisolated static var detailedDiagnosticsRequested: Bool {
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--validate-") }
    }

    private var activeAnalyzer: SpeechAnalyzer?
    private var preparedSession: PreparedSession?
    private var activeDownloadProgress: Progress?
    private var cancellationGeneration = 0
    private var latestCapabilities: NativeSpeechCapabilityReport?
    private var assetStatusBeforeReservation: String?
    private var assetStatusAfterInstallation: String?
    private var assetStatusAfterReservation: String?
    private var assetInstallationRequested = false
    private var inputFrameCount: Int64?
    private var inputDurationSeconds: Double?
    private var inputSampleRate: Double?
    private var inputChannelCount: UInt32?
    private var consumedThroughSeconds: Double?
    private var usedPreparedAnalyzer = false
    private var usedCachedAssetMetadata = false
    private var skippedIdleWarmup = false
    private var readinessCache = NativeSpeechReadinessCache()
    private var warmupState = NativeSpeechWarmupState()

    private(set) var lastAverageConfidence: Double?
    private(set) var lastResultDiagnostics = NativeSpeechResultDiagnostics()

    private struct PreparedSession {
        let language: NativeSpeechLanguage
        let transcriber: DictationTranscriber
        let analyzer: SpeechAnalyzer
    }

    /// Reads device capabilities without downloading a model or accessing audio.
    nonisolated static func capabilityReport() async -> NativeSpeechCapabilityReport {
        let installed = await DictationTranscriber.installedLocales
        var languages: [NativeSpeechLanguageCapability] = []
        for language in NativeSpeechLanguage.allCases {
            let locale = await DictationTranscriber.supportedLocale(
                equivalentTo: Locale(identifier: language.localeIdentifier)
            )
            let identifier = locale?.identifier(.bcp47)
            languages.append(.init(
                language: language, requestedLocale: language.localeIdentifier,
                resolvedLocale: identifier, supported: locale != nil,
                installed: identifier.map { identifier in
                    installed.contains { $0.identifier(.bcp47) == identifier }
                } ?? false
            ))
        }
        return NativeSpeechCapabilityReport(
            timestamp: Date(), operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            engine: "SpeechAnalyzer.DictationTranscriber",
            speechTranscriberAvailable: SpeechTranscriber.isAvailable,
            languages: languages
        )
    }

    /// Downloads are permitted only during this explicit preparation step. Once
    /// installed, Apple's system-managed assets are reused for offline inference.
    func prepare(language: NativeSpeechLanguage = .thai, allowDownload: Bool = false,
                 progress: (@Sendable (NativeSpeechStage) -> Void)? = nil) async throws {
        guard Self.workLease.acquire() else { throw NativeSpeechDecoderError.busy }
        defer { Self.workLease.release() }
        let generation = cancellationGeneration
        let started = ContinuousClock.now
        // Explicit preparation/download is a fresh inventory check. Repeated
        // questions may reuse the verified reservation until selection/failure.
        readinessCache.invalidate()
        warmupState.select(language)
        resetInputDiagnostics()
        assetStatusBeforeReservation = nil
        assetStatusAfterInstallation = nil
        assetStatusAfterReservation = nil
        assetInstallationRequested = false
        do {
            try checkCancellation(generation)
            progress?(.checkingAssets)
            latestCapabilities = await Self.capabilityReport()
            try checkCancellation(generation)
            writeReport(phase: "checkingAssets", language: language, allowDownload: allowDownload,
                        started: started)
            let transcriber = try await preparedTranscriber(
                language: language, allowDownload: allowDownload,
                generation: generation, progress: progress
            )
            if assetInstallationRequested || assetStatusBeforeReservation != "installed" {
                warmupState.invalidate()
                await discardPreparedSession()
                try checkCancellation(generation)
                latestCapabilities = await Self.capabilityReport()
            }
            try checkCancellation(generation)
            let ephemeral = RuntimePolicy.prefersEphemeralModels
            skippedIdleWarmup = warmupState.canSkipIdleWarmup(language: language, ephemeral: ephemeral)
            if !skippedIdleWarmup, preparedSession?.language != language {
                await discardPreparedSession()
                try checkCancellation(generation)
                let analyzer = Self.makeAnalyzer(transcriber: transcriber)
                activeAnalyzer = analyzer
                defer { activeAnalyzer = nil }
                progress?(.warmingModel)
                writeReport(phase: "warmingModel", language: language,
                            allowDownload: allowDownload, started: started)
                let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                           channels: 1, interleaved: false)
                do {
                    try await withTaskCancellationHandler {
                        try Task.checkCancellation()
                        try await analyzer.prepareToAnalyze(in: format)
                    } onCancel: {
                        Task { await analyzer.cancelAndFinishNow() }
                    }
                    try checkCancellation(generation)
                    preparedSession = .init(language: language, transcriber: transcriber, analyzer: analyzer)
                } catch {
                    await analyzer.cancelAndFinishNow()
                    throw error
                }
            }
            if ephemeral || RuntimePolicy.prefersEphemeralModels { await discardPreparedSession() }
            try checkCancellation(generation)
            warmupState.recordSuccess(language: language)
            writeReport(phase: "ready", language: language, allowDownload: allowDownload,
                        started: started)
        } catch {
            readinessCache.invalidate()
            if !(error is CancellationError) { warmupState.invalidate() }
            await discardPreparedSession()
            writeReport(phase: "preparationFailed", language: language, allowDownload: allowDownload,
                        started: started, error: error)
            throw error
        }
    }

    /// Cancels native work while its owner retains the lease until cleanup ends.
    func cancel() async {
        cancellationGeneration &+= 1
        let analyzer = activeAnalyzer
        activeDownloadProgress?.cancel()
        await discardPreparedSession()
        await analyzer?.cancelAndFinishNow()
        await SpeechModels.endRetention()
    }

    private func discardPreparedSession() async {
        let previous = preparedSession
        preparedSession = nil
        await previous?.analyzer.cancelAndFinishNow()
    }

    private nonisolated static func makeAnalyzer(transcriber: DictationTranscriber) -> SpeechAnalyzer {
        SpeechAnalyzer(modules: [transcriber],
                       options: .init(priority: .userInitiated,
                                      modelRetention: RuntimePolicy.prefersEphemeralModels ? .whileInUse : .lingering))
    }

    /// Accepts the held microphone recording. Only installed local assets can be
    /// used here; a missing model produces an error instead of a cloud fallback.
    func transcribe(audioURL: URL, language: NativeSpeechLanguage = .thai,
                    progress: (@Sendable (NativeSpeechStage) -> Void)? = nil) async throws -> String {
        guard Self.workLease.acquire() else { throw NativeSpeechDecoderError.busy }
        defer { Self.workLease.release() }
        let generation = cancellationGeneration
        let started = ContinuousClock.now
        resetInputDiagnostics()
        do {
            try checkCancellation(generation)
            progress?(.preparingAudio)
            let audioFile = try AVAudioFile(forReading: audioURL)
            guard audioFile.length > 0, audioFile.processingFormat.sampleRate > 0 else {
                throw NativeSpeechDecoderError.noSpeech
            }
            let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
            inputFrameCount = audioFile.length
            inputDurationSeconds = duration
            inputSampleRate = audioFile.processingFormat.sampleRate
            inputChannelCount = audioFile.processingFormat.channelCount
            guard duration <= 120 else { throw NativeSpeechDecoderError.recordingTooLong }
            try NativeSpeechAudio.validate(audioFile)

            let transcriber: DictationTranscriber
            let analyzer: SpeechAnalyzer
            if let prepared = preparedSession, prepared.language == language {
                // Adopt the exact preheated analyzer once; a finished analyzer
                // cannot accept another recording after finalization.
                preparedSession = nil
                usedPreparedAnalyzer = true
                transcriber = prepared.transcriber
                analyzer = prepared.analyzer
            } else {
                await discardPreparedSession()
                try checkCancellation(generation)
                progress?(.checkingAssets)
                transcriber = try await preparedTranscriber(
                    language: language, allowDownload: false, generation: generation, progress: progress
                )
                try checkCancellation(generation)
                analyzer = Self.makeAnalyzer(transcriber: transcriber)
            }
            activeAnalyzer = analyzer
            defer { activeAnalyzer = nil }
            progress?(.transcribing)
            writeReport(phase: "transcribing", language: language, allowDownload: false, started: started)

            let output = try await withTaskCancellationHandler {
                let resultsTask = Task { try await Self.collectLatestResults(from: transcriber) }
                do {
                    try Task.checkCancellation()
                    // Preheat cold sessions explicitly, then use Apple's file
                    // analysis pattern with an awaited finalization barrier.
                    if !usedPreparedAnalyzer {
                        try await analyzer.prepareToAnalyze(in: audioFile.processingFormat)
                    }
                    guard let lastSample = try await analyzer.analyzeSequence(from: audioFile) else {
                        throw NativeSpeechDecoderError.noSpeech
                    }
                    let consumed = CMTimeGetSeconds(lastSample)
                    consumedThroughSeconds = consumed.isFinite ? consumed : nil
                    try await analyzer.finalizeAndFinish(through: lastSample)
                    return try await resultsTask.value
                } catch {
                    // Cancel the analyzer before any wait on the result task:
                    // its result sequence may still be waiting for finalization.
                    resultsTask.cancel()
                    await analyzer.cancelAndFinishNow()
                    throw error
                }
            } onCancel: {
                Task { await analyzer.cancelAndFinishNow() }
            }
            try checkCancellation(generation)
            lastResultDiagnostics = output.diagnostics
            guard !output.text.isEmpty else { throw NativeSpeechDecoderError.noSpeech }
            lastAverageConfidence = output.averageConfidence
            warmupState.recordSuccess(language: language)
            writeReport(phase: "transcribed", language: language, allowDownload: false,
                        started: started, characterCount: output.text.count,
                        confidence: output.averageConfidence)
            return output.text
        } catch {
            // An externally removed asset or native service failure must force
            // the next question to recheck inventory; never switch to a server.
            if !(error is CancellationError) {
                readinessCache.invalidate()
                warmupState.invalidate()
            }
            writeReport(phase: "transcriptionFailed", language: language, allowDownload: false,
                        started: started, error: error)
            throw error
        }
    }

    private func preparedTranscriber(language: NativeSpeechLanguage, allowDownload: Bool,
                                    generation: Int,
                                    progress: (@Sendable (NativeSpeechStage) -> Void)?) async throws -> DictationTranscriber {
        assetStatusBeforeReservation = nil
        assetStatusAfterInstallation = nil
        assetStatusAfterReservation = nil
        assetInstallationRequested = false
        try checkCancellation(generation)
        readinessCache.select(language)
        warmupState.select(language)
        let cachedLocale = allowDownload ? nil : readinessCache.verifiedLocale(for: language)
        let locale: Locale
        if let cachedLocale {
            locale = cachedLocale
        } else {
            guard let supported = await DictationTranscriber.supportedLocale(
                equivalentTo: Locale(identifier: language.localeIdentifier)
            ) else { throw NativeSpeechDecoderError.unsupportedLanguage(language) }
            locale = supported
        }
        try checkCancellation(generation)
        var preset = DictationTranscriber.Preset.shortDictation
        preset.attributeOptions.insert(.transcriptionConfidence)
        let transcriber = DictationTranscriber(locale: locale, preset: preset)
        if cachedLocale != nil {
            usedCachedAssetMetadata = true
            assetStatusBeforeReservation = "installed"
            assetStatusAfterReservation = "installed"
            return transcriber
        }
        let status = await AssetInventory.status(forModules: [transcriber])
        assetStatusBeforeReservation = Self.name(of: status)
        try checkCancellation(generation)
        guard status != .unsupported else {
            throw NativeSpeechDecoderError.unsupportedLanguage(language)
        }
        if status != .installed {
            guard allowDownload else { throw NativeSpeechDecoderError.missingAssets(language) }
            progress?(.downloadingAssets)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                assetInstallationRequested = true
                try checkCancellation(generation)
                let downloadProgress = request.progress
                activeDownloadProgress = downloadProgress
                defer { activeDownloadProgress = nil }
                try await withTaskCancellationHandler {
                    try Task.checkCancellation()
                    try await request.downloadAndInstall()
                } onCancel: { downloadProgress.cancel() }
            }
            try checkCancellation(generation)
            assetStatusAfterInstallation = Self.name(of: await AssetInventory.status(forModules: [transcriber]))
            try checkCancellation(generation)
        }
        // Reserving an already installed locale keeps it available to this app
        // and never requires creating a model installation request.
        try await AssetInventory.reserve(locale: locale)
        try checkCancellation(generation)
        let reservedStatus = await AssetInventory.status(forModules: [transcriber])
        assetStatusAfterReservation = Self.name(of: reservedStatus)
        guard reservedStatus == .installed else {
            throw NativeSpeechDecoderError.missingAssets(language)
        }
        try checkCancellation(generation)
        readinessCache.recordVerified(language: language, locale: locale)
        return transcriber
    }

    private nonisolated static func name(of status: AssetInventory.Status) -> String {
        switch status {
        case .unsupported: "unsupported"
        case .downloading: "downloading"
        case .supported: "supported"
        case .installed: "installed"
        @unknown default: "unknown"
        }
    }

    private func checkCancellation(_ generation: Int) throws {
        try Task.checkCancellation()
        guard generation == cancellationGeneration else { throw CancellationError() }
    }

    private func resetInputDiagnostics() {
        lastAverageConfidence = nil
        lastResultDiagnostics = .init()
        inputFrameCount = nil
        inputDurationSeconds = nil
        inputSampleRate = nil
        inputChannelCount = nil
        consumedThroughSeconds = nil
        usedPreparedAnalyzer = false
        usedCachedAssetMetadata = false
        skippedIdleWarmup = false
    }

    private struct TranscriptionOutput: Sendable {
        let text: String
        let averageConfidence: Double?
        let diagnostics: NativeSpeechResultDiagnostics
    }

    private nonisolated static func collectLatestResults(from transcriber: DictationTranscriber) async throws -> TranscriptionOutput {
        var transcript = NativeSpeechTranscriptAccumulator()
        var diagnostics = NativeSpeechResultDiagnostics()
        for try await result in transcriber.results {
            try Task.checkCancellation()
            diagnostics.resultCount += 1
            diagnostics.allCharacterCount += result.text.characters.count
            if result.isFinal {
                diagnostics.finalResultCount += 1
                diagnostics.finalCharacterCount += result.text.characters.count
            }
            var confidenceSum = 0.0
            var confidenceCount = 0
            for run in result.text.runs {
                if let confidence = run.transcriptionConfidence, confidence.isFinite {
                    confidenceSum += confidence
                    confidenceCount += 1
                }
            }
            transcript.update(
                text: String(result.text.characters),
                startSeconds: CMTimeGetSeconds(result.range.start),
                endSeconds: CMTimeGetSeconds(CMTimeRangeGetEnd(result.range)),
                confidence: confidenceCount > 0 ? confidenceSum / Double(confidenceCount) : nil
            )
        }
        // Some DictationTranscriber results remain isFinal=false even when the
        // analyzer has finalized. The caller awaits finalizeAndFinish before
        // consuming this completed sequence, making these latest revisions safe.
        return .init(text: transcript.text,
                     averageConfidence: transcript.averageConfidence,
                     diagnostics: diagnostics)
    }

    /// Metadata only: no recording paths, transcripts, contextual words, or error
    /// descriptions that could accidentally contain recognized user speech.
    private struct CheckReport: Codable {
        let timestamp: Date
        let capabilities: NativeSpeechCapabilityReport?
        let phase: String
        let selectedLanguage: NativeSpeechLanguage
        let allowAssetDownload: Bool
        let assetStatusBeforeReservation: String?
        let assetStatusAfterInstallation: String?
        let assetStatusAfterReservation: String?
        let assetInstallationRequested: Bool
        let inputFrameCount: Int64?
        let inputDurationSeconds: Double?
        let inputSampleRate: Double?
        let inputChannelCount: UInt32?
        let consumedThroughSeconds: Double?
        let usedPreparedAnalyzer: Bool
        let usedCachedAssetMetadata: Bool
        let skippedIdleWarmup: Bool
        let resultDiagnostics: NativeSpeechResultDiagnostics
        let elapsedSeconds: Double
        let characterCount: Int?
        let averageConfidence: Double?
        let errorDomain: String?
        let errorCode: Int?
    }

    private func writeReport(phase: String, language: NativeSpeechLanguage, allowDownload: Bool,
                             started: ContinuousClock.Instant, characterCount: Int? = nil,
                             confidence: Double? = nil, error: Error? = nil) {
        guard Self.detailedDiagnosticsRequested || error != nil || phase == "ready" || phase == "transcribed" else { return }
        let elapsed = started.duration(to: .now).components
        let nativeError = error as NSError?
        let report = CheckReport(
            timestamp: Date(), capabilities: latestCapabilities, phase: phase,
            selectedLanguage: language, allowAssetDownload: allowDownload,
            assetStatusBeforeReservation: assetStatusBeforeReservation,
            assetStatusAfterInstallation: assetStatusAfterInstallation,
            assetStatusAfterReservation: assetStatusAfterReservation,
            assetInstallationRequested: assetInstallationRequested,
            inputFrameCount: inputFrameCount, inputDurationSeconds: inputDurationSeconds,
            inputSampleRate: inputSampleRate, inputChannelCount: inputChannelCount,
            consumedThroughSeconds: consumedThroughSeconds,
            usedPreparedAnalyzer: usedPreparedAnalyzer, usedCachedAssetMetadata: usedCachedAssetMetadata,
            skippedIdleWarmup: skippedIdleWarmup,
            resultDiagnostics: lastResultDiagnostics,
            elapsedSeconds: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
            characterCount: characterCount, averageConfidence: confidence,
            errorDomain: nativeError?.domain, errorCode: nativeError?.code
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(report).write(
            to: URL.documentsDirectory.appending(path: "NativeSpeechCheck.json"), options: .atomic
        )
    }
}

enum NativeSpeechDecoderError: LocalizedError, Equatable {
    case busy
    case unsupportedLanguage(NativeSpeechLanguage)
    case missingAssets(NativeSpeechLanguage)
    case noSpeech
    case recordingTooLong

    var errorDescription: String? {
        switch self {
        case .busy: "กำลังถอดเสียงคำถามก่อนหน้า"
        case .unsupportedLanguage(let language):
            "อุปกรณ์นี้ยังไม่รองรับการถอดเสียง\(language.label)บนเครื่อง"
        case .missingAssets(let language):
            "ยังไม่ได้ติดตั้งโมเดลเสียง\(language.label)สำหรับถอดเสียงบนเครื่อง กรุณาเชื่อมต่ออินเทอร์เน็ตแล้วเตรียมระบบเสียงอีกครั้ง"
        case .noSpeech: "ถอดคำถามไม่ได้ ลองกดค้างแล้วพูดใหม่"
        case .recordingTooLong: "คำถามยาวเกิน 2 นาที กรุณากดค้างแล้วถามให้สั้นลง"
        }
    }
}

private final class NativeSpeechWorkLease: @unchecked Sendable {
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
