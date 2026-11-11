import SwiftUI

struct RegionSelectionSheet: View {
    let photo: UIImage
    let confirm: (PhotoRegion) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage
    @State private var selection: PhotoRegion
    @State private var drawing: PhotoRegion?

    init(photo: UIImage, initial: PhotoRegion, confirm: @escaping (PhotoRegion) -> Void) {
        self.photo = photo
        self.confirm = confirm
        _selection = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            AdaptivePhotoToolsLayout {
                GeometryReader { geometry in
                    let scale = min(geometry.size.width / photo.size.width, geometry.size.height / photo.size.height)
                    let size = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
                    Image(uiImage: photo).resizable()
                        .frame(width: size.width, height: size.height)
                        .overlay { selectionOverlay(size: size) }
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }.padding(16)
            } tools: {
                ScrollView {
                    VStack(spacing: 16) {
                        Text("ลากกรอบรอบข้อความที่ต้องการ")
                            .font(LunaTheme.font(.headline))
                        Text("แอพจะอ่านหรือสรุปเฉพาะในกรอบนี้")
                            .font(LunaTheme.font(.subheadline)).foregroundStyle(LunaTheme.muted)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                            preset("ทั้งภาพ", region: .full, id: "regionFull")
                            preset("ส่วนบน", region: .init(rect: CGRect(x: 0, y: 0, width: 1, height: 0.5)), id: "regionTop")
                            preset("ตรงกลาง", region: .init(rect: CGRect(x: 0, y: 0.25, width: 1, height: 0.5)), id: "regionMiddle")
                            preset("ส่วนล่าง", region: .init(rect: CGRect(x: 0, y: 0.5, width: 1, height: 0.5)), id: "regionBottom")
                        }
                        Text(appLanguage.text("เลือกแล้ว: \(appLanguage.regionLabel(drawing ?? selection))"))
                            .font(LunaTheme.font(.subheadline)).foregroundStyle(LunaTheme.muted)
                            .accessibilityIdentifier("selectedRegionLabel")
                    }
                    .multilineTextAlignment(.center)
                    .padding(16)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            .background(LunaTheme.night)
            .navigationTitle("เลือกพื้นที่ข้อความ").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(LunaTheme.night, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("ใช้พื้นที่นี้") { confirm(selection); dismiss() }
                        .fontWeight(.semibold).accessibilityIdentifier("confirmRegion")
                }
            }
        }.font(LunaTheme.font(.body))
        .foregroundStyle(LunaTheme.paper)
        .tint(LunaTheme.gold).preferredColorScheme(.dark)
    }

    private func preset(_ title: String, region: PhotoRegion, id: String) -> some View {
        Button(appLanguage.text(title)) { selection = region; drawing = nil }
            .font(LunaTheme.font(.subheadline)).buttonStyle(.bordered)
            .tint(selection == region ? LunaTheme.gold : LunaTheme.faint)
            .accessibilityIdentifier(id)
    }

    private func selectionOverlay(size: CGSize) -> some View {
        let region = drawing ?? selection
        let rect = CGRect(x: region.rect.minX * size.width, y: region.rect.minY * size.height,
                          width: region.rect.width * size.width, height: region.rect.height * size.height)
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(rect)
            }.fill(LunaTheme.night.opacity(0.6), style: FillStyle(eoFill: true))
            Rectangle().stroke(LunaTheme.gold, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

        }
        .frame(width: size.width, height: size.height)
        .contentShape(.rect)
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in drawing = PhotoRegion.drawn(from: value.startLocation, to: value.location, in: size) }
            .onEnded { value in
                if let region = PhotoRegion.drawn(from: value.startLocation, to: value.location, in: size) { selection = region }
                drawing = nil
            })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(appLanguage.text("ภาพสำหรับลากกรอบข้อความ"))
        .accessibilityHint(appLanguage.text("ใช้ปุ่มทั้งภาพ ส่วนบน ตรงกลาง หรือส่วนล่างแทนการลากได้"))
        .accessibilityIdentifier("regionCanvas")
    }
}

struct RegionThumbnail: View {
    let photo: UIImage
    let region: PhotoRegion
    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / photo.size.width, geometry.size.height / photo.size.height)
            let size = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
            Image(uiImage: photo).resizable().frame(width: size.width, height: size.height)
                .overlay(alignment: .topLeading) {
                    Rectangle().stroke(LunaTheme.gold, lineWidth: 1.5)
                        .frame(width: region.rect.width * size.width, height: region.rect.height * size.height)
                        .offset(x: region.rect.minX * size.width, y: region.rect.minY * size.height)
                }
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }.accessibilityHidden(true)
    }
}
