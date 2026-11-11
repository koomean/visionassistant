import SwiftUI

struct TextSourcesSheet: View {
    @Bindable var chat: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("แตะกลุ่มที่ต้องการอ่านหรือสรุป").font(LunaTheme.font(.headline))
                    if let analysis = chat.sourceAnalysis, let photo = chat.photo {
                        SourceMap(photo: photo, sources: analysis.sources, selected: chat.activeSourceID) { source in
                            chat.selectSource(source); dismiss()
                        }.aspectRatio(photo.size, contentMode: .fit)
                        ForEach(analysis.sources) { source in
                            Button {
                                chat.selectSource(source); dismiss()
                            } label: {
                                HStack(alignment: .top, spacing: 14) {
                                    Text("\(source.id + 1)").font(LunaTheme.font(.headline).monospacedDigit())
                                        .frame(width: 32, height: 32).background(LunaTheme.gold.opacity(0.18), in: .circle)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(verbatim: appLanguage.sourceTitle(source)).font(LunaTheme.font(.headline))
                                        Text(verbatim: source.text).font(LunaTheme.font(.subheadline)).lineLimit(3).foregroundStyle(LunaTheme.muted)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(LunaTheme.font(.caption))
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                            }.buttonStyle(.plain).accessibilityIdentifier("textSource_\(source.id)")
                            Divider()
                        }
                        if let note = analysis.classificationNote {
                            Text(appLanguage.text(note)).font(LunaTheme.font(.footnote)).foregroundStyle(LunaTheme.muted)
                        }
                    } else if chat.isWorking {
                        ProgressView(appLanguage.text(chat.status)).frame(maxWidth: .infinity).padding(.vertical, 60)
                        Button("หยุด") { chat.stop() }.frame(maxWidth: .infinity)
                    } else if let error = chat.error {
                        Text(appLanguage.text(error)).foregroundStyle(LunaTheme.danger)
                        Button("ลองแยกข้อความอีกครั้ง") { chat.discoverSources() }
                    }
                    Text("หากกรอบรวมข้อความคนละชิ้น ใช้เลือกพื้นที่เพื่อลากกรอบแก้ได้")
                        .font(LunaTheme.font(.footnote)).foregroundStyle(LunaTheme.muted)
                }.padding(20)
            }
            .foldAwareReadable()
            .background(LunaTheme.night)
            .navigationTitle("ข้อความแต่ละจุด").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(LunaTheme.night, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { dismiss() } }
            }
        }
        .task { chat.discoverSources() }
        .onDisappear { if chat.isDiscoveringSources { chat.stop() } }
        .font(LunaTheme.font(.body))
        .foregroundStyle(LunaTheme.paper)
        .tint(LunaTheme.gold).preferredColorScheme(.dark)
    }
}

private struct SourceMap: View {
    let photo: UIImage
    let sources: [TextSource]
    let selected: Int?
    let choose: (TextSource) -> Void
    @Environment(\.appLanguage) private var appLanguage
    var body: some View {
        GeometryReader { geometry in
            Image(uiImage: photo).resizable()
                .overlay(alignment: .topLeading) {
                    ForEach(sources) { source in
                        let rect = source.region.rect
                        Button { choose(source) } label: {
                            Rectangle().fill(LunaTheme.gold.opacity(source.id == selected ? 0.25 : 0.06))
                                .overlay { Rectangle().stroke(LunaTheme.gold, lineWidth: 1.5) }
                                .overlay(alignment: .topLeading) {
                                    Text("\(source.id + 1)").font(LunaTheme.font(.caption).bold()).foregroundStyle(LunaTheme.night)
                                        .padding(4).background(LunaTheme.gold)
                                }
                        }.buttonStyle(.plain)
                            .frame(width: max(24, rect.width * geometry.size.width), height: max(24, rect.height * geometry.size.height))
                            .offset(x: rect.minX * geometry.size.width, y: rect.minY * geometry.size.height)
                            .accessibilityLabel(appLanguage.sourceTitle(source))
                            .accessibilityIdentifier("sourceMap_\(source.id)")
                    }
                }
        }
    }
}
