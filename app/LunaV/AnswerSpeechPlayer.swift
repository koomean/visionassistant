import AVFoundation
import Foundation
import Observation

/// Metadata for installed Apple voices. Siri's voice selection is not exposed by
/// AVSpeechSynthesizer, so the app labels these as Apple system voices.
struct AnswerSpeechVoice: Identifiable, Equatable, Sendable {
    enum Quality: Int, Comparable, Sendable {
        case `default` = 1
        case enhanced = 2
        case premium = 3

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let id: String
    let name: String
    let language: String
    let quality: Quality

    var qualityLabel: String {
        switch quality {
        case .default: "มาตรฐาน"
        case .enhanced: "คุณภาพสูง"
        case .premium: "พรีเมียม"
        }
    }

    var label: String { "\(name) · \(qualityLabel)" }
}

struct AnswerSpeechRequest: Equatable, Sendable {
    /// An utterance token, separate from the answer ID used to prevent replay.
    let id: UUID
    let text: String
    let voiceID: String
}

enum AnswerSpeechEvent: Equatable, Sendable {
    case started(UUID)
    case finished(UUID)
    case cancelled(UUID)

    var requestID: UUID {
        switch self {
        case let .started(id), let .finished(id), let .cancelled(id): id
        }
    }
}

/// The driver owns synthesis and its private system-managed audio session. Tests
/// inject a driver that never opens audio hardware.
@MainActor
protocol AnswerSpeechDriving: AnyObject {
    var onEvent: (@MainActor (AnswerSpeechEvent) -> Void)? { get set }
    func speak(_ request: AnswerSpeechRequest) throws
    func stop()
}

@MainActor @Observable
final class AnswerSpeechPlayer {
    var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: Self.enabledKey)
            if !enabled { stop() }
            else if !isSpeaking { status = Self.readyStatus }
        }
    }

    /// nil follows the highest quality installed voice for the answer language.
    var selectedThaiVoiceID: String? {
        didSet {
            persist(selectedThaiVoiceID, forKey: Self.thaiVoiceKey)
            if oldValue != selectedThaiVoiceID { stop() }
        }
    }
    var selectedEnglishVoiceID: String? {
        didSet {
            persist(selectedEnglishVoiceID, forKey: Self.englishVoiceKey)
            if oldValue != selectedEnglishVoiceID { stop() }
        }
    }

    private(set) var isSpeaking = false
    private(set) var status: String
    private(set) var error: String?
    private(set) var lastPlaybackEvent: AnswerSpeechEvent?
    private(set) var lastVoiceID: String?
    private(set) var availableVoices: [AnswerSpeechVoice] = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let driver: any AnswerSpeechDriving
    @ObservationIgnored private let voiceProvider: @MainActor () -> [AnswerSpeechVoice]
    @ObservationIgnored private var seenAnswerIDs: Set<UUID> = []
    @ObservationIgnored private var answerIDOrder: [UUID] = []
    @ObservationIgnored private var currentRequestID: UUID?

    static let maximumRememberedAnswers = 256
    var rememberedAnswerCount: Int { seenAnswerIDs.count }

    private static let enabledKey = "answerSpeechEnabled"
    private static let thaiVoiceKey = "answerSpeechThaiVoiceID"
    private static let englishVoiceKey = "answerSpeechEnglishVoiceID"
    private static let readyStatus = "พร้อมอ่านคำตอบด้วยเสียง Apple"
    private static let disabledStatus = "ปิดการอ่านคำตอบ"

    init(defaults: UserDefaults = .standard,
         driver: (any AnswerSpeechDriving)? = nil,
         voiceProvider: @escaping @MainActor () -> [AnswerSpeechVoice] = {
             SystemAnswerSpeechDriver.installedVoices()
         }) {
        self.defaults = defaults
        self.driver = driver ?? SystemAnswerSpeechDriver()
        self.voiceProvider = voiceProvider
        let initialEnabled = defaults.object(forKey: Self.enabledKey) == nil
            ? true : defaults.bool(forKey: Self.enabledKey)
        enabled = initialEnabled
        selectedThaiVoiceID = defaults.string(forKey: Self.thaiVoiceKey)
        selectedEnglishVoiceID = defaults.string(forKey: Self.englishVoiceKey)
        status = initialEnabled ? Self.readyStatus : Self.disabledStatus
        self.driver.onEvent = { [weak self] event in self?.receive(event) }
        refreshVoices()
    }

    /// Enumerating installed voices is silent and does not request asset downloads.
    func prepare() { refreshVoices() }

    func refreshVoices() {
        var identifiers: Set<String> = []
        availableVoices = voiceProvider().filter { identifiers.insert($0.id).inserted }
            .sorted {
                if $0.language != $1.language { return $0.language < $1.language }
                if $0.quality != $1.quality { return $0.quality > $1.quality }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    /// Call only after the complete answer has been committed to the conversation.
    /// Repeated completion callbacks, including callbacks after Stop, never replay.
    func speak(_ text: String, id answerID: UUID) {
        guard seenAnswerIDs.insert(answerID).inserted else { return }
        answerIDOrder.append(answerID)
        if answerIDOrder.count > Self.maximumRememberedAnswers {
            seenAnswerIDs.remove(answerIDOrder.removeFirst())
        }
        guard enabled else { return }
        let spokenText = Self.spokenText(text)
        guard !spokenText.isEmpty else { return }

        stop()
        let language = Self.containsThai(spokenText) ? "th" : "en"
        guard let voice = preferredVoice(for: language) else {
            error = language == "th"
                ? "ไม่มีเสียงภาษาไทยที่ติดตั้งบนอุปกรณ์นี้"
                : "ไม่มีเสียงภาษาอังกฤษที่ติดตั้งบนอุปกรณ์นี้"
            status = "อ่านคำตอบด้วยเสียงไม่ได้"
            return
        }

        let request = AnswerSpeechRequest(id: UUID(), text: spokenText, voiceID: voice.id)
        currentRequestID = request.id
        lastVoiceID = voice.id
        isSpeaking = true
        status = "กำลังอ่านคำตอบ…"
        do {
            try driver.speak(request)
        } catch {
            guard currentRequestID == request.id else { return }
            currentRequestID = nil
            driver.stop()
            isSpeaking = false
            self.error = error.localizedDescription
            status = "อ่านคำตอบด้วยเสียงไม่ได้"
        }
    }

    /// Invalidates callbacks before stopping the synthesizer. The audio session is
    /// private to synthesis, so this never deactivates the recorder's shared session.
    func stop() {
        currentRequestID = nil
        lastPlaybackEvent = nil
        driver.stop()
        isSpeaking = false
        error = nil
        status = enabled ? Self.readyStatus : Self.disabledStatus
    }

    private func receive(_ event: AnswerSpeechEvent) {
        guard event.requestID == currentRequestID else { return }
        lastPlaybackEvent = event
        switch event {
        case .started:
            isSpeaking = true
        case .finished, .cancelled:
            currentRequestID = nil
            isSpeaking = false
            status = enabled ? Self.readyStatus : Self.disabledStatus
        }
    }

    private func preferredVoice(for language: String) -> AnswerSpeechVoice? {
        let candidates = availableVoices.filter { $0.language.split(separator: "-").first == Substring(language) }
        let selected = language == "th" ? selectedThaiVoiceID : selectedEnglishVoiceID
        if let selected, let voice = candidates.first(where: { $0.id == selected }) { return voice }
        let defaultRegion = language == "th" ? "th-TH" : "en-US"
        return candidates.sorted {
            if $0.quality != $1.quality { return $0.quality > $1.quality }
            if ($0.language == defaultRegion) != ($1.language == defaultRegion) {
                return $0.language == defaultRegion
            }
            return $0.id < $1.id
        }.first
    }

    private func persist(_ id: String?, forKey key: String) {
        if let id { defaults.set(id, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }

    private static func containsThai(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0E00...0x0E7F).contains($0.value) }
    }

    /// Remove presentation markers while preserving punctuation, numbers, inline
    /// code contents, and link labels that carry meaning in an answer.
    static func spokenText(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "\r\n", with: "\n")
        let replacements: [(String, String)] = [
            (#"(?m)^[ \t]*(```|~~~)[^\n]*$"#, ""),
            (#"!\[([^\]]*)\]\([^)]*\)"#, "$1"),
            (#"\[([^\]]+)\]\([^)]*\)"#, "$1"),
            (#"(?m)^[ \t]{0,3}#{1,6}[ \t]+"#, ""),
            (#"(?m)^[ \t]{0,3}>[ \t]?"#, ""),
            (#"(?m)^[ \t]*([-*_])[ \t]*(?:\1[ \t]*){2,}$"#, ""),
            (#"(?m)^[ \t]*[-+*][ \t]+"#, ""),
            (#"(?m)^[ \t]*[0-9]+[.)][ \t]+"#, ""),
            (#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#, "$2"),
            (#"(?<!\*)\*([^*\n]+)\*(?!\*)"#, "$1"),
            (#"(?<![\p{L}\p{N}_])_([^_\n]+)_(?![\p{L}\p{N}_])"#, "$1"),
            (#"`+([^`\n]+)`+"#, "$1"),
            (#"~~([^~\n]+)~~"#, "$1"),
            (#"[ \t]+"#, " "),
            (#"\n[ \t]*\n+"#, "\n\n")
        ]
        for (pattern, replacement) in replacements {
            result = result.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
private final class SystemAnswerSpeechDriver: NSObject, AnswerSpeechDriving, AVSpeechSynthesizerDelegate {
    var onEvent: (@MainActor (AnswerSpeechEvent) -> Void)?
    private let synthesizer = AVSpeechSynthesizer()
    private nonisolated let requests = AnswerSpeechRequestRegistry()

    override init() {
        super.init()
        // iOS owns a separate session and its interruption/mixing behavior. Never
        // change the shared AVAudioSession used by microphone capture here.
        synthesizer.usesApplicationAudioSession = false
        synthesizer.delegate = self
    }

    static func installedVoices() -> [AnswerSpeechVoice] {
        AVSpeechSynthesisVoice.speechVoices().compactMap { voice in
            // Provider extensions may use a service. Only installed Apple system
            // voices are eligible for LunaV's entirely on-device speech path.
            guard voice.identifier.hasPrefix("com.apple."),
                  !voice.voiceTraits.contains(.isNoveltyVoice),
                  !voice.voiceTraits.contains(.isPersonalVoice),
                  AVSpeechSynthesisVoice(identifier: voice.identifier) != nil,
                  ["th", "en"].contains(String(voice.language.split(separator: "-").first ?? "")) else {
                return nil
            }
            let quality = AnswerSpeechVoice.Quality(rawValue: voice.quality.rawValue) ?? .default
            return AnswerSpeechVoice(id: voice.identifier, name: voice.name,
                                     language: voice.language, quality: quality)
        }
    }

    func speak(_ request: AnswerSpeechRequest) throws {
        guard request.voiceID.hasPrefix("com.apple."),
              let voice = AVSpeechSynthesisVoice(identifier: request.voiceID),
              !voice.voiceTraits.contains(.isNoveltyVoice),
              !voice.voiceTraits.contains(.isPersonalVoice) else {
            throw AnswerSpeechDriverError.voiceUnavailable
        }
        let utterance = AVSpeechUtterance(string: request.text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        requests.register(ObjectIdentifier(utterance), requestID: request.id)
        synthesizer.speak(utterance)
    }

    func stop() {
        requests.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                      didStart utterance: AVSpeechUtterance) {
        guard let id = requests.requestID(for: ObjectIdentifier(utterance), removing: false) else { return }
        Task { @MainActor [weak self] in self?.onEvent?(.started(id)) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                      didFinish utterance: AVSpeechUtterance) {
        guard let id = requests.requestID(for: ObjectIdentifier(utterance), removing: true) else { return }
        Task { @MainActor [weak self] in self?.onEvent?(.finished(id)) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                      didCancel utterance: AVSpeechUtterance) {
        guard let id = requests.requestID(for: ObjectIdentifier(utterance), removing: true) else { return }
        Task { @MainActor [weak self] in self?.onEvent?(.cancelled(id)) }
    }
}

/// Delegate methods may arrive off the main actor. Capture the token while the
/// callback still retains its utterance, then send only that token to the actor.
/// The lock protects every access and prevents a delayed hop from confusing a
/// reused ObjectIdentifier with a newer utterance after Stop.
private final class AnswerSpeechRequestRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [ObjectIdentifier: UUID] = [:]

    func register(_ identity: ObjectIdentifier, requestID: UUID) {
        lock.withLock { requests[identity] = requestID }
    }

    func requestID(for identity: ObjectIdentifier, removing: Bool) -> UUID? {
        lock.withLock {
            if removing { return requests.removeValue(forKey: identity) }
            return requests[identity]
        }
    }

    func removeAll() {
        lock.withLock { requests.removeAll() }
    }
}

private enum AnswerSpeechDriverError: LocalizedError {
    case voiceUnavailable
    var errorDescription: String? { "เสียงที่เลือกไม่พร้อมใช้งานบนอุปกรณ์นี้" }
}
