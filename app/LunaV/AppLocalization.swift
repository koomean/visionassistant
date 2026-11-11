import Foundation
import SwiftUI

/// Display language is deliberately independent of Dictation, answer prompts,
/// and the voices selected for spoken answers.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case thai = "th"
    case english = "en"

    static let storageKey = "lunav.ui.language"
    var id: String { rawValue }
    var name: String { self == .thai ? "ภาษาไทย" : "English" }
    var locale: Locale { Locale(identifier: rawValue) }

    func text(_ source: String) -> String {
        self == .thai ? source : UIStrings.english(source)
    }
}

private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .thai
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}

/// Translates app-owned display copy only. Never pass questions, answers, OCR,
/// prompts, or stored model data here. Dynamic source strings remain unchanged
/// in their owners; only their rendered labels use this catalog.
enum UIStrings {
    static let englishTranslations: [String: String] = {
        guard let directory = Bundle.main.url(forResource: "en", withExtension: "lproj"),
              let data = try? Data(contentsOf: directory.appendingPathComponent("Localizable.strings")),
              let value = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let strings = value as? [String: String] else { return [:] }
        return strings
    }()

    private static let formatSpecifier = try! NSRegularExpression(
        pattern: #"%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|ll|[hlLzjt])?[@diuoxXfFeEgGsc]"#)

    private struct Template: Sendable {
        let expression: NSRegularExpression
        let translation: String
        let argumentPositions: [Int]
    }

    private static let templates: [Template] = englishTranslations.keys
        .filter { $0.contains("%") && $0.unicodeScalars.contains { (0x0E00...0x0E7F).contains($0.value) } }
        .sorted { $0.count > $1.count }
        .compactMap { key in
            let source = key as NSString
            let fields = formatSpecifier.matches(in: key, range: NSRange(location: 0, length: source.length))
            guard !fields.isEmpty, let translation = englishTranslations[key] else { return nil }
            var pattern = "^"
            var end = 0
            var positions: [Int] = []
            for (index, field) in fields.enumerated() {
                pattern += NSRegularExpression.escapedPattern(for: source.substring(with: NSRange(location: end, length: field.range.location - end)))
                pattern += "(.*?)"
                let position = field.range(at: 1)
                positions.append(position.location == NSNotFound ? index + 1 : Int(source.substring(with: position)) ?? index + 1)
                end = NSMaxRange(field.range)
            }
            pattern += NSRegularExpression.escapedPattern(for: source.substring(from: end)) + "$"
            guard let expression = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else { return nil }
            return Template(expression: expression, translation: translation, argumentPositions: positions)
        }

    static func english(_ source: String) -> String { english(source, depth: 0) }

    private static func english(_ source: String, depth: Int) -> String {
        guard !source.isEmpty, depth < 5 else { return source }
        if let exact = englishTranslations[source] { return exact }
        guard source.unicodeScalars.contains(where: { (0x0E00...0x0E7F).contains($0.value) }) else { return source }
        let value = source as NSString
        let range = NSRange(location: 0, length: value.length)
        for template in templates {
            guard let match = template.expression.firstMatch(in: source, range: range) else { continue }
            var arguments: [Int: String] = [:]
            for (index, position) in template.argumentPositions.enumerated() {
                arguments[position] = english(value.substring(with: match.range(at: index + 1)), depth: depth + 1)
            }
            let translated = template.translation as NSString
            let fields = formatSpecifier.matches(in: template.translation, range: NSRange(location: 0, length: translated.length))
            var result = ""
            var end = 0
            for (index, field) in fields.enumerated() {
                result += translated.substring(with: NSRange(location: end, length: field.range.location - end))
                let numbered = field.range(at: 1)
                let position = numbered.location == NSNotFound ? index + 1 : Int(translated.substring(with: numbered)) ?? index + 1
                result += arguments[position] ?? translated.substring(with: field.range)
                end = NSMaxRange(field.range)
            }
            return result + translated.substring(from: end)
        }
        // These separators join app-owned statuses and positional labels. Exact
        // catalog/template matching is applied to each component, never words.
        for separator in [" · ", "\n"] where source.contains(separator) {
            return source.components(separatedBy: separator)
                .map { english($0, depth: depth + 1) }.joined(separator: separator)
        }
        return source
    }
}
