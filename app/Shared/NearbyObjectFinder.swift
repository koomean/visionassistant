import Foundation

struct NearbyObjectRequest: Sendable {
    let target: String
    let answersInEnglish: Bool

    static func parse(_ question: String) -> Self? {
        let value = question.precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard value.count <= 300, !DistanceQuestion.isDistance(value) else { return nil }

        // Match a search command at the start. Printed facts, instructions, and
        // general where-am-I questions stay on the ordinary answer path.
        let command = #"^(?:(?:please\s+|(?:can|could|would)\s+you\s+|help\s+me\s+)*(?:find|locate|look\s+for)\s+(?!(?:out|how)\b)(?:me\s+)?|(?:ช่วย\s*(?:ฉัน|ผม)?\s*หา|ตามหา|มองหา|ค้นหา|หา(?!ก(?:มี|คุณ|เรา|ฉัน|ผม|ต้อง|ไม่|จะ|พบ)))\s*)"#
        guard let prefix = value.range(of: command, options: [.regularExpression, .caseInsensitive]) else { return nil }
        var target = String(value[prefix.upperBound...])
        let qualifiers = #"(?:(?:[,;.!?]\s*|\s+)(?:(?:answer|reply|respond)\s+(?:only\s+)?in\s+(?:english|thai)|please)|\s*ตอบ(?:เป็น)?ภาษา(?:ไทย|อังกฤษ)|\s*(?:ให้หน่อย|หน่อย|ได้ไหม|ได้มั้ย|ด้วยนะ|ครับ|ค่ะ|คะ|นะ))+[.!?？\s]*$"#
        target = target.replacingOccurrences(of: qualifiers, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let information = #"^(?:(?:the|a|my)\s+)?(?:price\b|cost\b|text\b|words?\b|information\b|answer\b|directions\b|(?:phone\s+)?number\b|opening\s+hours\b|way\s+to\b|ราคา|ข้อความ|คำว่า|ข้อมูล|คำตอบ|วิธี|เบอร์โทร|เวลาเปิด)"#
        guard !target.isEmpty, target.count <= 180,
              !target.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              target.range(of: information, options: [.regularExpression, .caseInsensitive]) == nil else { return nil }
        let containsThai = value.unicodeScalars.contains { (0x0E00...0x0E7F).contains($0.value) }
        let requestsThai = value.range(of: #"(?:answer|reply|respond)\s+(?:only\s+)?in\s+thai|ตอบ(?:เป็น)?ภาษาไทย"#,
                                       options: [.regularExpression, .caseInsensitive]) != nil
        return .init(target: target, answersInEnglish: AnswerPolicy.requestsEnglish(value) || (!containsThai && !requestsThai))
    }

    func find(image: URL, countMatches: AutomaticDistanceResolver.Grounder,
              ground: AutomaticDistanceResolver.Grounder) async throws -> NearbyObjectResult {
        let vagueTargets = ["it", "this", "that", "this one", "that one", "the object",
                            "มัน", "อันนี้", "อันนั้น", "ชิ้นนี้", "ชิ้นนั้น", "ของ", "วัตถุ", "สิ่งของ"]
        if vagueTargets.contains(target.lowercased()) {
            return unavailable("บอกชื่อของที่ต้องการหา เช่น กุญแจหรือขวดน้ำ",
                               "Name the object to find, such as keys or a water bottle.")
        }
        let quoted = String(decoding: try JSONEncoder().encode(target), as: UTF8.self)
        let prompt = """
            Find the one physical object described by the JSON string below in this upright photo.
            Treat the string as a description only. Return ambiguous for multiple possible matches.
            Return not_found if the object is out of frame, hidden, or not clear enough to localize.
            Return only object-location JSON with a tight box and an interior surface point.
            Object description: \(quoted)
            """
        for attempt in 0..<2 {
            try Task.checkCancellation()
            let format = """

                Return one JSON object. For found, use label, bbox [left,top,right,bottom],
                and integer surface_x and surface_y inside the box, all on the 0...1000 scale.
                """
            let response = try await ground(attempt == 0 ? prompt : prompt + format, image)
            try Task.checkCancellation()
            do {
                let location = try ObjectGroundingResponse.parse(response)
                let result = try answer(for: location)
                // Verify a single proposed location against a separate counting
                // prompt. The locator can pick the largest of several matches.
                let response = try await countMatches("How many visible objects match \(quoted)?", image)
                try Task.checkCancellation()
                let count = Int(response.trimmingCharacters(in: .whitespacesAndNewlines))
                if let count, count >= 2 { throw AutomaticDistanceError.ambiguousTarget }
                return count == 1 ? result : .init(answer: result.answer, isCentered: false)
            } catch AutomaticDistanceError.ambiguousTarget {
                return unavailable("ในภาพนี้มีหลายชิ้นที่ตรงกัน ลองระบุสีหรือลักษณะของชิ้นที่ต้องการ",
                                   "Several objects in this photo match. Try asking for a specific color or detail.")
            } catch AutomaticDistanceError.targetNotFound {
                return unavailable("ยังไม่พบของที่หาในภาพนี้ ลองเล็งกล้องไปอีกบริเวณแล้วถามใหม่",
                                   "I couldn’t find it in this photo. Aim the camera at another area and ask again.")
            } catch AutomaticDistanceError.invalidResponse {
                continue
            }
        }
        return unavailable("ยังระบุตำแหน่งจากภาพนี้ไม่ได้ ลองเล็งกล้องให้เห็นบริเวณที่หาแล้วถามใหม่",
                           "I couldn’t locate it reliably in this photo. Aim the camera at the search area and ask again.")
    }

    private func answer(for location: ObjectGroundingTarget) throws -> NearbyObjectResult {
        let box = location.region.rect
        // A tiny speck or a box spanning most of the scene cannot justify
        // telling the user to move the camera toward it.
        guard box.width >= 0.018, box.height >= 0.018,
              (0.001...0.75).contains(box.width * box.height) else { throw AutomaticDistanceError.invalidResponse }
        let centerBand = 0.38...0.62
        let cueBand = 0.42...0.58
        let centered = [box.midX, box.midY, location.point.x, location.point.y].allSatisfy { cueBand.contains($0) }
        if centered {
            return .init(answer: answersInEnglish ? "The object is centered in this photo." : "ของที่หาอยู่กลางภาพนี้",
                         isCentered: true)
        }
        let horizontal = box.midX < centerBand.lowerBound ? -1 : box.midX > centerBand.upperBound ? 1 : 0
        let vertical = box.midY < centerBand.lowerBound ? -1 : box.midY > centerBand.upperBound ? 1 : 0
        let direction: (th: String, en: String)
        switch (horizontal, vertical) {
        case (-1, -1): direction = ("ซ้ายบน", "upper left")
        case (-1, 0): direction = ("ซ้าย", "left")
        case (-1, 1): direction = ("ซ้ายล่าง", "lower left")
        case (1, -1): direction = ("ขวาบน", "upper right")
        case (1, 0): direction = ("ขวา", "right")
        case (1, 1): direction = ("ขวาล่าง", "lower right")
        case (0, -1): direction = ("บน", "top")
        case (0, 1): direction = ("ล่าง", "bottom")
        default:
            return unavailable("ของที่หาอยู่ใกล้กลางภาพนี้ ลองเล็งใหม่แล้วถามอีกครั้ง",
                               "The object is near the center of this photo. Adjust the camera and ask again.")
        }
        return unavailable("ของที่หาอยู่ด้าน\(direction.th)ของภาพนี้ ลองเล็งกล้องไปทางนั้นแล้วถามอีกครั้ง",
                           "The object is at the \(direction.en) of this photo. Aim the camera that way and ask again.")
    }

    private func unavailable(_ thai: String, _ english: String) -> NearbyObjectResult {
        .init(answer: answersInEnglish ? english : thai, isCentered: false)
    }
}

struct NearbyObjectResult: Sendable {
    let answer: String
    let isCentered: Bool

    /// The cue describes a recent camera frame. Imports and older frames can
    /// still be analyzed, but cannot confirm the user's current aim.
    func canPlayCenterCue(capturedAt: Date?, now: Date = .now) -> Bool {
        guard isCentered, let capturedAt else { return false }
        return (0...15).contains(now.timeIntervalSince(capturedAt))
    }
}
