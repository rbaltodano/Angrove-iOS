import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Model delivery presentation and recovery")
struct ModelDeliveryStateTests {
    @Test("Unknown total stays indeterminate; invalid byte progress is clamped")
    func progress() {
        #expect(ModelDeliveryPhase.downloading(completed: 10, total: 0).fractionCompleted == nil)
        #expect(ModelDeliveryPhase.downloading(completed: -5, total: 10).fractionCompleted == 0)
        #expect(ModelDeliveryPhase.downloading(completed: 12, total: 10).fractionCompleted == 1)
        #expect(ModelDeliveryPhase.downloading(completed: 5, total: 10).fractionCompleted == 0.5)
        #expect(ModelDeliveryPhase.verifying.fractionCompleted == nil)
    }

    @Test("Storage errors wrapped by URLSession produce storage recovery instructions")
    func wrappedStorageFailure() {
        let disk = NSError(domain: NSPOSIXErrorDomain, code: 28)
        let outer = NSError(domain: NSURLErrorDomain, code: URLError.cannotWriteToFile.rawValue,
                            userInfo: [NSUnderlyingErrorKey: disk])
        #expect(ModelDeliveryFailure.classify(outer) == .storage)
        #expect(ModelDeliveryFailure.classify(CocoaError(.fileWriteOutOfSpace)) == .storage)
        #expect(ModelDeliveryFailure.classify(URLError(.notConnectedToInternet)) == .network)
        #expect(ModelDeliveryFailure.classify(LiteRTModelStoreError.invalidModelDigest) == .integrity)
    }

    @Test("Repeated retry taps share one preparation and only success becomes ready")
    @MainActor func retryCoalesces() async throws {
        let probe = PreparationProbe()
        let state = ModelDeliveryState(prepare: { try await probe.prepare() })
        state.update(.notInstalled)
        state.retry()
        state.retry()
        try await waitUntil { state.phase == .ready }
        #expect(await probe.calls == 1)
    }

    @Test("An interrupted download can be retried without recreating the app state")
    @MainActor func interruptedThenRetry() async throws {
        let probe = PreparationProbe(failFirst: true)
        let state = ModelDeliveryState(prepare: { try await probe.prepare() })
        state.update(.notInstalled)
        state.retry()
        try await waitUntil { state.phase == .failed(.network) }
        state.retry()
        try await waitUntil { state.phase == .ready }
        #expect(await probe.calls == 2)
    }

    @Test("Completed asset preparation ignores late download observer updates")
    @MainActor func lateProgress() async {
        let state = ModelDeliveryState(prepare: {})
        let relay = ModelDeliveryStatusRelay(report: { await state.update($0) })
        await relay.send(.waiting)
        #expect(state.phase == .waiting)
        await relay.close()
        state.update(.verifying)
        await relay.send(.downloading(completed: 1, total: 10))
        #expect(state.phase == .verifying)
        state.update(.ready)
        await relay.send(.failed(.network))
        #expect(state.phase == .ready)
    }

    @MainActor private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}

private actor PreparationProbe {
    private(set) var calls = 0
    let failFirst: Bool
    init(failFirst: Bool = false) { self.failFirst = failFirst }
    func prepare() async throws {
        calls += 1
        try await Task.sleep(for: .milliseconds(30))
        if failFirst && calls == 1 { throw URLError(.notConnectedToInternet) }
    }
}
