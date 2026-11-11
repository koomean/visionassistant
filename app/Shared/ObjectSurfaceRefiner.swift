import Foundation
import CoreGraphics
import CoreVideo
import Vision

/// Foreground instance labels in the same upright, full-image coordinates used
/// by visual grounding. Zero is background; each nonzero value is one instance.
struct ObjectInstanceMask: Sendable {
    struct Instance: Sendable {
        var count = 0
        var minX = Int.max
        var minY = Int.max
        var maxX = 0
        var maxY = 0

        mutating func include(x: Int, y: Int) {
            count += 1
            minX = min(minX, x); minY = min(minY, y)
            maxX = max(maxX, x + 1); maxY = max(maxY, y + 1)
        }
    }

    let width: Int
    let height: Int
    let labels: [UInt8]
    let instances: [UInt8: Instance]

    init(width: Int, height: Int, labels: [UInt8]) {
        self.width = width
        self.height = height
        self.labels = labels
        guard width >= 5, height >= 5, width <= 1_024, height <= 1_024,
              labels.count == width * height else {
            instances = [:]
            return
        }
        // Counts and bounds depend only on this photo, not the requested box.
        // Store them with the mask so follow-up questions reuse this scan.
        var entries: [UInt8: Instance] = [:]
        for y in 0..<height {
            for x in 0..<width {
                let id = labels[y * width + x]
                guard id != 0 else { continue }
                entries[id, default: Instance()].include(x: x, y: y)
            }
        }
        instances = entries
    }

    fileprivate init(width: Int, height: Int, labels: [UInt8], instances: [UInt8: Instance]) {
        self.width = width
        self.height = height
        self.labels = labels
        self.instances = instances
    }
}

/// Keeps only the most recent photo's small instance mask. It never caches depth
/// or a measured point, so another photograph cannot inherit a previous range.
actor ObjectSurfaceRefiner {
    static let shared = ObjectSurfaceRefiner()
    private var cachedImage: URL?
    private var cachedMask: ObjectInstanceMask?
    private var cacheRevision: UInt64 = 0

    func clear() {
        cacheRevision &+= 1
        cachedImage = nil
        cachedMask = nil
    }

    func refine(target: ObjectGroundingTarget, image: URL, depth: LiDARSnapshot) async throws -> ObjectGroundingTarget? {
        try Task.checkCancellation()
        let mask: ObjectInstanceMask?
        if cachedImage == image { mask = cachedMask }
        else {
            cacheRevision &+= 1
            let revision = cacheRevision
            mask = await Task.detached(priority: .userInitiated) {
                try? Self.makeMask(image: image)
            }.value
            try Task.checkCancellation()
            // A clear/new photo while Vision was running must not resurrect an
            // old mask or its cached statistics after the actor resumes.
            if cacheRevision == revision {
                cachedImage = image
                cachedMask = mask
            }
        }
        guard let mask else { return nil }
        return try ObjectSurfaceMatcher.refine(target: target, depth: depth, mask: mask)
    }

    private nonisolated static func makeMask(image: URL) throws -> ObjectInstanceMask? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(url: image)
        try handler.perform([request])
        guard let pixelBuffer = request.results?.first?.instanceMask,
              CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_OneComponent8 else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0, width <= 1_024, height <= 1_024 else { return nil }
        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard rowBytes >= width else { return nil }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var labels = [UInt8](repeating: 0, count: width * height)
        var instances: [UInt8: ObjectInstanceMask.Instance] = [:]
        for row in 0..<height {
            for column in 0..<width {
                let id = bytes[row * rowBytes + column]
                labels[row * width + column] = id
                if id != 0 { instances[id, default: .init()].include(x: column, y: row) }
            }
        }
        return .init(width: width, height: height, labels: labels, instances: instances)
    }
}

/// Pure geometry/sensor matcher, separate from Vision so every exclusion rule
/// can be tested with known foreground/background and depth maps.
enum ObjectSurfaceMatcher {
    static func refine(target: ObjectGroundingTarget, depth: LiDARSnapshot,
                       mask: ObjectInstanceMask) throws -> ObjectGroundingTarget? {
        guard mask.width >= 5, mask.height >= 5, mask.width <= 1_024, mask.height <= 1_024,
              mask.labels.count == mask.width * mask.height,
              depth.width >= 5, depth.height >= 5, depth.depthMeters.count == depth.width * depth.height else { return nil }
        let box = target.region.rect
        guard box.minX.isFinite, box.minY.isFinite, box.width.isFinite, box.height.isFinite else { return nil }
        let pixels = target.region.pixels(width: mask.width, height: mask.height)
        let instances = mask.instances
        var insideCounts: [UInt8: Int] = [:]
        for y in max(0, Int(pixels.minY))..<min(mask.height, Int(pixels.maxY)) {
            for x in max(0, Int(pixels.minX))..<min(mask.width, Int(pixels.maxX)) {
                let id = mask.labels[y * mask.width + x]
                guard id != 0 else { continue }
                insideCounts[id, default: 0] += 1
            }
        }
        var matches: [(id: UInt8, score: Double)] = []
        for (id, entry) in instances {
            let inside = insideCounts[id, default: 0]
            guard entry.count >= 25, Double(inside) / Double(entry.count) >= 0.6 else { continue }
            let bounds = CGRect(x: entry.minX, y: entry.minY, width: entry.maxX - entry.minX, height: entry.maxY - entry.minY)
            let intersection = bounds.intersection(pixels)
            let shared = intersection.isNull ? 0 : intersection.width * intersection.height
            let union = bounds.width * bounds.height + pixels.width * pixels.height - shared
            let iou = union > 0 ? shared / union : 0
            guard iou >= 0.35 else { continue }
            matches.append((id, 0.6 * Double(iou) + 0.4 * Double(inside) / Double(entry.count)))
        }
        matches.sort { $0.score > $1.score }
        guard let match = matches.first else { return nil }
        guard matches.count == 1 || matches[1].score < match.score * 0.75 else {
            throw AutomaticDistanceError.ambiguousTarget
        }
        if target.requiresUniqueInstance, let chosen = instances[match.id] {
            // A small VLM may nominate one tight box even for an unspecified
            // noun such as "bottle". Independently detect other similarly
            // shaped foreground instances instead of accepting that guess.
            let cw = Double(chosen.maxX - chosen.minX), ch = Double(chosen.maxY - chosen.minY)
            let duplicated = instances.contains { id, entry in
                guard id != match.id, entry.count >= 25 else { return false }
                let w = Double(entry.maxX - entry.minX), h = Double(entry.maxY - entry.minY)
                guard cw > 0, ch > 0, w > 0, h > 0 else { return false }
                return (0.6...1.67).contains(w / cw) && (0.6...1.67).contains(h / ch)
                    && (0.75...1.33).contains((w / h) / (cw / ch))
            }
            if duplicated { throw AutomaticDistanceError.ambiguousTarget }
        }

        let swaps = depth.orientation.rawValue >= 5
        let uprightWidth = swaps ? depth.height : depth.width
        let uprightHeight = swaps ? depth.width : depth.height
        // The entire raw 5x5 patch, plus pixel quantization, must remain within
        // this one visual instance and the requested object box.
        let marginX = 3 / CGFloat(uprightWidth)
        let marginY = 3 / CGFloat(uprightHeight)
        let safe = box.insetBy(dx: marginX, dy: marginY)
        guard !safe.isEmpty else { throw AutomaticDistanceError.targetTooSmall }
        func insideSurface(_ point: CGPoint) -> Bool {
            guard safe.contains(point) else { return false }
            let left = Int(floor((point.x - marginX) * CGFloat(mask.width)))
            let right = Int(ceil((point.x + marginX) * CGFloat(mask.width)))
            let top = Int(floor((point.y - marginY) * CGFloat(mask.height)))
            let bottom = Int(ceil((point.y + marginY) * CGFloat(mask.height)))
            guard left >= 0, top >= 0, right < mask.width, bottom < mask.height else { return false }
            for y in top...bottom { for x in left...right {
                if mask.labels[y * mask.width + x] != match.id { return false }
            } }
            return true
        }
        func rawValue(_ point: CGPoint) -> Float {
            let sensor = depth.orientation.sensorPoint(fromUpright: point)
            let x = min(depth.width - 1, max(0, Int(sensor.x * CGFloat(depth.width))))
            let y = min(depth.height - 1, max(0, Int(sensor.y * CGFloat(depth.height))))
            return depth.depthMeters[y * depth.width + x]
        }
        if insideSurface(target.point), (try? LiDARRangeReader.measure(depth, at: target.point)) != nil {
            return .init(label: target.label, region: target.region, point: target.point, surfaceEvidence: .visionInstance)
        }
        var candidates = NearestCandidates(capacity: 4_096)
        for y in max(0, Int(pixels.minY))..<min(mask.height, Int(pixels.maxY)) {
            for x in max(0, Int(pixels.minX))..<min(mask.width, Int(pixels.maxX)) {
                guard mask.labels[y * mask.width + x] == match.id else { continue }
                let point = CGPoint(x: (CGFloat(x) + 0.5) / CGFloat(mask.width), y: (CGFloat(y) + 0.5) / CGFloat(mask.height))
                guard safe.contains(point) else { continue }
                let value = rawValue(point)
                guard value.isFinite, depth.depthSource.supportedRange.contains(value) else { continue }
                let dx = point.x - target.point.x, dy = point.y - target.point.y
                candidates.insert(point: point, distance: dx * dx + dy * dy, order: y * mask.width + x)
            }
        }
        // Sparse raw maps have few candidates. Bound the local patch checks on
        // denser maps, where a nearby valid patch normally succeeds immediately.
        for point in candidates.orderedPoints() {
            try Task.checkCancellation()
            guard insideSurface(point),
                  (try? LiDARRangeReader.measure(depth, at: point)) != nil else { continue }
            return .init(label: target.label, region: target.region, point: point, surfaceEvidence: .visionInstance)
        }
        // A uniquely identified foreground instance is positive visual evidence.
        // Never fall back to an otherwise valid background reading outside it.
        throw LiDARMeasurementError.noReading
    }

    /// Max-heap retaining exactly the nearest K pixels. Row-major order resolves
    /// equal distances, matching the previous stable full-array sort.
    struct NearestCandidates {
        private struct Candidate {
            let point: CGPoint
            let distance: CGFloat
            let order: Int
        }
        private let capacity: Int
        private var heap: [Candidate] = []
        var count: Int { heap.count }

        init(capacity: Int) {
            self.capacity = max(0, capacity)
            heap.reserveCapacity(self.capacity)
        }

        private static func precedes(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
            lhs.distance < rhs.distance || (lhs.distance == rhs.distance && lhs.order < rhs.order)
        }

        mutating func insert(point: CGPoint, distance: CGFloat, order: Int) {
            guard capacity > 0 else { return }
            let candidate = Candidate(point: point, distance: distance, order: order)
            if heap.count < capacity {
                heap.append(candidate)
                var child = heap.count - 1
                while child > 0 {
                    let parent = (child - 1) / 2
                    guard Self.precedes(heap[parent], heap[child]) else { break }
                    heap.swapAt(parent, child)
                    child = parent
                }
            } else if Self.precedes(candidate, heap[0]) {
                heap[0] = candidate
                var parent = 0
                while parent * 2 + 1 < heap.count {
                    let left = parent * 2 + 1, right = left + 1
                    let worse = right < heap.count && Self.precedes(heap[left], heap[right]) ? right : left
                    guard Self.precedes(heap[parent], heap[worse]) else { break }
                    heap.swapAt(parent, worse)
                    parent = worse
                }
            }
        }

        func orderedPoints() -> [CGPoint] {
            heap.sorted(by: Self.precedes).map(\.point)
        }
    }
}
