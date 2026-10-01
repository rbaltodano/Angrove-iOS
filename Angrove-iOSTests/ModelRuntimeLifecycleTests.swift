import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Adaptive model runtime lifecycle")
struct ModelRuntimeLifecycleTests {
    @Test("Short foreground pauses keep the model warm")
    func shortPauseKeepsModelWarm() async throws {
        let driver = TestModelRuntimeDriver()
        // A generous idle timeout, so a slow CI machine can't stretch the short pause past it.
        let manager = makeManager(
            driver: driver,
            normalTimeout: 5,
            seriousTimeout: 1
        )

        let lease = try #require(await manager.acquireLease())
        await manager.releaseLease(lease)
        try await Task.sleep(for: .milliseconds(40))

        #expect(await manager.currentState() == .ready)
        #expect(await driver.unloadCount == 0)
    }

    @Test("Normal idle timeout unloads the model")
    func normalIdleTimeoutUnloads() async throws {
        let driver = TestModelRuntimeDriver()
        let manager = makeManager(
            driver: driver,
            normalTimeout: 0.03,
            seriousTimeout: 0.01
        )

        let lease = try #require(await manager.acquireLease())
        await manager.releaseLease(lease)
        try await waitUntil { await manager.currentState() == .unloaded }

        #expect(await driver.unloadCount == 1)
    }

    @Test("Serious thermal pressure shortens an existing idle timer")
    func seriousThermalPressureShortensTimeout() async throws {
        let driver = TestModelRuntimeDriver()
        let manager = makeManager(
            driver: driver,
            normalTimeout: 1,
            seriousTimeout: 0.03
        )

        let lease = try #require(await manager.acquireLease())
        await manager.releaseLease(lease)
        await manager.updateThermalPressure(.serious)
        try await waitUntil { await manager.currentState() == .unloaded }

        #expect(await driver.unloadCount == 1)
    }

    @Test("An active generation lease blocks immediate unloading")
    func activeLeaseBlocksUnload() async throws {
        let driver = TestModelRuntimeDriver()
        let manager = makeManager(driver: driver)
        let lease = try #require(await manager.acquireLease())

        let unloadRequest = Task {
            await manager.unloadAsSoonAsIdle(reason: .memoryPressure)
        }
        try await Task.sleep(for: .milliseconds(30))
        #expect(await manager.currentState() == .generating)
        #expect(await driver.unloadCount == 0)

        await manager.releaseLease(lease)
        await unloadRequest.value
        #expect(await manager.currentState() == .unloaded)
        #expect(await driver.unloadCount == 1)
    }

    @Test("The first task after unloading performs one clean reload")
    func coldTaskReloadsOnce() async throws {
        let driver = TestModelRuntimeDriver()
        let manager = makeManager(driver: driver)

        let firstLease = try #require(await manager.acquireLease())
        await manager.releaseLease(firstLease)
        await manager.unloadAsSoonAsIdle(reason: .background)
        let secondLease = try #require(await manager.acquireLease())

        #expect(await driver.loadCount == 2)
        #expect(await manager.currentState() == .generating)
        await manager.releaseLease(secondLease)
    }

    @Test("A runtime without unloadable weights remains resident")
    func residentRuntimeIgnoresUnloadRequests() async {
        let manager = ModelRuntimeLifecycleManager()

        await manager.unloadAsSoonAsIdle(reason: .memoryPressure)

        #expect(await manager.currentState() == .ready)
        #expect(await manager.requiresLoadingForNextLease() == false)
    }

    @MainActor
    @Test("Backgrounding preserves and retries background queue work")
    func backgroundingPreservesBackgroundWork() async throws {
        let driver = TestModelRuntimeDriver()
        let manager = makeManager(driver: driver)
        let queue = ModelTaskQueue(runtimeLifecycle: manager)
        let attempts = TestAttemptCounter()

        queue.enqueue(kind: .refreshQuestionOfTheDay, priority: .background) {
            // The first attempt stays busy until backgrounding preempts it; the retry finishes
            // at once. A fixed short sleep let slow CI machines finish the first attempt
            // before the test could background the app.
            if await attempts.started() == 1 {
                try? await Task.sleep(for: .seconds(30))
            }
            guard !Task.isCancelled else { return }
            await attempts.completed()
        }
        try await waitUntil { await attempts.startCount == 1 }

        queue.setApplicationActive(false)
        try await waitUntil { await manager.currentState() == .unloaded }
        #expect(queue.upcomingTasks.count == 1)

        queue.setApplicationActive(true)
        try await waitUntil { await attempts.completionCount == 1 }
        #expect(await attempts.startCount == 2)
    }

    @MainActor
    @Test("Latest completion retains its origin after completed rows clear")
    func latestCompletionRetainsOrigin() async throws {
        let driver = TestModelRuntimeDriver()
        let queue = ModelTaskQueue(runtimeLifecycle: makeManager(driver: driver))

        let taskID = queue.enqueue(
            kind: .refreshQuestionOfTheDay,
            originPage: .studyTopics
        ) { }

        try await waitUntil { await queue.latestCompletedTask?.id == taskID }
        #expect(queue.latestCompletedTask?.originPage == .studyTopics)

        // Completed rows clear 0.7 s after finishing; wait for that rather than a fixed sleep.
        try await waitUntil { await queue.completedTasks.isEmpty }
        #expect(queue.latestCompletedTask?.id == taskID)
    }

    @MainActor
    @Test("A midpoint queued behind questions runs last and cancels nothing")
    func midpointJoinsBottomOfQueueWithoutCancelling() async throws {
        let queue = ModelTaskQueue(runtimeLifecycle: makeManager(driver: TestModelRuntimeDriver()))
        let log = TestEventLog()
        let gate = TestGate()

        queue.enqueue(
            kind: .userQuestion(branchID: UUID(), responseIndex: 1),
            onCancel: { Task { await log.record("cancel first") } }
        ) {
            await gate.wait()
            await log.record("first")
        }
        queue.enqueue(
            kind: .userQuestion(branchID: UUID(), responseIndex: 1),
            onCancel: { Task { await log.record("cancel second") } }
        ) { await log.record("second") }
        queue.enqueue(
            kind: .createMidpoint,
            onCancel: { Task { await log.record("cancel midpoint") } }
        ) { await log.record("midpoint") }

        await gate.open()
        try await waitUntil { await log.events.count == 3 }
        #expect(await log.events == ["first", "second", "midpoint"])
    }

    @Test("An unload that waited on a load never drops a model a request has leased")
    func unloadDuringLoadYieldsToLease() async throws {
        let gate = TestGate()
        let driver = TestModelRuntimeDriver(loadGate: gate)
        let manager = makeManager(driver: driver)

        let leaseTask = Task { await manager.acquireLease() }
        try await waitUntil { await driver.loadCount == 1 }
        let unloadTask = Task { await manager.unloadAsSoonAsIdle(reason: .memoryPressure) }
        try await Task.sleep(for: .milliseconds(50))
        await gate.open()

        // Either side may win once the load finishes. The invariant: a granted lease is never
        // followed by an unload of the model it leased.
        let lease = await leaseTask.value
        await unloadTask.value
        if let lease {
            #expect(await driver.unloadCount == 0)
            #expect(await manager.currentState() == .generating)
            await manager.releaseLease(lease)
        } else {
            #expect(await driver.unloadCount == 1)
        }
    }

    @MainActor
    @Test("Reordering upcoming tasks changes the order they run in")
    func reorderedUpcomingTasksRunInNewOrder() async throws {
        let queue = ModelTaskQueue(runtimeLifecycle: makeManager(driver: TestModelRuntimeDriver()))
        let log = TestEventLog()
        let gate = TestGate()

        queue.enqueue(kind: .userQuestion(branchID: UUID(), responseIndex: 1)) {
            await gate.wait()
            await log.record("running")
        }
        let second = queue.enqueue(kind: .userQuestion(branchID: UUID(), responseIndex: 1)) {
            await log.record("second")
        }
        let third = queue.enqueue(kind: .userQuestion(branchID: UUID(), responseIndex: 1)) {
            await log.record("third")
        }
        try await waitUntil { await queue.currentTask != nil }

        #expect(queue.moveUpcoming(id: third, relativeTo: second, placeAfterTarget: false))
        #expect(queue.upcomingTasks.map(\.id) == [third, second])

        await gate.open()
        try await waitUntil { await log.events.count == 3 }
        #expect(await log.events == ["running", "third", "second"])
    }

    @MainActor
    @Test("A midpoint placed during background tree work leaves that work queued, not lost")
    func midpointDuringBackgroundWorkKeepsBackgroundWork() async throws {
        let queue = ModelTaskQueue(runtimeLifecycle: makeManager(driver: TestModelRuntimeDriver()))
        let log = TestEventLog()
        let attempts = TestAttemptCounter()

        queue.enqueue(kind: .updateInsightTree, priority: .background) {
            if await attempts.started() == 1 {
                try? await Task.sleep(for: .seconds(30))
            }
            guard !Task.isCancelled else { return }
            await log.record("tree")
        }
        try await waitUntil { await attempts.startCount == 1 }

        queue.enqueue(kind: .createMidpoint) { await log.record("midpoint") }
        try await waitUntil { await log.events.count == 2 }
        #expect(await log.events == ["midpoint", "tree"])
    }

    @MainActor
    @Test("Follow-up tree work runs before questions that were already waiting")
    func runsNextPlacesTreeWorkAheadOfWaitingQuestions() async throws {
        let queue = ModelTaskQueue(runtimeLifecycle: makeManager(driver: TestModelRuntimeDriver()))
        let log = TestEventLog()
        let gate = TestGate()

        queue.enqueue(kind: .userQuestion(branchID: UUID(), responseIndex: 1)) {
            await gate.wait()
            await log.record("first")
        }
        queue.enqueue(kind: .userQuestion(branchID: UUID(), responseIndex: 1)) {
            await log.record("second")
        }
        queue.enqueue(kind: .updateInsightTree, priority: .foreground, runsNext: true) {
            await log.record("tree")
        }

        await gate.open()
        try await waitUntil { await log.events.count == 3 }
        #expect(await log.events == ["first", "tree", "second"])
    }

    private func makeManager(
        driver: TestModelRuntimeDriver,
        normalTimeout: TimeInterval = 10,
        seriousTimeout: TimeInterval = 1
    ) -> ModelRuntimeLifecycleManager {
        ModelRuntimeLifecycleManager(
            driver: driver,
            configuration: ModelRuntimeLifecycleConfiguration(
                retentionPolicy: .adaptive,
                normalIdleTimeout: normalTimeout,
                seriousThermalIdleTimeout: seriousTimeout
            )
        )
    }

    private func waitUntil(
        // Generous for slow CI machines; passing checks return as soon as the condition holds.
        timeout: Duration = .seconds(10),
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Condition did not become true before the timeout.")
    }
}

private actor TestModelRuntimeDriver: ModelRuntimeDriver {
    nonisolated let supportsUnloading = true
    private(set) var loadCount = 0
    private(set) var unloadCount = 0
    /// When set, each load waits for this gate, so a test can act while a load is in flight.
    let loadGate: TestGate?

    init(loadGate: TestGate? = nil) {
        self.loadGate = loadGate
    }

    func loadModelWeights() async throws {
        loadCount += 1
        await loadGate?.wait()
    }

    func unloadModelWeights() async {
        unloadCount += 1
    }
}

private actor TestAttemptCounter {
    private(set) var startCount = 0
    private(set) var completionCount = 0

    /// Records a start and returns which attempt this is (1 for the first).
    @discardableResult
    func started() -> Int {
        startCount += 1
        return startCount
    }

    func completed() {
        completionCount += 1
    }
}

private actor TestEventLog {
    private(set) var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }
}

private actor TestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}
