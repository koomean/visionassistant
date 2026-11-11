import AVFoundation
import CoreHaptics
import Observation
import UIKit

enum ObstacleMonitoringState: Equatable, Sendable {
    case off, unavailable, paused, waiting, clear, warning, failed
}

/// Owns only the proximity filter and a small transient haptic player. Camera
/// buffers stay on CaptureEngine's queue; this object receives one scalar at 5Hz.
@MainActor @Observable
final class ObstacleHaptics {
    static let enabledKey = "lunav.obstacle.enabled"
    static let warningKey = "lunav.obstacle.warningDistance"
    static let closeKey = "lunav.obstacle.closeDistance"
    static let intensityKey = "lunav.obstacle.maxIntensity"

    private var savedConfiguration: ObstacleWarningConfiguration
    var configuration: ObstacleWarningConfiguration {
        get { savedConfiguration }
        set {
            let normalized = newValue.normalized
            guard normalized != savedConfiguration else { return }
            savedConfiguration = normalized
            defaults.set(normalized.enabled, forKey: Self.enabledKey)
            defaults.set(normalized.warningDistance, forKey: Self.warningKey)
            defaults.set(normalized.closeDistance, forKey: Self.closeKey)
            defaults.set(normalized.maxIntensity, forKey: Self.intensityKey)
            // The owner rearms with the new configuration. Never play a pulse
            // calculated using the old settings while a slider is moving.
            suspend()
        }
    }
    let isSupported: Bool
    private(set) var state: ObstacleMonitoringState = .off
    private(set) var distanceMeters: Double?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var policy = ObstacleWarningPolicy()
    @ObservationIgnored private var pulseTask: Task<Void, Never>?
    @ObservationIgnored private var hapticEngine: CHHapticEngine?
    @ObservationIgnored private var player: (any CHHapticPatternPlayer)?
    @ObservationIgnored private var lastPulseTime: TimeInterval = -.infinity
    @ObservationIgnored private var monitoring = false
    @ObservationIgnored private var hapticFailed = false
    @ObservationIgnored private var engineRevision = UUID()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var saved = ObstacleWarningConfiguration()
        saved.enabled = defaults.bool(forKey: Self.enabledKey)
        if defaults.object(forKey: Self.warningKey) != nil { saved.warningDistance = defaults.double(forKey: Self.warningKey) }
        if defaults.object(forKey: Self.closeKey) != nil { saved.closeDistance = defaults.double(forKey: Self.closeKey) }
        if defaults.object(forKey: Self.intensityKey) != nil { saved.maxIntensity = defaults.double(forKey: Self.intensityKey) }
        savedConfiguration = saved.normalized
        isSupported = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) != nil
            && CHHapticEngine.capabilitiesForHardware().supportsHaptics
        state = configuration.enabled ? (isSupported ? .paused : .unavailable) : .off
    }

    func setActive(_ active: Bool, streamAvailable: Bool) {
        suspend()
        guard configuration.enabled else { state = .off; return }
        guard isSupported else { state = .unavailable; return }
        guard active else { state = .paused; return }
        guard streamAvailable else { state = .unavailable; return }
        monitoring = true
        hapticFailed = false
        state = .waiting
        pulseTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.tick()
                do { try await Task.sleep(for: .milliseconds(50)) }
                catch { return }
            }
        }
    }

    func suspend() {
        monitoring = false
        pulseTask?.cancel()
        pulseTask = nil
        policy.reset()
        distanceMeters = nil
        lastPulseTime = -.infinity
        stopHaptics()
        state = configuration.enabled ? (isSupported ? .paused : .unavailable) : .off
    }

    func receive(distance: Double?, timestamp: TimeInterval) {
        guard monitoring, !hapticFailed, configuration.enabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard timestamp.isFinite, timestamp <= now, now - timestamp <= ObstacleWarningPolicy.staleInterval else { return }
        policy.receive(distance, at: timestamp)
        tick()
    }

    /// One independent preview pulse. It does not start live sensing or opt in.
    func testVibration() {
        guard isSupported, UIApplication.shared.applicationState == .active else { return }
        do {
            try play(intensity: configuration.maxIntensity)
            hapticFailed = false
            // A settings preview must release its engine even when monitoring
            // is off/paused. An active live stream owns its normal pulse cycle.
            let revision = engineRevision
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, self.engineRevision == revision, !self.monitoring else { return }
                self.stopHaptics()
            }
        } catch { hapticFailed = true; state = .failed; stopHaptics() }
    }

    private func tick() {
        guard monitoring, !hapticFailed else { return }
        guard UIApplication.shared.applicationState == .active,
              ProcessInfo.processInfo.thermalState != .serious,
              ProcessInfo.processInfo.thermalState != .critical else { suspend(); return }
        let now = ProcessInfo.processInfo.systemUptime
        distanceMeters = policy.isFresh(at: now) ? policy.distance : nil
        guard let pulse = policy.pulse(at: now, configuration: configuration) else {
            state = distanceMeters == nil ? .waiting : .clear
            // A transient ends by itself, but stopping its player also cancels a
            // sample preview if measurements have just become unavailable.
            try? player?.stop(atTime: CHHapticTimeImmediate)
            player = nil
            return
        }
        state = .warning
        guard now - lastPulseTime >= pulse.interval else { return }
        do {
            try play(intensity: pulse.intensity)
            lastPulseTime = now
        } catch { hapticFailed = true; state = .failed; stopHaptics() }
    }

    private func play(intensity: Double) throws {
        if hapticEngine == nil {
            let engine = try CHHapticEngine()
            let revision = UUID()
            engineRevision = revision
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = true
            engine.resetHandler = { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.engineRevision == revision else { return }
                    self.player = nil
                    self.hapticEngine = nil
                    self.hapticFailed = true
                    self.state = .failed
                }
            }
            engine.stoppedHandler = { [weak self] reason in
                // Idle auto-shutdown and our own stop are expected. Hardware or
                // audio interruptions must stop the cue until it is rearmed.
                guard reason != .idleTimeout, reason != .notifyWhenFinished else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.engineRevision == revision, self.monitoring else { return }
                    self.player = nil
                    self.hapticFailed = true
                    self.state = .failed
                }
            }
            hapticEngine = engine
        }
        guard let hapticEngine else { return }
        try hapticEngine.start()
        let event = CHHapticEvent(eventType: .hapticTransient,
            parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity)),
                         CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(0.25 + 0.5 * intensity))],
            relativeTime: 0)
        let pattern = try CHHapticPattern(events: [event], parameters: [])
        try? player?.stop(atTime: CHHapticTimeImmediate)
        let next = try hapticEngine.makePlayer(with: pattern)
        player = next
        try next.start(atTime: CHHapticTimeImmediate)
    }

    private func stopHaptics() {
        engineRevision = UUID()
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        // Detach handlers first: an intentional stop must not mark a newly
        // resumed monitor as failed when its callback arrives asynchronously.
        hapticEngine?.stoppedHandler = { _ in }
        hapticEngine?.resetHandler = {}
        hapticEngine?.stop(completionHandler: nil)
        hapticEngine = nil
    }
}
