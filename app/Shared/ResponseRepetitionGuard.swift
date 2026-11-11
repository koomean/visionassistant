import Foundation

/// A final safety net for clause loops. It does not synthesize or paraphrase answers.
enum ResponseRepetitionGuard {
    /// The same predicate at each delivered chunk boundary, with normalization
    /// performed only for new scalars. Boolean checks need no raw-text index map
    /// and never allocate the trimmed answer used by the final-output API.
    struct StreamChecker {
        private let isLiteral: Bool
        private var scalars: [Unicode.Scalar] = [" "]
        private var previousWasSpace = true

        init(question: String) { isLiteral = ResponseRepetitionGuard.isLiteralRequest(question) }

        mutating func append(_ chunk: String) -> Bool {
            guard !isLiteral else { return false }
            for scalar in chunk.unicodeScalars {
                let isSpace = scalar.properties.isWhitespace || CharacterSet.punctuationCharacters.contains(scalar)
                if isSpace && previousWasSpace { continue }
                scalars.append(isSpace ? " " : scalar)
                previousWasSpace = isSpace
            }
            return ResponseRepetitionGuard.repeatedTail(in: scalars, requiresClauseBoundary: false) != nil
        }
    }

    static func containsLoop(in text: String, question: String) -> Bool {
        checkedLoop(in: text, question: question, requiresClauseBoundary: false) != nil
    }

    static func trimmedLoop(in text: String, question: String) -> String? {
        checkedLoop(in: text, question: question, requiresClauseBoundary: true)
    }

    private static func checkedLoop(in text: String, question: String, requiresClauseBoundary: Bool) -> String? {
        // Text in an image may legitimately contain repeated lines; preserve transcription.
        guard !isLiteralRequest(question) else { return nil }

        let raw = text.unicodeScalars
        // A virtual leading separator makes the first clause match later clauses
        // even when only those later clauses have a leading space/newline.
        var scalars: [Unicode.Scalar] = [" "]
        var rawEnds: [String.UnicodeScalarView.Index] = [raw.startIndex]
        var previousWasSpace = true
        for index in raw.indices {
            let scalar = raw[index]
            let isSpace = scalar.properties.isWhitespace || CharacterSet.punctuationCharacters.contains(scalar)
            if isSpace && previousWasSpace { continue }
            scalars.append(isSpace ? " " : scalar)
            rawEnds.append(raw.index(after: index))
            previousWasSpace = isSpace
        }
        guard let repetition = repeatedTail(in: scalars, requiresClauseBoundary: requiresClauseBoundary) else { return nil }
        var end = repetition.end - 2 * repetition.period
        // Once a loop is proven, retain a single copy rather than another repeated pair.
        while let duplicate = repeatedSuffix(in: scalars, end: end, copies: 2) {
            end -= duplicate
        }
        guard end > 0 else { return nil }
        return String(raw[..<rawEnds[end - 1]]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isLiteralRequest(_ question: String) -> Bool {
        let literalRequests = ["อ่านข้อความ", "อ่านตัวอักษร", "ถอดข้อความ", "คัดลอก", "ocr", "transcribe", "read the text"]
        return literalRequests.contains(where: { question.localizedCaseInsensitiveContains($0) })
    }

    private static func repeatedTail(in scalars: [Unicode.Scalar], requiresClauseBoundary: Bool) -> (end: Int, period: Int)? {
        // Streaming can end partway through a fourth copy. Accept that tail only
        // when it exactly matches the beginning of the already proven clause.
        let maximumTail = min(255, scalars.count / 4)
        for tailLength in 0...maximumTail {
            let end = scalars.count - tailLength
            guard let period = repeatedSuffix(in: scalars, end: end, copies: 3,
                requiresClauseBoundary: requiresClauseBoundary), tailLength < period else { continue }
            let unitStart = end - period
            guard scalars[end...].elementsEqual(scalars[unitStart..<(unitStart + tailLength)]) else { continue }
            return (end, period)
        }
        return nil
    }

    private static func repeatedSuffix(in scalars: [Unicode.Scalar], end: Int, copies: Int,
                                       requiresClauseBoundary: Bool = false) -> Int? {
        let maximum = min(256, end / copies)
        guard maximum >= 4 else { return nil }
        for period in stride(from: maximum, through: 4, by: -1) {
            let start = end - copies * period
            if requiresClauseBoundary {
                // Thai has no word separators: detect such cycles, but only
                // extract a clause when its beginning is actually known.
                guard start <= 1 || scalars[start].properties.isWhitespace
                    || scalars[start - 1].properties.isWhitespace else { continue }
            }
            let tail = scalars[(end - period)..<end]
            guard (1..<copies).allSatisfy({ copy in
                scalars[(end - (copy + 1) * period)..<(end - copy * period)].elementsEqual(tail)
            }), Set(tail.filter { !$0.properties.isWhitespace }).count >= 3 else { continue }
            return period
        }
        return nil
    }
}
