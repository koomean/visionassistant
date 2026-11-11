import Foundation

/// Release information comes from the signed app's Info.plist, which is filled
/// from project.yml. The About screen must never maintain a second version.
enum AppMetadata {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    static let websiteURL = URL(string: "https://visionassistant.koomean.com/")!
    static let authorThai = "วชิรวิช ไกรพิณดากุล"
    static let authorEnglish = "Wachirawich kripindakul (koomean)"
}
