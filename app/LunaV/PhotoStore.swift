import Foundation
import ImageIO
import UniformTypeIdentifiers

struct PreparedPhoto: Sendable {
    let url: URL
    let data: Data
    let originalURL: URL?
}

enum PhotoStore {
    /// Keep the compressed original for later text crops; preview decoding stays bounded.
    static func prepare(_ data: Data) async throws -> PreparedPhoto {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard data.count <= 50 * 1_024 * 1_024,
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw CameraError.captureFailed }
            let thumbnail = try thumbnail(source, maximum: 1_536)
            try Task.checkCancellation()
            let prepared = try save(thumbnail)
            let original = URL.temporaryDirectory.appending(path: "lunav-source-\(UUID().uuidString).image")
            do {
                try data.write(to: original, options: .atomic)
                try Task.checkCancellation()
            } catch {
                try? FileManager.default.removeItem(at: prepared.url)
                try? FileManager.default.removeItem(at: original)
                throw error
            }
            return PreparedPhoto(url: prepared.url, data: prepared.data, originalURL: original)
        }
        return try await withTaskCancellationHandler {
            let prepared = try await worker.value
            if Task.isCancelled {
                remove(prepared)
                throw CancellationError()
            }
            return prepared
        } onCancel: { worker.cancel() }
    }

    static func remove(_ photo: PreparedPhoto) {
        for url in [photo.url, photo.originalURL].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func crop(original: URL, region: PhotoRegion, forText: Bool) async throws -> PreparedPhoto {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithURL(original as CFURL, nil) else { throw DocumentTextError.unreadableImage }
            // Cap decode memory even for 48 MP input. Read from the original, not the preview.
            let image = try thumbnail(source, maximum: forText ? 4_096 : 2_048)
            let area = region.pixels(width: image.width, height: image.height)
            guard area.width >= 8, area.height >= 8, let crop = image.cropping(to: area) else {
                throw DocumentTextError.unreadableImage
            }
            try Task.checkCancellation()
            let result = try save(crop)
            if Task.isCancelled { try? FileManager.default.removeItem(at: result.url); throw CancellationError() }
            return result
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }

    private static func thumbnail(_ source: CGImageSource, maximum: Int) throws -> CGImage {
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximum,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { throw CameraError.captureFailed }
        return image
    }

    private static func save(_ image: CGImage) throws -> PreparedPhoto {
        let jpeg = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw CameraError.captureFailed }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CameraError.captureFailed }
        let url = URL.temporaryDirectory.appending(path: "lunav-\(UUID().uuidString).jpg")
        try (jpeg as Data).write(to: url, options: .atomic)
        return PreparedPhoto(url: url, data: jpeg as Data, originalURL: nil)
    }
}
