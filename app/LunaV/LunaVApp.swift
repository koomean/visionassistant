import SwiftUI

@main
struct LunaVApp: App {
    init() {
        #if DEBUG && targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(where: { $0.hasPrefix("--uitesting") }) {
            UserDefaults.standard.set(false, forKey: CameraQuestionPreference.reusePhotoKey)
            if !arguments.contains("--uitesting-preserve-ui-language") {
                UserDefaults.standard.set(AppLanguage.thai.rawValue, forKey: AppLanguage.storageKey)
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            CameraScreen().modifier(AppLanguagePresentation())
        }
    }
}

/// Update display copy without recreating the camera, chat, or model owners.
private struct AppLanguagePresentation: ViewModifier {
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.thai.rawValue

    func body(content: Content) -> some View {
        let language = AppLanguage(rawValue: languageCode) ?? .thai
        content.environment(\.appLanguage, language).environment(\.locale, language.locale)
    }
}
