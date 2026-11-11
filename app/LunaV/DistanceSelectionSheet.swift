import SwiftUI

struct DistanceSelectionSheet: View {
    let photo: UIImage
    let depth: LiDARSnapshot
    let confirm: (CGPoint) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage
    @State private var point: CGPoint?

    init(photo: UIImage, depth: LiDARSnapshot, initialPoint: CGPoint?, confirm: @escaping (CGPoint) -> Void) {
        self.photo = photo
        self.depth = depth
        self.confirm = confirm
        _point = State(initialValue: initialPoint)
    }

    private var reading: LiDARMeasurement? {
        guard let point else { return nil }
        return try? LiDARRangeReader.measure(depth, at: point)
    }
    private var explanation: String {
        guard let point else { return "แตะตรงกลางพื้นผิวของวัตถุที่ต้องการวัด" }
        do {
            _ = try LiDARRangeReader.measure(depth, at: point)
            return depth.depthSource.isEstimated ? "ประมาณจากโมเดล ณ ตอนถ่ายภาพ · ค่าจริงอาจคลาดเคลื่อน" : "ระยะจากกล้อง ณ ตอนถ่ายภาพ"
        }
        catch { return error.localizedDescription }
    }

    var body: some View {
        NavigationStack {
            AdaptivePhotoToolsLayout {
                GeometryReader { geometry in
                    let scale = min(geometry.size.width / photo.size.width, geometry.size.height / photo.size.height)
                    let size = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
                    Image(uiImage: photo).resizable().frame(width: size.width, height: size.height)
                        .overlay {
                            if let point {
                                Circle().stroke(LunaTheme.gold, lineWidth: 2).frame(width: 26, height: 26)
                                    .overlay { Circle().fill(LunaTheme.gold).frame(width: 5, height: 5) }
                                    .position(x: point.x * size.width, y: point.y * size.height)
                            }
                        }
                        .contentShape(.rect)
                        .gesture(SpatialTapGesture().onEnded { value in
                            point = CGPoint(x: min(max(value.location.x / size.width, 0), 1),
                                            y: min(max(value.location.y / size.height, 0), 1))
                        })
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        .accessibilityIdentifier("distanceCanvas")
                        .accessibilityLabel(appLanguage.text("ภาพสำหรับแตะเลือกจุดวัดระยะ"))
                }.padding(16)
            } tools: {
                ScrollView {
                    VStack(spacing: 16) {
                        Text("แตะวัตถุที่จะวัดระยะ").font(LunaTheme.font(.headline))
                        if let reading {
                            let distance = reading.meters.formatted(.number.locale(appLanguage.locale)
                                .precision(.fractionLength(depth.depthSource.isEstimated ? 1 : 2)))
                            Text(verbatim: "≈ \(distance) \(appLanguage.text("เมตร"))")
                                .font(LunaTheme.font(.largeTitle).monospacedDigit())
                                .accessibilityIdentifier("distanceReading")
                        }
                        Text(appLanguage.text(explanation))
                            .font(LunaTheme.font(.subheadline)).foregroundStyle(LunaTheme.muted)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("distanceExplanation")
                        Button("เลือกจุดกลางภาพ") { point = CGPoint(x: 0.5, y: 0.5) }
                            .buttonStyle(.bordered).accessibilityIdentifier("distanceCenter")
                        let capturedTime = depth.capturedAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened)
                            .locale(appLanguage.locale))
                        Text(appLanguage.text("\(depth.depthSource.title) · ภาพถ่าย \(capturedTime)"))
                            .font(LunaTheme.font(.caption)).foregroundStyle(LunaTheme.muted)

                    }
                    .padding(16)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            .background(LunaTheme.night)
            .navigationTitle(appLanguage.text(depth.depthSource.isEstimated ? "ประเมินระยะจากภาพ" : "วัดระยะ LiDAR")).navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(LunaTheme.night, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("ใช้จุดนี้") { if let point { confirm(point) } }
                        .disabled(reading == nil).accessibilityIdentifier("confirmDistance")
                }
            }
        }.font(LunaTheme.font(.body))
        .foregroundStyle(LunaTheme.paper)
        .tint(LunaTheme.gold).preferredColorScheme(.dark)
    }
}

struct DistancePointThumbnail: View {
    let photo: UIImage
    let point: CGPoint
    var region: PhotoRegion? = nil
    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / photo.size.width, geometry.size.height / photo.size.height)
            let size = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
            Image(uiImage: photo).resizable().frame(width: size.width, height: size.height)
                .overlay(alignment: .topLeading) {
                    if let region {
                        Rectangle().stroke(LunaTheme.gold.opacity(0.8), lineWidth: 1)
                            .frame(width: region.rect.width * size.width, height: region.rect.height * size.height)
                            .offset(x: region.rect.minX * size.width, y: region.rect.minY * size.height)
                    }
                    Circle().fill(LunaTheme.gold).frame(width: 8, height: 8)
                        .offset(x: point.x * size.width - 4, y: point.y * size.height - 4)
                }.position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }.accessibilityHidden(true)
    }
}
