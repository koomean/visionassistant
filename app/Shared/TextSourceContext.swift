import Foundation
import ImageIO
import UniformTypeIdentifiers

struct TextSourceContext: Sendable {
    let source: TextSource
    let image: URL
}

enum TextSourceContextImages {
    /// Decode once for all crops. Keep the carrier around the text (bottle neck,
    /// menu edges, sign board), which is needed to recognize its physical source.
    static func prepare(image: URL, sources: [TextSource]) async throws -> [TextSourceContext] {
        let worker = Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(image as CFURL, nil),
                  let upright = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2_048
                  ] as CFDictionary) else { throw DocumentTextError.unreadableImage }
            var results: [TextSourceContext] = []
            do {
                for source in sources {
                    try Task.checkCancellation()
                    let text = source.region.rect
                    let context = PhotoRegion(rect: CGRect(
                        x: text.minX - max(0.04, text.width),
                        y: text.minY - max(0.06, text.height * 2.5),
                        width: text.width + max(0.08, text.width * 2),
                        height: text.height + max(0.12, text.height * 3.5)))
                    guard let crop = upright.cropping(to: context.pixels(width: upright.width, height: upright.height)) else {
                        throw DocumentTextError.unreadableImage
                    }
                    let url = URL.temporaryDirectory.appending(path: "lunav-source-context-\(UUID().uuidString).jpg")
                    let data = NSMutableData()
                    guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
                        throw DocumentTextError.unreadableImage
                    }
                    CGImageDestinationAddImage(destination, crop, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
                    guard CGImageDestinationFinalize(destination) else { throw DocumentTextError.unreadableImage }
                    try (data as Data).write(to: url, options: .atomic)
                    results.append(.init(source: source, image: url))
                }
                try Task.checkCancellation()
                return results
            } catch {
                for result in results { try? FileManager.default.removeItem(at: result.image) }
                throw error
            }
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
}
