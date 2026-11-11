import Foundation
import ImageIO
import Vision

struct DocumentText: Sendable {
    let text: String
    let lineCount: Int
}

enum DocumentTextError: LocalizedError {
    case unreadableImage, noText
    var errorDescription: String? {
        switch self {
        case .unreadableImage: "เปิดภาพส่วนที่เลือกไม่ได้ กรุณาเลือกพื้นที่ใหม่"
        case .noText: "ไม่พบข้อความที่อ่านได้ในพื้นที่นี้ ลองเลือกกรอบให้ชิดข้อความหรือถ่ายให้ชัดขึ้น"
        }
    }
}

struct TextScan: Sendable {
    let document: DocumentText
    let sources: [TextSource]
}

/// A single photo/crop's text and geometry, never image buffers or Vision requests.
/// Including content and recognition settings prevents stale results at a reused URL.
struct QuestionTextCache: Sendable {
    struct Key: Equatable, Sendable {
        let image: URL
        let content: LocalFileFingerprint
        let recognitionSignature: String

        init(image: URL, recognitionSignature: String = DocumentTextReader.recognitionSignature) throws {
            self.image = image.standardizedFileURL.resolvingSymlinksInPath()
            content = try LocalFileFingerprint(url: self.image)
            self.recognitionSignature = recognitionSignature
        }
    }

    enum Value: Sendable {
        case text(TextScan), noText
        var scan: TextScan? {
            if case .text(let scan) = self { return scan }
            return nil
        }
    }

    private var entry: (key: Key, value: Value)?

    mutating func value(for key: Key) -> Value? {
        guard entry?.key == key else { clear(); return nil }
        return entry?.value
    }

    mutating func store(_ value: Value, for key: Key) { entry = (key, value) }
    mutating func retainOnly(image: URL?) {
        guard let image, entry?.key.image == image.standardizedFileURL.resolvingSymlinksInPath() else {
            clear()
            return
        }
    }
    mutating func clear() { entry = nil }
}

enum DocumentTextReader {
    static let recognitionSignature = "accurate;correction=off;autoLanguage=on;preferred=th-TH,en-US;rectangles=24,0.65,0.04,0.15;upright;v1"

    /// Vision runs off the UI thread and reads only the already-cropped upright image.
    static func read(image: URL) async throws -> DocumentText {
        try await scan(image: image, includeLayout: false).document
    }

    static func scan(image: URL, includeLayout: Bool = true) async throws -> TextScan {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.automaticallyDetectsLanguage = true
            let supported = try request.supportedRecognitionLanguages()
            let preferred = ["th-TH", "en-US"].filter { supported.contains($0) }
            if !preferred.isEmpty { request.recognitionLanguages = preferred }
            let handler = VNImageRequestHandler(url: image, orientation: .up)
            try handler.perform([request])
            try Task.checkCancellation()
            let lines = (request.results ?? []).enumerated().compactMap { index, observation -> RecognizedLine? in
                guard let text = observation.topCandidates(1).first?.string,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                let box = observation.boundingBox
                return RecognizedLine(id: index, text: text,
                                      rect: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height))
            }
            guard !lines.isEmpty else { throw DocumentTextError.noText }
            let document = DocumentText(text: lines.map(\.text).joined(separator: "\n"), lineCount: lines.count)
            guard includeLayout else { return TextScan(document: document, sources: []) }
            let rectangles = VNDetectRectanglesRequest()
            rectangles.maximumObservations = 24
            rectangles.minimumConfidence = 0.65
            rectangles.minimumSize = 0.04
            rectangles.minimumAspectRatio = 0.15
            // Rectangle detection is an optional layout hint; OCR remains usable if it fails.
            try? handler.perform([rectangles])
            try Task.checkCancellation()
            let surfaces = (rectangles.results ?? []).map { observation in
                let box = observation.boundingBox
                return CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
            }
            return TextScan(document: document,
                            sources: TextSourceGrouper.group(lines: lines, surfaces: surfaces))
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: { worker.cancel() }
    }
}
