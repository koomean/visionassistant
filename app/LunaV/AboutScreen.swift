import SwiftUI

struct AboutScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack(spacing: 18) {
                    Image("BrandMark")
                        .resizable().scaledToFit()
                        .frame(width: 68, height: 68)
                        .accessibilityHidden(true)
                    Text("LunaV\(Text(".").foregroundColor(LunaTheme.gold))")
                        .font(LunaTheme.brandFont(size: 40))
                        .accessibilityLabel("LunaV")
                }
                .padding(.top, 12)

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(appLanguage.text("เวอร์ชันแอพ"))
                            .foregroundStyle(LunaTheme.muted)
                        Spacer(minLength: 16)
                        Text(verbatim: AppMetadata.version)
                            .font(LunaTheme.font(.title2, weight: .semibold))
                            .monospacedDigit()
                            .accessibilityIdentifier("aboutVersion")
                    }
                    Rectangle().fill(LunaTheme.line).frame(height: 1)
                    HStack {
                        Text("บิลด์").foregroundStyle(LunaTheme.muted)
                        Spacer(minLength: 16)
                        Text(verbatim: AppMetadata.buildNumber).monospacedDigit()
                            .accessibilityIdentifier("aboutBuild")
                    }
                    .font(LunaTheme.font(.footnote))
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LunaTheme.deep, in: .rect(cornerRadius: 20))
                .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(LunaTheme.line, lineWidth: 1) }

                VStack(alignment: .leading, spacing: 12) {
                    Text("จัดทำโดย")
                        .font(LunaTheme.font(.subheadline, weight: .medium))
                        .foregroundStyle(LunaTheme.gold)
                    // Proper names are kept exactly as supplied in either UI language.
                    Text(verbatim: AppMetadata.authorThai)
                        .font(LunaTheme.font(.title3, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("aboutAuthorThai")
                    Text(verbatim: AppMetadata.authorEnglish)
                        .font(LunaTheme.font(.body))
                        .foregroundStyle(LunaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("aboutAuthorEnglish")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Link(destination: AppMetadata.websiteURL) {
                        HStack(spacing: 12) {
                            Image(systemName: "safari")
                                .font(.system(size: 20, weight: .medium))
                                .accessibilityHidden(true)
                            Text("เว็บไซต์ของโปรแกรม")
                                .font(LunaTheme.font(.body, weight: .semibold))
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 14, weight: .semibold))
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 18)
                        .frame(minHeight: 54)
                        .foregroundStyle(LunaTheme.night)
                        .background(LunaTheme.gold, in: .rect(cornerRadius: 16))
                        .contentShape(.rect(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("openProgramWebsite")
                    .accessibilityHint("เปิดเว็บไซต์ LunaV ในเบราว์เซอร์")
                    Text(verbatim: AppMetadata.websiteURL.host ?? "visionassistant.koomean.com")
                        .font(LunaTheme.font(.footnote))
                        .foregroundStyle(LunaTheme.muted)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 32)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .foldAwareReadable()
        .background(LunaTheme.night)
        .foregroundStyle(LunaTheme.paper)
        .font(LunaTheme.font(.body))
        .tint(LunaTheme.gold)
        .navigationTitle("เกี่ยวกับ LunaV")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(LunaTheme.night, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("กลับ", systemImage: "chevron.left") { dismiss() }
                    .font(LunaTheme.font(.body))
                    .accessibilityIdentifier("closeAbout")
            }
        }
    }
}
