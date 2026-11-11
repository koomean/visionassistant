import CoreGraphics
import Foundation

enum TargetedTextReading {
    struct Request: Equatable, Sendable {
        enum Field: Equatable, Sendable {
            case price(item: String?)
            case busRoute
            case label(String)
            case line(containing: String)
            case word(String)
        }

        let field: Field
        let english: Bool
        var area: Area? = nil
        var menuOnly = false

        enum Area: String, Sendable {
            case left, right, top, bottom, center

            func contains(_ rect: CGRect) -> Bool {
                switch self {
                case .left: rect.midX < 0.5
                case .right: rect.midX > 0.5
                case .top: rect.midY < 0.5
                case .bottom: rect.midY > 0.5
                case .center: (0.33...0.67).contains(rect.midX) && (0.33...0.67).contains(rect.midY)
                }
            }
        }

        static func parse(_ prompt: String) -> Request? {
            let original = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = original.replacingOccurrences(
                of: #"(?:(?:[.,;]\s*|\s+)(?:answer|reply|respond)\s+(?:only\s+)?in\s+(?:English|Thai)|\s*ตอบ(?:เป็น)?ภาษา(?:อังกฤษ|ไทย))[.!?]?$"#,
                with: "", options: [.regularExpression, .caseInsensitive])
                .replacingOccurrences(of: #"^(?:(?:can|could|would)\s+you\s+|ขอ\s*)"#,
                                      with: "", options: [.regularExpression, .caseInsensitive])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let thai = capture(
                #"^(?:ช่วย\s*)?(?:(?:อ่าน|บอก)(?:ข้อความ)?\s*(?:แค่|เฉพาะ|เพียง|ให้ฟังแค่)\s*|อ่าน\s*(?=ราคา|เลข(?:สาย)?รถเมล์|หมายเลข(?:สาย)?รถเมล์|สายรถเมล์))(.+)$"#, in: text)
            let english = capture(#"^(?:please\s+)?(?:read|tell me)\s+(.+?)\s+only[.!?]?$"#, in: text)
                ?? capture(
                    #"^(?:please\s+)?(?:(?:just|only)\s+(?:read|tell me)\s+|(?:read|tell me)\s+(?:just|only)\s+|read\s+(?=(?:the\s+)?(?:price\b|(?:bus\s+)?route\s+(?:number|no\.)|bus\s+number\b)))(.+)$"#, in: text)
            guard let raw = thai ?? english else { return nil }
            var body = raw.replacingOccurrences(
                of: #"(?:\s*(?:ให้หน่อย|หน่อย|ได้ไหม|ได้มั้ย|เท่านั้น|นะครับ|นะคะ|ครับ|ค่ะ|คะ)|\s+please|[.!?])+$"#,
                with: "", options: [.regularExpression, .caseInsensitive])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty, body.count <= 120 else { return nil }

            let area = extractArea(from: &body)
            let wantsThai = matches(#"(?:answer|reply|respond)\s+(?:only\s+)?in\s+Thai|ตอบ(?:เป็น)?ภาษาไทย"#, original)
            let wantsEnglish = AnswerPolicy.requestsEnglish(original) || (thai == nil && !wantsThai)
            if matches(#"^(?:the\s+)?(?:(?:bus\s+)?route\s*(?:number|no\.?)?|bus\s+number)$|^(?:(?:เลข|หมายเลข)(?:สาย)?รถเมล์|สายรถเมล์|เลขสาย)$"#, body) {
                return .init(field: .busRoute, english: wantsEnglish, area: area)
            }
            let menuSuffix = #"(?:\s+(?:on|in|from)\s+(?:the\s+)?menu|\s*(?:ใน|บน|จาก)\s*เมนู)$"#
            let withoutMenu = body.replacingOccurrences(of: menuSuffix, with: "", options: [.regularExpression, .caseInsensitive])
            let menuOnly = withoutMenu != body
            if matches(#"^(?:the\s+)?price$|^ราคา$"#, withoutMenu) {
                return .init(field: .price(item: nil), english: wantsEnglish, area: area, menuOnly: menuOnly)
            }
            if let item = capture(#"^(?:the\s+)?price\s+(?:of|for)\s+(?:the\s+)?(.+)$|^ราคา\s*(?:ของ\s*)?(.+)$"#, in: withoutMenu)
                ?? capture(#"^(?:the\s+)?(.+?)\s+price$"#, in: withoutMenu) {
                let name = item.replacingOccurrences(of: #"^เมนู\s*"#,
                                                     with: "", options: [.regularExpression, .caseInsensitive])
                return .init(field: .price(item: unquote(name)), english: wantsEnglish, area: area, menuOnly: menuOnly)
            }
            if let line = capture(
                #"^(?:the\s+)?line\s+(?:with|containing|that says)\s+(.+)$|^(?:แถว|บรรทัด)(?:ที่)?(?:มีคำว่า|เขียนว่า|มีข้อความว่า|ที่มี|มี)\s*(.+)$"#, in: body) {
                return .init(field: .line(containing: unquote(line)), english: wantsEnglish, area: area)
            }
            if let word = capture(#"^(?:the\s+)?(?:word|phrase)\s+(.+)$|^คำว่า\s*(.+)$"#, in: body) {
                return .init(field: .word(unquote(word)), english: wantsEnglish, area: area)
            }
            let label = body.replacingOccurrences(of: #"^(?:the|ค่า)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
            return .init(field: .label(unquote(label)), english: wantsEnglish, area: area)
        }

        private static func extractArea(from body: inout String) -> Area? {
            let english = #"\s+(?:(?:on|at|in|from)\s+(?:the\s+)?)(left|right|top|bottom|cent(?:er|re))(?:\s+(?:side|part|area))?(?:\s+of\s+(?:the\s+)?(?:image|photo|picture))?$"#
            let thai = #"\s*(?:(?:ที่อยู่|อยู่|ที่)\s*|(?:บน|ใน|จาก)\s*(?:ป้าย|ฉลาก|เมนู|ภาพ|รูป)\s*)?(?:ด้าน|ฝั่ง|ทาง|ตรง)\s*(ซ้าย|ขวา|บน|ล่าง|กลาง)(?:\s*(?:ของ)?(?:ภาพ|รูป))?$"#
            if let direction = capture(english, in: body) {
                body = body.replacingOccurrences(of: english, with: "", options: [.regularExpression, .caseInsensitive])
                return Area(rawValue: direction.lowercased().replacingOccurrences(of: "centre", with: "center"))
            }
            guard let direction = capture(thai, in: body) else { return nil }
            body = body.replacingOccurrences(of: thai, with: "", options: .regularExpression)
            return ["ซ้าย": .left, "ขวา": .right, "บน": .top, "ล่าง": .bottom, "กลาง": .center][direction]
        }
    }

    // Only the matched substring or line reaches speech and the conversation.
    static func answer(to request: Request, scan: TextScan?) -> String {
        let sources = scan?.sources ?? []
        func inArea(_ line: RecognizedLine) -> Bool {
            request.area?.contains(line.rect) ?? true
        }
        let candidates: [String]
        switch request.field {
        case .price(let item):
            candidates = prices(in: sources, item: item, menuOnly: request.menuOnly, inArea: inArea)
        case .busRoute:
            candidates = sources.flatMap { routeNumbers(in: $0, inArea: inArea) }
        case .label(let label):
            candidates = sources.flatMap { values(for: label, in: $0, inArea: inArea) }
        case .line(let phrase):
            candidates = sources.flatMap(\.lines).filter { inArea($0) && contains(phrase, in: $0.text) }.map(\.text)
        case .word(let phrase):
            candidates = sources.flatMap(\.lines).filter(inArea).compactMap { literalMatch(phrase, in: $0.text) }
        }
        let unique = Set(candidates.filter { !$0.isEmpty })
        guard unique.count == 1, let value = unique.first else {
            if unique.isEmpty {
                return request.english ? "I couldn’t verify the requested text in this image."
                    : "ยังยืนยันข้อความที่ขอในภาพนี้ไม่ได้"
            }
            return request.english ? "I found several matches. Say which item or area to read."
                : "พบข้อมูลตรงกันหลายจุด ลองระบุชื่อรายการหรือบริเวณที่ต้องการอ่าน"
        }
        switch request.field {
        case .price:
            return request.english ? "Price \(value)" : "ราคา \(value)"
        case .busRoute:
            return request.english ? "Bus route \(value)" : "รถเมล์สาย \(value)"
        default:
            return value
        }
    }

    private static let amount = #"\p{Nd}+(?:[,.]\p{Nd}+)*"#
    private static let priceLabel = #"(?:ราคา|\bprice\b(?:\s*(?:\((?:THB|Baht)\)|(?:THB|Baht)\b))?)"#
    private static let currencyPrefix = #"(?:฿|\$|€|£|THB\s+)\s*"#
    private static let currencySuffix = #"\s*(?:฿|บาท|THB\b|Baht\b)"#
    private static let amountBoundary = #"(?![\p{L}\p{N}/%]|[.,]\p{Nd})"#
    private static let routeLabel = #"(?:รถเมล์\s*สาย|สาย\s*รถเมล์|หมายเลข(?:สาย)?รถเมล์|เลข(?:สาย)?รถเมล์|^\s*สาย|\b(?:bus\s+)?route(?:\s*(?:number|no\.?|#))?|\bbus\s+(?:number|no\.?))"#
    private static let routeNumber = #"\p{Nd}{1,4}(?:[-–/]\p{Nd}{1,4})?(?:[A-Za-z])?(?![\p{L}\p{N}/–-]|[.,:]\p{Nd})"#

    private static func prices(in sources: [TextSource], item: String?, menuOnly: Bool,
                               inArea: (RecognizedLine) -> Bool) -> [String] {
        sources.flatMap { source -> [String] in
            let itemLines = item.map { name in source.lines.filter { contains(name, in: $0.text) } }
            let isMenu = source.kind == .menu || source.lines.contains { matches(#"(?:\bmenu\b|^\s*เมนู)"#, $0.text) }
            guard !menuOnly || isMenu else { return [] }
            let headers = source.lines.filter {
                matches("^\\s*\(priceLabel)\\s*[:：]?\\s*$", $0.text)
            }
            return source.lines.filter(inArea).flatMap { line -> [String] in
                if let itemLines, !itemLines.contains(where: { $0.id == line.id || rightOf(line, onSameRowAs: $0) }) {
                    return []
                }
                let labelled = captures("\(priceLabel)\\s*[:：=]?\\s*((?:\(currencyPrefix))?\(amount)(?:\(currencySuffix)|\(amountBoundary)))", in: line.text)
                if !labelled.isEmpty { return labelled }
                let currency = captures(
                    "(?<![\\p{Nd}.,])(\(currencyPrefix)\(amount)\(amountBoundary)|\(amount)\(currencySuffix))",
                    in: line.text)
                if !currency.isEmpty { return currency }

                if isMenu, let item, let printedName = literalMatch(item, in: line.text) {
                    let escaped = NSRegularExpression.escapedPattern(for: printedName)
                    if let value = capture("^\\s*\(escaped)\\s+(?:[.·…]+\\s*)?(\(amount))\\s*$", in: line.text) {
                        return [value]
                    }
                }

                // A bare number is evidence only under a Price header in the same OCR surface.
                guard headers.contains(where: { header in
                    line.rect.midY > header.rect.midY && alignedColumns(line.rect, header.rect)
                }), let bare = capture("^\\s*(\(amount))\\s*$", in: line.text) else { return [] }
                return [bare]
            }
        }
    }

    private static func routeNumbers(in source: TextSource, inArea: (RecognizedLine) -> Bool) -> [String] {
        let lines = source.lines.filter(inArea)
        let labelled = lines.flatMap { line in
            captures("\(routeLabel)\\s*[:：#]?\\s*(\(routeNumber))", in: line.text)
        }
        if !labelled.isEmpty { return labelled }
        let headers = source.lines.filter { matches("^\\s*\(routeLabel)\\s*[:：#]?\\s*$", $0.text) }
        return lines.compactMap { line in
            guard headers.contains(where: { rightOf(line, onSameRowAs: $0) }),
                  let number = capture("^\\s*(\(routeNumber))\\s*$", in: line.text) else { return nil }
            return number
        }
    }

    private static let fieldAliases = [
        ["phone number", "telephone", "tel", "phone", "เบอร์โทรศัพท์", "เบอร์โทร", "หมายเลขโทรศัพท์", "โทร"],
        ["opening hours", "business hours", "hours", "open", "เวลาเปิดทำการ", "เวลาเปิดร้าน", "เวลาเปิด", "เปิดทำการ"],
        ["expiration date", "expiry date", "expiration", "expiry", "exp", "วันหมดอายุ", "หมดอายุ"],
        ["ingredients", "ส่วนประกอบ", "ส่วนผสม"],
        ["address", "ที่อยู่"]
    ]

    private static func values(for label: String, in source: TextSource, inArea: (RecognizedLine) -> Bool) -> [String] {
        guard !label.isEmpty else { return [] }
        let aliases = fieldAliases.first { $0.contains(label.lowercased()) } ?? [label]
        let alternatives = aliases.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let field = "(?:\(alternatives))"
        let otherFields = fieldAliases.flatMap { $0 }.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let labelledValue = "(?:^\\s*\(field)(?:\\s*[:：=]\\s*|\\s+|(?=\\p{Nd}))|(?<=\\s)\(field)\\s*[:：=]\\s*)(.+?)(?=\\s+(?:\(otherFields)|\(field))\\s*[:：=]|$)"
        let lines = source.lines.filter(inArea)
        let values = lines.flatMap { line in
            captures(labelledValue, in: line.text).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        if !values.isEmpty { return values }
        let labels = source.lines.filter { matches("^\\s*\(field)\\s*[:：=]?\\s*$", $0.text) }
        return lines.filter { line in labels.contains { rightOf(line, onSameRowAs: $0) } }.map(\.text)
    }

    private static func rightOf(_ line: RecognizedLine, onSameRowAs label: RecognizedLine) -> Bool {
        let gap = line.rect.minX - label.rect.maxX
        return gap >= -0.003 && gap <= 0.28
            && abs(line.rect.midY - label.rect.midY) <= min(line.rect.height, label.rect.height) * 0.55
    }

    private static func alignedColumns(_ a: CGRect, _ b: CGRect) -> Bool {
        min(a.maxX, b.maxX) - max(a.minX, b.minX) >= min(a.width, b.width) * 0.5
    }

    private static func unquote(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: "\"'“”‘’")))
    }

    private static func contains(_ term: String, in text: String) -> Bool {
        literalMatch(term, in: text) != nil
    }

    private static func literalMatch(_ term: String, in text: String) -> String? {
        guard !term.isEmpty else { return nil }
        let escaped = NSRegularExpression.escapedPattern(for: term)
        let asciiTerm = matches(#"^[A-Za-z0-9].*[A-Za-z0-9]$|^[A-Za-z0-9]$"#, term)
        return capture(asciiTerm ? "(?<![A-Za-z0-9])(\(escaped))(?![A-Za-z0-9])" : "(\(escaped))", in: text)
    }

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        captures(pattern, in: text).first
    }

    private static func captures(_ pattern: String, in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            (1..<match.numberOfRanges).lazy
                .compactMap { Range(match.range(at: $0), in: text) }
                .first.map { String(text[$0]) }
        }
    }
}
