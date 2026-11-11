import Foundation

struct RecognizedLine: Sendable, Equatable {
    let id: Int
    let text: String
    /// Upright image coordinates, origin at top left.
    let rect: CGRect
}

enum TextSourceKind: String, Codable, Sendable {
    case sign, menu, bottleLabel = "bottle_label", packageLabel = "package_label", document, screen, other
    var title: String {
        switch self {
        case .sign: "ป้าย"
        case .menu: "เมนูอาหาร"
        case .bottleLabel: "ฉลากขวด"
        case .packageLabel: "ฉลากสินค้า"
        case .document: "เอกสาร"
        case .screen: "หน้าจอ"
        case .other: "ข้อความ"
        }
    }
}

struct TextSource: Identifiable, Sendable, Equatable {
    let id: Int
    let lines: [RecognizedLine]
    let region: PhotoRegion
    var kind: TextSourceKind = .other
    var title: String { "\(kind.title) \(id + 1) · \(region.label)" }
    var text: String { lines.map(\.text).joined(separator: "\n") }
}

struct TextSourceAnalysis: Sendable {
    var sources: [TextSource]
    var visuallyClassified: Bool = false
    var classificationNote: String?
    var classificationResponse: String?
    var text: String { sources.map { "[\($0.title)]\n\($0.text)" }.joined(separator: "\n\n") }
    var lineCount: Int { sources.reduce(0) { $0 + $1.lines.count } }
}

enum TextSourceGrouper {
    static func group(lines: [RecognizedLine], surfaces: [CGRect] = []) -> [TextSource] {
        guard !lines.isEmpty else { return [] }
        // A detected rectangular surface can hold menu columns or centered label text.
        // Ignore image borders and tiny boxes, and choose the smallest containing surface.
        let surfaces = surfaces.filter { surface in
            guard surface.width * surface.height < 0.85, surface.width > 0.04, surface.height > 0.03 else { return false }
            let contained = lines.filter { line in
                let area = surface.intersection(line.rect)
                return !area.isNull && area.width * area.height >= line.rect.width * line.rect.height * 0.85
            }
            guard contained.count >= 2 else { return false }
            let textBounds = contained.reduce(CGRect.null) { $0.union($1.rect) }
            let meanHeight = contained.reduce(CGFloat.zero) { $0 + $1.rect.height } / CGFloat(contained.count)
            // Vision also detects tight rectangles around glyphs/words. Such boxes
            // must not take ownership away from a real label/menu surface.
            return surface.height - textBounds.height > meanHeight * 0.4
                && surface.width - textBounds.width > meanHeight * 0.25
        }
        let owners: [Int?] = lines.map { line in
            surfaces.indices.filter {
                let intersection = surfaces[$0].intersection(line.rect)
                return !intersection.isNull && intersection.width * intersection.height >= line.rect.width * line.rect.height * 0.85
            }.min { surfaces[$0].width * surfaces[$0].height < surfaces[$1].width * surfaces[$1].height }
        }
        var parents = Array(lines.indices)
        func root(_ index: Int) -> Int {
            var i = index
            while parents[i] != i { i = parents[i] }
            return i
        }
        for i in lines.indices {
            for j in lines.indices where j > i {
                let sameSurface = owners[i] != nil && owners[i] == owners[j]
                let bothUnowned = owners[i] == nil && owners[j] == nil
                if sameSurface || (bothUnowned && adjacent(lines[i].rect, lines[j].rect)) {
                    parents[root(j)] = root(i)
                }
            }
        }
        var groups: [Int: [RecognizedLine]] = [:]
        for i in lines.indices { groups[root(i), default: []].append(lines[i]) }
        let ordered = groups.values.map { group -> ([RecognizedLine], CGRect) in
            let orderedLines = readingOrder(group, x: { $0.rect.minX }, y: { $0.rect.midY }, tie: { $0.id }) {
                abs($0.rect.midY - $1.rect.midY) < min($0.rect.height, $1.rect.height) * 0.5
            }
            let box = group.reduce(CGRect.null) { $0.union($1.rect) }
            return (orderedLines, box)
        }
        let orderedSources = readingOrder(ordered, x: { $0.1.minX }, y: { $0.1.minY },
                                         tie: { $0.0.map(\.id).min() ?? 0 }) {
            abs($0.1.minY - $1.1.minY) < 0.035
        }
        return orderedSources.enumerated().map { index, entry in
            let padding = min(0.015, entry.1.height * 0.15)
            return TextSource(id: index, lines: entry.0,
                              region: .init(rect: entry.1.insetBy(dx: -padding, dy: -padding)))
        }
    }

    /// Proximity is not a transitive comparison: A may share a row with B and B
    /// with C while A and C do not. Sort vertically first, anchor each row once,
    /// then sort horizontally so OCR input enumeration cannot shuffle the text.
    private static func readingOrder<T>(_ values: [T], x: (T) -> CGFloat, y: (T) -> CGFloat,
                                        tie: (T) -> Int, sameRow: (T, T) -> Bool) -> [T] {
        let vertical = values.sorted {
            if y($0) != y($1) { return y($0) < y($1) }
            if x($0) != x($1) { return x($0) < x($1) }
            return tie($0) < tie($1)
        }
        var rows: [[T]] = []
        for value in vertical {
            if let anchor = rows.last?.first, sameRow(anchor, value) {
                rows[rows.count - 1].append(value)
            } else { rows.append([value]) }
        }
        return rows.flatMap { row in
            row.sorted {
                if x($0) != x($1) { return x($0) < x($1) }
                if y($0) != y($1) { return y($0) < y($1) }
                return tie($0) < tie($1)
            }
        }
    }

    private static func adjacent(_ a: CGRect, _ b: CGRect) -> Bool {
        // Horizontal neighbors on one baseline may belong to different bottles/columns.
        // Join vertically aligned lines only; a shared surface handles menu price columns.
        let gap = max(0, max(a.minY, b.minY) - min(a.maxY, b.maxY))
        let height = min(a.height, b.height)
        let overlap = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        let aligned = abs(a.minX - b.minX) < 0.035 || abs(a.midX - b.midX) < 0.045
        return abs(a.midY - b.midY) >= height * 0.5
            && gap <= min(0.045, max(a.height, b.height) * 1.5)
            && overlap >= min(a.width, b.width) * 0.35 && aligned
    }
}

enum TextSourceLabels {
    /// The model may label known IDs, but it cannot change OCR text, bounds or membership.
    static func apply(_ response: String, to sources: [TextSource]) -> [TextSource]? {
        if sources.count == 1,
           let kind = TextSourceKind(rawValue: response.trimmingCharacters(in: .whitespacesAndNewlines)) {
            var source = sources[0]
            source.kind = kind
            return [source]
        }
        struct Envelope: Decodable { let sources: [Label] }
        struct Label: Decodable { let id: Int; let kind: TextSourceKind }
        let result: Envelope
        if let first = response.firstIndex(of: "["), let last = response.lastIndex(of: "]"), first <= last,
           let data = String(response[first...last]).data(using: .utf8),
           let kinds = try? JSONDecoder().decode([TextSourceKind].self, from: data), kinds.count == sources.count {
            result = Envelope(sources: zip(sources, kinds).map { Label(id: $0.id, kind: $1) })
        } else {
            guard let first = response.firstIndex(of: "{"), let last = response.lastIndex(of: "}"), first <= last,
                  let data = String(response[first...last]).data(using: .utf8),
                  let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }
            result = envelope
        }
        guard !result.sources.isEmpty, Set(result.sources.map(\.id)).count == result.sources.count,
              Set(result.sources.map(\.id)) == Set(sources.map(\.id)) else { return nil }
        let labels = Dictionary(uniqueKeysWithValues: result.sources.map { ($0.id, $0.kind) })
        return sources.map { source in
            var value = source
            value.kind = labels[source.id] ?? .other
            return value
        }
    }

}
