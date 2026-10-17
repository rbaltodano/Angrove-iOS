import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Native request ownership")
struct NativeOperationRaceTests {
    private enum Failure: Error { case stalled }

    @Test("Cancelling a request completes even while native work ignores cancellation")
    func cancelBlockedOperation() async throws {
        let native = HeldNativeCall()
        let request = Task {
            try await NativeOperationRace.run(operation: { await native.value() }) {
                try await Task.sleep(for: .milliseconds(100))
                throw Failure.stalled
            }
        }
        await native.waitUntilStarted()
        request.cancel()
        do { _ = try await request.value; Issue.record("Cancelled request returned success") }
        catch { #expect(error is CancellationError) }
        await native.release()
    }

    @Test("A late native completion cannot resume a timed-out request twice")
    func lateCompletion() async throws {
        let native = HeldNativeCall()
        let request = Task {
            try await NativeOperationRace.run(operation: { await native.value() }) {
                try await Task.sleep(for: .milliseconds(20))
                throw Failure.stalled
            }
        }
        await native.waitUntilStarted()
        do { _ = try await request.value; Issue.record("Timed-out request returned success") }
        catch { #expect(error is Failure) }
        await native.release()
        let next = try await NativeOperationRace.run(operation: { 42 }) {
            try await Task.sleep(for: .seconds(1))
            throw Failure.stalled
        }
        #expect(next == 42)
    }

    @Test("Cancellation before continuation attachment cannot start native work")
    func alreadyCancelled() async {
        let native = HeldNativeCall()
        let request = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await NativeOperationRace.run(operation: { await native.value() }) {
                throw Failure.stalled
            }
        }
        do { _ = try await request.value; Issue.record("Cancelled request returned success") }
        catch { #expect(error is CancellationError) }
        #expect(await native.startedCount == 0)
        // Release defensively if native work was admitted by a regression.
        await native.release()
    }
}

private actor HeldNativeCall {
    private var continuation: CheckedContinuation<Int, Never>?
    private var released = false
    private(set) var startedCount = 0
    func value() async -> Int {
        startedCount += 1
        if released { return 7 }
        return await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilStarted() async { while continuation == nil { await Task.yield() } }
    func release() { released = true; continuation?.resume(returning: 7); continuation = nil }
}
