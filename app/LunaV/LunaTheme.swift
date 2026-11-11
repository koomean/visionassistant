import SwiftUI

/// Shared with website/styles.css. Keep the camera image untouched; colour only
/// the surrounding interface, controls and reading surfaces.
enum LunaTheme {
    static let night = colour(0x080F20)
    static let deep = colour(0x0C162C)
    static let paper = colour(0xF2F0E9)
    static let muted = colour(0xA5AFC3)
    static let faint = colour(0x75849F)
    static let blue = colour(0xA7BDED)
    static let gold = colour(0xDAC7A0)
    static let danger = colour(0xEE625B)
    static let line = colour(0xB4C6E9).opacity(0.15)

    static func font(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        let size: CGFloat
        switch style {
        case .largeTitle: size = 34
        case .title: size = 28
        case .title2: size = 22
        case .title3: size = 20
        case .headline, .body: size = 17
        case .callout: size = 16
        case .subheadline: size = 15
        case .footnote: size = 13
        case .caption: size = 12
        case .caption2: size = 11
        @unknown default: size = 17
        }
        return .custom("NotoSansThai-Regular", size: size, relativeTo: style).weight(weight)
    }

    static func brandFont(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        // The website's 650-weight wordmark is baked into this static instance.
        .custom("LunaVBrand-Regular", fixedSize: size)
    }

    private static func colour(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

struct LunaBrandLockup: View {
    var markSize: CGFloat = 30
    var wordmarkSize: CGFloat = 25

    var body: some View {
        HStack(spacing: 10) {
            Image("IntroMoon").resizable().scaledToFit()
                .frame(width: markSize, height: markSize)
            Text("\(Text("LunaV").foregroundColor(LunaTheme.paper))\(Text(".").foregroundColor(LunaTheme.gold))")
                .font(LunaTheme.brandFont(size: wordmarkSize))
                .tracking(-wordmarkSize * 0.06)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("LunaV")
    }
}

/// Launch animation is an independent, finite overlay. It never gates the task
/// that prepares models; only user interaction waits for its visual handoff.
enum LunaLaunchPolicy {
    static func showsIntroduction(arguments: [String]) -> Bool {
        if arguments.contains(where: { $0.hasPrefix("--validate-") }) { return false }
        if arguments.contains("--uitesting-show-intro") { return true }
        return !arguments.contains(where: { $0.hasPrefix("--uitesting") })
    }
}

/// Translate the app's generated source headings while keeping recognized
/// text and the source headings sent to the model in their original language.
extension AppLanguage {
    func regionLabel(_ region: PhotoRegion) -> String {
        region.label.components(separatedBy: " · ").map { text($0) }.joined(separator: " · ")
    }

    func sourceTitle(_ source: TextSource) -> String {
        "\(text(source.kind.title)) \(source.id + 1) · \(regionLabel(source.region))"
    }

    /// Historical messages keep their generated source heading as a string.
    /// Recognize only the app's kind/number/position format; never rewrite OCR.
    func sourceTitle(_ storedTitle: String) -> String {
        let components = storedTitle.components(separatedBy: " · ")
        guard let heading = components.first else { return storedTitle }
        let kinds: [TextSourceKind] = [.sign, .menu, .bottleLabel, .packageLabel, .document, .screen, .other]
        for kind in kinds {
            let prefix = kind.title + " "
            guard heading.hasPrefix(prefix) else { continue }
            let identifier = String(heading.dropFirst(prefix.count))
            guard !identifier.isEmpty,
                  identifier.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { continue }
            let localizedHeading = text(kind.title) + " " + identifier
            return ([localizedHeading] + components.dropFirst().map { text($0) }).joined(separator: " · ")
        }
        return storedTitle
    }
}
