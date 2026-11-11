import Foundation

/// Coordinates are normalized to the upright image, with the origin at top left.
struct PhotoRegion: Sendable, Equatable {
    let rect: CGRect
    static let full = PhotoRegion(rect: CGRect(x: 0, y: 0, width: 1, height: 1))

    init(rect: CGRect) {
        let clipped = rect.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        self.rect = clipped.isNull || clipped.isEmpty ? CGRect(x: 0, y: 0, width: 1, height: 1) : clipped
    }

    static func drawn(from start: CGPoint, to end: CGPoint, in size: CGSize) -> Self? {
        guard size.width > 0, size.height > 0 else { return nil }
        let start = CGPoint(x: min(max(start.x, 0), size.width), y: min(max(start.y, 0), size.height))
        let end = CGPoint(x: min(max(end.x, 0), size.width), y: min(max(end.y, 0), size.height))
        guard abs(start.x - end.x) >= 24, abs(start.y - end.y) >= 24 else { return nil }
        return .init(rect: CGRect(x: min(start.x, end.x) / size.width,
                                 y: min(start.y, end.y) / size.height,
                                 width: abs(start.x - end.x) / size.width,
                                 height: abs(start.y - end.y) / size.height))
    }

    func pixels(width: Int, height: Int) -> CGRect {
        CGRect(x: rect.minX * CGFloat(width), y: rect.minY * CGFloat(height),
               width: rect.width * CGFloat(width), height: rect.height * CGFloat(height))
            .integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
    }

    var label: String {
        if self == .full { return "ทั้งภาพ" }
        let vertical = rect.midY < 0.34 ? "ส่วนบน" : rect.midY > 0.66 ? "ส่วนล่าง" : "ตรงกลาง"
        let horizontal = rect.midX < 0.34 ? "ซ้าย" : rect.midX > 0.66 ? "ขวา" : ""
        return vertical + (horizontal.isEmpty ? "" : " · " + horizontal)
    }
}

enum PhotoAction: String, CaseIterable, Identifiable, Sendable {
    case question, read, summarize
    var id: String { rawValue }
    var title: String {
        switch self {
        case .question: "ถามภาพ"
        case .read: "อ่านข้อความ"
        case .summarize: "สรุปข้อความ"
        }
    }
    var placeholder: String {
        switch self {
        case .question: "พิมพ์ถามเกี่ยวกับภาพ…"
        case .read: "อ่านตามต้นฉบับในพื้นที่ที่เลือก"
        case .summarize: "เน้นเรื่องใดเป็นพิเศษ? (ไม่บังคับ)"
        }
    }
}
