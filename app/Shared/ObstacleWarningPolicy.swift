import Foundation

/// Parameters for a foreground, live-LiDAR proximity cue. Distances are metres.
struct ObstacleWarningConfiguration: Equatable, Sendable {
    var enabled = false
    var warningDistance = 2.0
    var closeDistance = 0.4
    var maxIntensity = 0.8

    var normalized: Self {
        var value = self
        value.warningDistance = warningDistance.isFinite ? min(4, max(0.5, warningDistance)) : 2
        value.closeDistance = closeDistance.isFinite
            ? min(1.5, min(value.warningDistance - 0.1, max(0.2, closeDistance))) : min(0.4, value.warningDistance - 0.1)
        value.maxIntensity = maxIntensity.isFinite ? min(1, max(0.2, maxIntensity)) : 0.8
        return value
    }
}

struct ObstacleWarningPulse: Equatable, Sendable {
    let intensity: Double
    let interval: TimeInterval
    let distance: Double
}

/// Small deterministic filter. Missing/stale measurements never mean “clear”.
struct ObstacleWarningPolicy: Sendable {
    static let staleInterval: TimeInterval = 0.75
    private(set) var distance: Double?
    private(set) var lastValidTime: TimeInterval?
    private var candidate: Double?
    private var candidateTime: TimeInterval?
    private var warningLatched = false

    /// Capture timestamps are converted to host-clock seconds by AVFoundation's
    /// synchronization clock, then mapped onto uptime for the haptic watchdog.
    /// Delivery time must never make an old depth frame appear newly measured.
    static func measurementUptime(callbackUptime: TimeInterval, hostNow: TimeInterval,
                                  capturedHostTime: TimeInterval) -> TimeInterval? {
        guard callbackUptime.isFinite, callbackUptime >= 0,
              hostNow.isFinite, capturedHostTime.isFinite else { return nil }
        let age = hostNow - capturedHostTime
        guard age >= 0, age <= staleInterval, callbackUptime >= age else { return nil }
        return callbackUptime - age
    }

    mutating func reset() { self = Self() }

    mutating func receive(_ sample: Double?, at now: TimeInterval) {
        guard now.isFinite, let sample, sample.isFinite, (0.2...5).contains(sample) else {
            // Stop immediately on an invalid frame; two new agreeing frames
            // are required before a cue can resume.
            reset()
            return
        }
        if let lastValidTime, now < lastValidTime { reset() }
        if let candidate, let candidateTime, now > candidateTime,
           now - candidateTime <= Self.staleInterval,
           abs(candidate - sample) <= Self.agreementTolerance(from: candidate, to: sample, elapsed: now - candidateTime) {
            // Do not smooth away an approaching obstacle. Receding surfaces
            // relax gradually to avoid strength jumps on a depth boundary.
            if let distance { self.distance = sample < distance ? sample : distance + (sample - distance) * 0.5 }
            else { distance = min(candidate, sample) }
            lastValidTime = now
        } else {
            distance = nil
            lastValidTime = nil
            warningLatched = false
        }
        candidate = sample
        candidateTime = now
    }

    private static func agreementTolerance(from previous: Double, to sample: Double, elapsed: TimeInterval) -> Double {
        let noiseMargin = max(0.18, min(previous, sample) * 0.2)
        // An approaching person can move more than the stationary-noise
        // allowance between 5 Hz samples. Limit the extra tolerance so a
        // delayed or abruptly different surface still needs corroboration.
        let approachMargin = sample < previous ? 1.5 * min(elapsed, 0.25) : 0
        return noiseMargin + approachMargin
    }

    mutating func pulse(at now: TimeInterval, configuration: ObstacleWarningConfiguration) -> ObstacleWarningPulse? {
        let configuration = configuration.normalized
        guard configuration.enabled, now.isFinite, let lastValidTime,
              now >= lastValidTime, now - lastValidTime <= Self.staleInterval,
              let distance else { warningLatched = false; return nil }
        // Once warning starts, a small release margin prevents border chatter.
        let threshold = configuration.warningDistance + (warningLatched ? 0.12 : 0)
        guard distance <= threshold else { warningLatched = false; return nil }
        warningLatched = true
        let closeness = min(1, max(0, (configuration.warningDistance - distance)
            / (configuration.warningDistance - configuration.closeDistance)))
        return ObstacleWarningPulse(intensity: configuration.maxIntensity * (0.18 + 0.82 * closeness),
                                    interval: 1.1 - 0.94 * closeness, distance: distance)
    }

    func isFresh(at now: TimeInterval) -> Bool {
        guard let lastValidTime, now.isFinite else { return false }
        return now >= lastValidTime && now - lastValidTime <= Self.staleInterval
    }
}

/// Reads only a 13×11 grid in the forward centre of the sensor map. Require
/// neighbouring support, so an isolated bad pixel cannot trigger a near cue.
/// No RGB buffers, map copies, image analysis or ML inference are retained.
enum ObstacleDepthSampler {
    static func estimate(width: Int, height: Int, sample: (Int, Int) -> Float) -> Double? {
        guard width >= 24, height >= 24 else { return nil }
        let columns = 13, rows = 11
        var grid = [Double?](repeating: nil, count: columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let x = Int((0.28 + 0.44 * Double(column) / Double(columns - 1)) * Double(width - 1))
                let y = Int((0.25 + 0.5 * Double(row) / Double(rows - 1)) * Double(height - 1))
                let value = Double(sample(x, y))
                if value.isFinite && (0.2...5).contains(value) { grid[row * columns + column] = value }
            }
        }
        var nearest: Double?
        // Each supported 2×2 patch is independent: gradual planes are allowed,
        // but three disconnected speckles do not corroborate each other.
        for row in 0..<(rows - 1) {
            for column in 0..<(columns - 1) {
                let indices = [row * columns + column, row * columns + column + 1,
                               (row + 1) * columns + column, (row + 1) * columns + column + 1]
                let values = indices.compactMap { grid[$0] }.sorted()
                guard values.count >= 3 else { continue }
                // Reject depth edges; accept three of four mutually close returns.
                for start in 0...(values.count - 3) {
                    let triple = Array(values[start..<(start + 3)])
                    let middle = triple[1]
                    guard triple[2] - triple[0] <= max(0.1, middle * 0.1) else { continue }
                    nearest = min(nearest ?? middle, middle)
                }
            }
        }
        return nearest
    }
}
