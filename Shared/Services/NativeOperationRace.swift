import Foundation

/// A cancelled or timed-out Swift request stops waiting without joining a blocked native call.
/// The native owner must still track the abandoned operation until its actual completion.
nonisolated enum NativeOperationRace {
    static func run<Value: Sendable>(
        operation: @escaping @Sendable @concurrent () async throws -> Value,
        watchdog: @escaping @Sendable () async throws -> Void
    ) async throws -> Value {
        let state = RaceState<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.attach(continuation)
                guard !Task.isCancelled else {
                    state.finish(.failure(CancellationError()))
                    return
                }
                let work = Task {
                    do {
                        try Task.checkCancellation()
                        let value = try await operation()
                        try Task.checkCancellation()
                        state.finish(.success(value))
                    } catch { state.finish(.failure(error)) }
                }
                state.attach(work)
                let timer = Task {
                    do {
                        try Task.checkCancellation()
                        try await watchdog()
                    } catch is CancellationError {
                        return
                    } catch { state.finish(.failure(error)) }
                }
                state.attach(timer)
            }
        } onCancel: {
            state.finish(.failure(CancellationError()))
        }
    }
}

private nonisolated final class RaceState<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?
    private var continuation: CheckedContinuation<Value, Error>?
    private var tasks: [Task<Void, Never>] = []

    func attach(_ continuation: CheckedContinuation<Value, Error>) {
        let completed = lock.withLock { () -> Result<Value, Error>? in
            if let result { return result }
            self.continuation = continuation
            return nil as Result<Value, Error>?
        }
        if let completed { continuation.resume(with: completed) }
    }

    func attach(_ task: Task<Void, Never>) {
        let completed = lock.withLock {
            guard result == nil else { return true }
            tasks.append(task)
            return false
        }
        if completed { task.cancel() }
    }

    func finish(_ result: Result<Value, Error>) {
        let completed = lock.withLock { () -> (CheckedContinuation<Value, Error>?, [Task<Void, Never>])? in
            guard self.result == nil else { return nil }
            self.result = result
            let completed = (continuation, tasks)
            continuation = nil
            tasks = []
            return completed
        }
        guard let (continuation, tasks) = completed else { return }
        tasks.forEach { $0.cancel() }
        continuation?.resume(with: result)
    }
}
