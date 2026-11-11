import SwiftUI

/// Display preferences only; sensor and haptic resources belong to the camera.
struct ObstacleSettingsSection: View {
    @Bindable var monitor: ObstacleHaptics
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("สั่นเตือนสิ่งกีดขวาง")
                .font(LunaTheme.font(.title3, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 18) {
                Toggle("เตือนด้วย LiDAR", isOn: setting(\.enabled))
                    .accessibilityIdentifier("obstacleWarnings")
                    .disabled(!monitor.isSupported)
                Text(language.text(obstacleStatusDescription(monitor)))
                    .font(LunaTheme.font(.footnote)).foregroundStyle(LunaTheme.muted)
                    .accessibilityIdentifier("obstacleStatus")
                    .fixedSize(horizontal: false, vertical: true)
                if monitor.isSupported {
                    distanceControl("ระยะเริ่มเตือน", value: setting(\.warningDistance), range: 0.5...4,
                                    id: "obstacleWarningDistance")
                    distanceControl("ระยะสั่นแรงที่สุด", value: setting(\.closeDistance),
                                    range: 0.2...min(1.5, monitor.configuration.warningDistance - 0.1),
                                    id: "obstacleCloseDistance")
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("ความแรงสูงสุด")
                            Spacer()
                            Text(monitor.configuration.maxIntensity, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit().foregroundStyle(LunaTheme.gold)
                        }.font(LunaTheme.font(.subheadline))
                        Slider(value: setting(\.maxIntensity), in: 0.2...1, step: 0.05) {
                            Text("ความแรงสูงสุด")
                        }.accessibilityIdentifier("obstacleIntensity")
                    }
                    Button { monitor.testVibration() } label: {
                        Label("ทดสอบการสั่น", systemImage: "iphone.radiowaves.left.and.right")
                            .font(LunaTheme.font(.subheadline, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.plain).accessibilityIdentifier("obstacleHapticsTest")
                }
                Text("ยิ่งใกล้ยิ่งสั่นแรงและถี่ขึ้น ใช้ระยะสดด้านหน้ากล้องหลัง พักระหว่างถาม AI และกลับมาเตือนอัตโนมัติเมื่อเสร็จ")
                    .font(LunaTheme.font(.footnote)).foregroundStyle(LunaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("เป็นสัญญาณช่วยเสริม อาจตรวจไม่พบกระจก พื้นต่างระดับ หรือสิ่งกีดขวางนอกมุมกล้อง")
                    .font(LunaTheme.font(.footnote)).foregroundStyle(LunaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(LunaTheme.deep, in: .rect(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(LunaTheme.line, lineWidth: 1) }
        }
    }

    private func setting<Value>(_ key: WritableKeyPath<ObstacleWarningConfiguration, Value>) -> Binding<Value> {
        Binding(get: { monitor.configuration[keyPath: key] }, set: { value in
            var configuration = monitor.configuration
            configuration[keyPath: key] = value
            monitor.configuration = configuration
        })
    }

    private func distanceControl(_ title: LocalizedStringKey, value: Binding<Double>,
                                 range: ClosedRange<Double>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                HStack(spacing: 4) {
                    Text(value.wrappedValue, format: .number.precision(.fractionLength(1)))
                    Text("ม.")
                }.monospacedDigit().foregroundStyle(LunaTheme.gold)
            }.font(LunaTheme.font(.subheadline))
            Slider(value: value, in: range, step: 0.1) { Text(title) }
                .accessibilityIdentifier(id)
        }
    }
}

@MainActor
func obstacleStatusDescription(_ monitor: ObstacleHaptics) -> String {
    guard monitor.isSupported else { return "ต้องใช้ iPhone ที่มี LiDAR และรองรับการสั่น" }
    switch monitor.state {
    case .off: return "ปิดการเตือนอยู่"
    case .unavailable: return "ข้อมูล LiDAR ไม่พร้อมใช้งาน"
    case .paused: return "พักการเตือนชั่วคราว"
    case .waiting: return "กำลังรอระยะสดจาก LiDAR"
    case .clear: return "ไม่พบสิ่งกีดขวางในบริเวณที่วัด"
    case .warning: return "พบสิ่งกีดขวางด้านหน้ากล้อง · กำลังสั่นเตือน"
    case .failed: return "การสั่นไม่พร้อมใช้งาน ลองปิดและเปิดการเตือนอีกครั้ง"
    }
}
