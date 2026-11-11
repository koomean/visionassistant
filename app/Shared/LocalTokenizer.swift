import Foundation
import CryptoKit
import MLXLMCommon
import Tokenizers

struct LocalTokenizerLoader: MLXLMCommon.TokenizerLoader {
    private let cache: LocalTokenizerCache
    private let makeTokenizer: @Sendable (URL) async throws -> any MLXLMCommon.Tokenizer

    init(cache: LocalTokenizerCache = .shared,
         makeTokenizer: @escaping @Sendable (URL) async throws -> any MLXLMCommon.Tokenizer = { directory in
             let tokenizer = try await AutoTokenizer.from(modelFolder: directory)
             return try LocalTokenizer(base: tokenizer, directory: directory)
         }) {
        self.cache = cache
        self.makeTokenizer = makeTokenizer
    }

    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        try await cache.load(from: directory, makeTokenizer: makeTokenizer)
    }

    func clearCache() { cache.clear() }
}

/// One CPU-only tokenizer survives weight eviction. Content hashes also detect a
/// replacement whose path, length and modification date were deliberately kept.
/// Hash in small chunks so checking the 11 MB vocabulary needs no second full copy.
struct LocalFileFingerprint: Equatable, Sendable {
    let digest: [UInt8]

    init(url: URL) throws {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 64 * 1_024), !data.isEmpty {
            hash.update(data: data)
        }
        digest = Array(hash.finalize())
    }
}

final class LocalTokenizerCache: @unchecked Sendable {
    static let shared = LocalTokenizerCache()

    private struct Key: Equatable, Sendable {
        let directory: URL
        let files: [LocalFileFingerprint?]

        init(directory: URL) throws {
            self.directory = directory.standardizedFileURL.resolvingSymlinksInPath()
            // The adapter requires tokenizer.json; the other files can affect the
            // upstream tokenizer/template and therefore belong in the same key.
            var files: [LocalFileFingerprint?] = [try .init(url: self.directory.appending(path: "tokenizer.json"))]
            for name in ["tokenizer_config.json", "config.json", "added_tokens.json", "special_tokens_map.json", "chat_template.jinja"] {
                let file = self.directory.appending(path: name)
                if FileManager.default.fileExists(atPath: file.path) {
                    files.append(try .init(url: file))
                } else { files.append(nil) }
            }
            self.files = files
        }
    }

    private struct Entry {
        let key: Key
        let id: UUID
        let task: Task<any MLXLMCommon.Tokenizer, Error>
    }

    private let lock = NSLock()
    private var entry: Entry?

    func load(from directory: URL,
              makeTokenizer: @escaping @Sendable (URL) async throws -> any MLXLMCommon.Tokenizer) async throws -> any MLXLMCommon.Tokenizer {
        try Task.checkCancellation()
        let key = try Key(directory: directory)
        let selected = lock.withLock {
            if let entry, entry.key == key { return entry }
            let next = Entry(key: key, id: UUID(), task: Task {
                let tokenizer = try await makeTokenizer(key.directory)
                // Every coalesced caller awaits this validation, including callers
                // that arrive while metadata/tokenizer parsing is still underway.
                guard key == (try Key(directory: key.directory)) else {
                    throw TokenizerError.mismatchedConfig("Tokenizer files changed while loading")
                }
                return tokenizer
            })
            entry = next
            return next
        }
        let tokenizer: any MLXLMCommon.Tokenizer
        do {
            tokenizer = try await selected.task.value
        } catch {
            // Only a failed shared load invalidates this entry. Cancellation of
            // one waiter must not evict a valid tokenizer used by other callers.
            lock.withLock { if entry?.id == selected.id { entry = nil } }
            throw error
        }
        try Task.checkCancellation()
        return tokenizer
    }

    func clear() {
        // An existing model can still use its tokenizer. Do not cancel a caller's
        // load or let a late completion repopulate the cleared cache.
        lock.withLock { entry = nil }
    }
}

private struct LocalTokenizer: MLXLMCommon.Tokenizer {
    let base: any Tokenizers.Tokenizer
    let split: NSRegularExpression
    let added: NSRegularExpression
    let specialIDs: [String: Int]

    init(base: any Tokenizers.Tokenizer, directory: URL) throws {
        self.base = base
        let data = try Data(contentsOf: directory.appendingPathComponent("tokenizer.json"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let pre = json?["pre_tokenizer"] as? [String: Any]
        let sequence = pre?["pretokenizers"] as? [[String: Any]]
        let first = sequence?.first
        let pattern = first?["pattern"] as? [String: String]
        let byteLevel = sequence?.last
        let normalizer = json?["normalizer"] as? [String: Any]
        let post = json?["post_processor"] as? [String: Any]
        let configData = try Data(contentsOf: directory.appendingPathComponent("tokenizer_config.json"))
        let config = try JSONSerialization.jsonObject(with: configData) as? [String: Any]
        // This adapter is deliberately limited to the bundled Qwen tokenizer layout.
        guard sequence?.count == 2, first?["type"] as? String == "Split",
              first?["behavior"] as? String == "Isolated", first?["invert"] as? Bool == false,
              let regex = pattern?["Regex"], byteLevel?["type"] as? String == "ByteLevel",
              byteLevel?["use_regex"] as? Bool == false, byteLevel?["add_prefix_space"] as? Bool == false,
              normalizer?["type"] as? String == "NFC", post?["type"] as? String == "ByteLevel",
              post?["add_prefix_space"] as? Bool == false,
              config?["clean_up_tokenization_spaces"] as? Bool == false,
              let tokens = json?["added_tokens"] as? [[String: Any]],
              tokens.allSatisfy({ $0["lstrip"] as? Bool == false && $0["rstrip"] as? Bool == false }) else {
            throw TokenizerError.mismatchedConfig("Unsupported local tokenizer layout")
        }
        self.split = try NSRegularExpression(pattern: regex)
        self.specialIDs = Dictionary(uniqueKeysWithValues: tokens.compactMap {
            guard let content = $0["content"] as? String, let id = $0["id"] as? Int else { return nil }
            return (content, id)
        })
        self.added = try NSRegularExpression(pattern: specialIDs.keys.sorted {
            $0.utf16.count > $1.utf16.count
        }.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|"))
    }

    var bosToken: String? { base.bosToken }
    var eosToken: String? { base.eosToken }
    var unknownToken: String? { base.unknownToken }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        // swift-transformers 1.3.5 splits Swift graphemes at regex scalar boundaries.
        // Thai vowel/tone marks need NSString's UTF-16 slicing before byte-level BPE.
        let normalized = text.precomposedStringWithCanonicalMapping as NSString
        var ids: [Int] = []
        var cursor = 0
        func encodeOrdinary(_ range: NSRange) {
            guard range.length > 0 else { return }
            let piece = normalized.substring(with: range) as NSString
            var start = 0
            for match in split.matches(in: piece as String, range: NSRange(location: 0, length: piece.length)) {
                if match.range.location > start {
                    ids += base.encode(text: piece.substring(with: NSRange(location: start, length: match.range.location - start)), addSpecialTokens: false)
                }
                ids += base.encode(text: piece.substring(with: match.range), addSpecialTokens: false)
                start = NSMaxRange(match.range)
            }
            if start < piece.length {
                ids += base.encode(text: piece.substring(from: start), addSpecialTokens: false)
            }
        }
        for match in added.matches(in: normalized as String, range: NSRange(location: 0, length: normalized.length)) {
            encodeOrdinary(NSRange(location: cursor, length: match.range.location - cursor))
            if let id = specialIDs[normalized.substring(with: match.range)] { ids.append(id) }
            cursor = NSMaxRange(match.range)
        }
        encodeOrdinary(NSRange(location: cursor, length: normalized.length - cursor))
        // The validated ByteLevel postprocessor adds no BOS/EOS, for either flag.
        return ids
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        base.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }
    func convertTokenToId(_ token: String) -> Int? { base.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { base.convertIdToToken(id) }

    func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
                           additionalContext: [String: any Sendable]?) throws -> [Int] {
        // Keep upstream Jinja/tool/image formatting. Its lossless decoder recovers the
        // rendered text, which then goes through the scalar-safe encoding path above.
        let renderedIDs = try base.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        return encode(text: base.decode(tokens: renderedIDs, skipSpecialTokens: false), addSpecialTokens: false)
    }
}
