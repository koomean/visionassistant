import Foundation

/// App-owned, bounded memory. Only complete accepted turns enter this ledger;
/// KV caches are disposable and may be rebuilt without retaining failed output.
struct ConversationContext: Sendable {
    struct Turn: Sendable, Equatable {
        let prompt: String
        let answer: String
        let tokenCount: Int
    }

    struct Plan: Sendable {
        let rebuild: Bool
        let history: [Turn]
        let estimatedTokens: Int
    }

    static let turnLimit = 4
    static let templateReserve = 96
    private(set) var recent: [Turn] = []
    private(set) var turnsInSession = 0

    /// Disposable structured calls still need the referent of a true follow-up.
    /// Earlier facts are never supplied to a standalone question.
    func referencePrompt(for question: String) -> String {
        guard AnswerPolicy.needsConversationContext(question), !recent.isEmpty else { return question }
        var selected: [Turn] = []
        var tokens = 0
        for turn in recent.reversed() {
            guard tokens + turn.tokenCount <= 384 else { break }
            selected.insert(turn, at: 0)
            tokens += turn.tokenCount
        }
        guard !selected.isEmpty else { return question }
        let context = selected.map { "User: \($0.prompt)\nAssistant: \($0.answer)" }.joined(separator: "\n")
        return """
            Recent dialogue, only to resolve the object referred to in the latest question.
            Verify all properties against the current photo or OCR; previous answers are not visual evidence.
            \(context)
            Latest question: \(question)
            """
    }

    func plan(currentTokens: Int, promptTokens: Int, imageTokens: Int,
              instructionTokens: Int, answerTokens: Int, limit: Int,
              forceRebuild: Bool, retainHistory: Bool) -> Plan? {
        let incremental = promptTokens + answerTokens + Self.templateReserve
        let rebuild = forceRebuild || turnsInSession >= Self.turnLimit
            || currentTokens + incremental > limit
        guard rebuild else {
            return Plan(rebuild: false, history: [], estimatedTokens: currentTokens + incremental)
        }
        let base = incremental + imageTokens + instructionTokens
        guard base <= limit else { return nil }
        let historyBudget = min(384, limit / 5, limit - base)
        var history: [Turn] = []
        var historyTokens = 0
        if retainHistory {
            for turn in recent.reversed() {
                guard history.count < 2, historyTokens + turn.tokenCount <= historyBudget else { break }
                history.insert(turn, at: 0)
                historyTokens += turn.tokenCount
            }
        }
        return Plan(rebuild: true, history: history, estimatedTokens: base + historyTokens)
    }

    mutating func didRebuild(retaining history: [Turn]) {
        recent = history
        turnsInSession = 0
    }

    mutating func record(prompt: String, answer: String, tokenCount: Int) {
        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        recent.append(.init(prompt: prompt, answer: answer, tokenCount: tokenCount))
        recent = Array(recent.suffix(2))
        turnsInSession += 1
    }

    mutating func clear() {
        recent.removeAll()
        turnsInSession = 0
    }
}

/// A finite recovery policy shared by production inference and fault-injection tests.
enum AnswerAttemptRecovery {
    enum Decision: Equatable { case accept, retryFresh, reject }

    static func decide(attempt: Int, structured: Bool, repeated: Bool,
                       reachedLimit: Bool, empty: Bool) -> Decision {
        guard repeated || reachedLimit || empty else { return .accept }
        return !structured && attempt == 0 ? .retryFresh : .reject
    }
}
