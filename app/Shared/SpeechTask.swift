import Foundation

enum SpeechTaskError: Error, Equatable {
    case timedOut
    case alreadyAwaited
}

/// A single speech operation whose caller can stop waiting independently of Core ML.
/// Cancellation cannot interrupt every Core ML call. Keep this job quarantined while
/// `isRunning` is true; `onFinish` owns cleanup until the operation actually returns.
final class SpeechTask: Sendable {
    private let state = State()

    init(
        operation: @escaping @Sendable () async throws -> String,
        onFinish: @escaping @Sendable () -> Void = {},
        onCompletion: @escaping @Sendable () -> Void = {}
    ) {
        let state = self.state
        let worker = Task.detached { [weak state] in
            let result: Result<String, Error>
            do {
                try Task.checkCancellation()
                result = .success(try await operation())
            } catch {
                result = .failure(error)
            }
            onFinish()
            state?.finish(result)
            onCompletion()
        }
        state.installWorker(worker)
    }

    var isRunning: Bool { state.isRunning }

    /// One consumer only. No structured child is joined when this wait ends.
    func value(timeout: Duration) async throws -> String {
        let state = self.state
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                state.wait(continuation, timeout: timeout)
            }
        } onCancel: {
            state.cancel()
        }
    }

    func cancel() { state.cancel() }

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var running = true
        private var claimed = false
        private var cancellationRequested = false
        private var terminal: Result<String, Error>?
        private var continuation: CheckedContinuation<String, Error>?
        private var worker: Task<Void, Never>?
        private var timer: Task<Void, Never>?

        var isRunning: Bool { lock.withLock { running } }

        func installWorker(_ worker: Task<Void, Never>) {
            let cancel = lock.withLock {
                guard running else { return false }
                self.worker = worker
                return cancellationRequested
            }
            if cancel { worker.cancel() }
        }

        func wait(_ continuation: CheckedContinuation<String, Error>, timeout: Duration) {
            let immediate: Result<String, Error>? = lock.withLock {
                guard !claimed else { return .failure(SpeechTaskError.alreadyAwaited) }
                claimed = true
                if let terminal { return terminal }
                self.continuation = continuation
                return nil
            }
            if let immediate {
                continuation.resume(with: immediate)
                return
            }
            guard timeout > .zero else {
                stopWaiting(with: SpeechTaskError.timedOut)
                return
            }
            let timer = Task.detached { [weak self] in
                do { try await Task.sleep(for: timeout) }
                catch { return }
                self?.stopWaiting(with: SpeechTaskError.timedOut)
            }
            let keep = lock.withLock {
                guard terminal == nil else { return false }
                self.timer = timer
                return true
            }
            if !keep { timer.cancel() }
        }

        func cancel() { stopWaiting(with: CancellationError()) }

        private func stopWaiting(with error: Error) {
            let delivery = lock.withLock { () -> Delivery? in
                guard terminal == nil else { return nil }
                let result: Result<String, Error> = .failure(error)
                terminal = result
                cancellationRequested = true
                let delivery = Delivery(
                    continuation: continuation, result: result, timer: timer, worker: worker
                )
                continuation = nil
                timer = nil
                return delivery
            }
            delivery?.send()
        }

        func finish(_ result: Result<String, Error>) {
            let delivery = lock.withLock { () -> Delivery in
                running = false
                worker = nil
                let delivery = Delivery(
                    continuation: terminal == nil ? continuation : nil,
                    result: result, timer: timer, worker: nil
                )
                if terminal == nil { terminal = result }
                continuation = nil
                timer = nil
                return delivery
            }
            delivery.send()
        }

        /// Resume and cancel outside the lock, including completion during registration.
        private struct Delivery {
            let continuation: CheckedContinuation<String, Error>?
            let result: Result<String, Error>
            let timer: Task<Void, Never>?
            let worker: Task<Void, Never>?

            func send() {
                timer?.cancel()
                worker?.cancel()
                continuation?.resume(with: result)
            }
        }
    }
}
