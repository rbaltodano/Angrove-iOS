//
//  LiteRTLifecycleProbe.swift
//  Aquinas-iOS
//

#if DEBUG
import Foundation

/// `--litert-lifecycle-probe`: drives the app's own runtime, queue, and model (from
/// `AquinasApplicationRuntime.shared`, so the launch's model override, CPU, and idle-timeout
/// flags apply) through plan C7's lifecycle stress cases, each followed by a fresh request that
/// must succeed. Launch with `--litert-lifecycle-trace` so the overlap and memory checks have a
/// trace to read. Writes `Documents/litert-lifecycle-result.json`.
///
/// It reproduces the queue-level events (cancel, preemption, background, memory warning), not
/// the operating system's: process suspension and a real memory warning still need the app.
@MainActor
enum LiteRTLifecycleProbe {
    struct Request: Encodable {
        let question: String
        var seconds: Double = 0
        var succeeded = false
        var cancelled = false
        var text = ""
        /// Streamed updates the model delivered after the queue cancelled this request.
        var updatesAfterCancel = 0
    }

    struct Step: Encodable {
        let name: String
        var requests: [Request] = []
        var note: String?
        var passed = false
    }

    struct MemoryCheck: Encodable {
        let loadAt: String
        let beforeLoadBytes: UInt64
        let deletedAt: String
        let afterUnloadBytes: UInt64
        let ratio: Double
        let withinTenPercent: Bool
        /// The first cycle also loads the app's retrieval and embedding assets, so it is
        /// reported but not gated.
        let isWarmUp: Bool
    }

    struct Overlap: Encodable {
        let at: String
        let event: String
        let inFlight: [String]
    }

    struct Summary: Encodable {
        let startedAt: String
        var finishedAt: String?
        let launchArguments: [String]
        var steps: [Step] = []
        var overlaps: [Overlap] = []
        var memory: [MemoryCheck] = []
        var passed = false
        var error: String?
    }

    private static let questions = [
        "What does Aquinas mean by the natural law?",
        "What is the first of the five ways?",
        "What does Aquinas say about the virtue of justice?",
        "How does Aquinas define prudence?",
        "What is the relation between faith and reason?",
        "What are the first precepts of the natural law?",
        "What is the fifth way, from governance?",
        "How does Aquinas explain transubstantiation?",
        "What is the eternal law?",
        "What is the second way, from efficient causation?",
    ]
    private static var nextQuestion = 0

    static func run() async {
        let app = AquinasApplicationRuntime.shared
        var summary = Summary(
            startedAt: Date.now.ISO8601Format(),
            launchArguments: ProcessInfo.processInfo.arguments
        )
        guard let runtime = app.debugLiteRTRuntime, let lifecycle = app.debugRuntimeLifecycle
        else {
            summary.error = "No on-device runtime; check the model override."
            write(summary)
            return
        }
        let queue = app.modelTasks

        // 0. Warm-up: the first request also loads retrieval and embedding assets, which stay
        // resident, so memory baselines start after it.
        var step = Step(name: "warm-up")
        step.requests.append(await ask(queue: queue, model: app.model))
        let warmedUp = await waitForState(.unloaded, lifecycle: lifecycle, limit: .seconds(120))
        step.passed = step.requests[0].succeeded && warmedUp
        summary.steps.append(step)

        // 1. Baseline, then idle unload and reload.
        step = Step(name: "baseline-then-idle-unload")
        step.requests.append(await ask(queue: queue, model: app.model))
        let unloaded = await waitForState(.unloaded, lifecycle: lifecycle, limit: .seconds(120))
        step.note = unloaded ? "idle unload observed" : "idle unload not observed in 120 s"
        step.requests.append(await ask(queue: queue, model: app.model))
        step.passed = unloaded && step.requests.allSatisfy(\.succeeded)
        summary.steps.append(step)

        // 2. Cancel mid-generation.
        step = Step(name: "cancel-mid-generation")
        step.requests.append(await askAndCancel(queue: queue, model: app.model))
        step.requests.append(await ask(queue: queue, model: app.model))
        step.passed = step.requests[0].cancelled && step.requests[1].succeeded
        summary.steps.append(step)

        // 3. A foreground request preempts background work mid-native-stream.
        step = Step(name: "foreground-preempts-background")
        let background = BackgroundJob()
        queue.enqueue(kind: .refreshQuestionOfTheDay, priority: .background) {
            await background.run(model: app.model)
        }
        let streaming = await waitForNativeStream(limit: .seconds(60))
        step.requests.append(await ask(queue: queue, model: app.model))
        let backgroundFinished = await waitUntil(limit: .seconds(180)) { background.finished }
        step.note = "background streaming when preempted: \(streaming); "
            + "background attempts: \(background.attempts); finished: \(backgroundFinished); "
            + "succeeded: \(background.succeeded)"
        step.passed = streaming && step.requests[0].succeeded && background.succeeded
        summary.steps.append(step)

        // 4. Forced stall timeout.
        step = Step(name: "forced-stall-timeout")
        await runtime.forceStallOnce(after: .seconds(1))
        step.requests.append(await ask(queue: queue, model: app.model))
        step.requests.append(await ask(queue: queue, model: app.model))
        step.note = "first request is expected to fail with the explicit failure message"
        step.passed = !step.requests[0].succeeded && step.requests[1].succeeded
        summary.steps.append(step)

        // 5. Backgrounding during generation (queue-level; no process suspension).
        step = Step(name: "background-during-generation")
        let started = Date.now
        let backgroundRequest = Task { await ask(queue: queue, model: app.model) }
        _ = await waitForNativeStream(limit: .seconds(60))
        queue.setApplicationActive(false)
        try? await Task.sleep(for: .seconds(5))
        queue.setApplicationActive(true)
        step.requests.append(await backgroundRequest.value)
        step.requests.append(await ask(queue: queue, model: app.model))
        step.note = "backgrounded for 5 s, \(seconds(since: started)) s after submit"
        step.passed = step.requests[1].succeeded
        summary.steps.append(step)

        // 6. Memory warning while loaded and idle.
        step = Step(name: "memory-warning-idle")
        _ = await waitForState(.ready, lifecycle: lifecycle, limit: .seconds(30))
        queue.handleMemoryPressure()
        let unloadedByWarning = await waitForState(
            .unloaded, lifecycle: lifecycle, limit: .seconds(30)
        )
        step.requests.append(await ask(queue: queue, model: app.model))
        step.note = "unloaded by warning: \(unloadedByWarning)"
        step.passed = unloadedByWarning && step.requests[0].succeeded
        summary.steps.append(step)

        // 7. Memory warning during generation.
        step = Step(name: "memory-warning-during-generation")
        let warned = Task { await ask(queue: queue, model: app.model) }
        _ = await waitForNativeStream(limit: .seconds(60))
        queue.handleMemoryPressure()
        step.requests.append(await warned.value)
        step.requests.append(await ask(queue: queue, model: app.model))
        step.passed = step.requests[1].succeeded
        summary.steps.append(step)

        // Let the last conversation's native teardown and the idle unload finish before reading
        // the trace, so the final memory check has a settled sample.
        _ = await waitForState(.unloaded, lifecycle: lifecycle, limit: .seconds(120))
        try? await Task.sleep(for: .seconds(7))

        analyzeTrace(into: &summary)
        summary.passed = summary.steps.allSatisfy(\.passed)
            && summary.overlaps.isEmpty
            && summary.memory.allSatisfy { $0.isWarmUp || $0.withinTenPercent }
        summary.finishedAt = Date.now.ISO8601Format()
        write(summary)
    }

    // MARK: - Requests

    @MainActor
    private final class Box {
        var request: Request
        var done = false
        var cancelledAt: Date?
        var firstUpdate = false
        init(_ request: Request) { self.request = request }
    }

    @MainActor
    private final class BackgroundJob {
        var attempts = 0
        var finished = false
        var succeeded = false

        func run(model: any AquinasModel) async {
            attempts += 1
            do {
                _ = try await model.generateQuestionOfTheDay(
                    from: ConversationContext(transcript: [
                        .user("What does Aquinas say about the virtue of justice?", nil, []),
                        .text("Justice gives each person what is due to them."),
                    ]),
                    conversationTitle: "Justice",
                    insights: []
                )
                guard !Task.isCancelled else { return }
                succeeded = true
                finished = true
            } catch {
                guard !Task.isCancelled else { return }
                finished = true
            }
        }
    }

    private static func ask(queue: ModelTaskQueue, model: any AquinasModel) async -> Request {
        let box = enqueue(queue: queue, model: model)
        _ = await waitUntil(limit: .seconds(600)) { box.done }
        return box.request
    }

    private static func askAndCancel(
        queue: ModelTaskQueue,
        model: any AquinasModel
    ) async -> Request {
        let box = enqueue(queue: queue, model: model)
        _ = await waitUntil(limit: .seconds(120)) { box.firstUpdate }
        box.cancelledAt = .now
        box.request.cancelled = true
        queue.stopCurrent()
        // Watch for stale updates while the abandoned native call finishes.
        _ = await waitUntil(limit: .seconds(120)) {
            LiteRTLifecycleTrace.shared.inFlightKinds().isEmpty
        }
        try? await Task.sleep(for: .seconds(1))
        box.done = true
        return box.request
    }

    private static func enqueue(queue: ModelTaskQueue, model: any AquinasModel) -> Box {
        let question = questions[nextQuestion % questions.count]
        nextQuestion += 1
        let box = Box(Request(question: question))
        let start = ContinuousClock.now
        queue.enqueue(
            kind: .userQuestion(branchID: UUID(), responseIndex: 1),
            onCancel: { box.done = box.done || box.request.cancelled }
        ) {
            let response = await model.respond(
                to: ConversationContext(transcript: [.user(question, nil, [])]),
                thinkingEnabled: false,
                onUpdate: { _ in
                    box.firstUpdate = true
                    if box.cancelledAt != nil { box.request.updatesAfterCancel += 1 }
                }
            )
            guard box.cancelledAt == nil else { return }
            box.request.seconds = seconds(since: start)
            box.request.text = String(response.text.prefix(300))
            box.request.succeeded = !response.text.contains("couldn't complete")
                && !response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            box.done = true
        }
        return box
    }

    // MARK: - Waiting

    private static func waitUntil(
        limit: Duration,
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let start = ContinuousClock.now
        while !condition() {
            guard start.duration(to: .now) < limit else { return false }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return true
    }

    private static func waitForNativeStream(limit: Duration) async -> Bool {
        await waitUntil(limit: limit) {
            LiteRTLifecycleTrace.shared.inFlightKinds().contains("native-stream")
        }
    }

    private static func waitForState(
        _ state: ModelRuntimeState,
        lifecycle: ModelRuntimeLifecycleManager,
        limit: Duration
    ) async -> Bool {
        let start = ContinuousClock.now
        while await lifecycle.currentState() != state {
            guard start.duration(to: .now) < limit else { return false }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return true
    }

    // MARK: - Trace analysis

    /// Overlap: a new engine load, or a new conversation, starting while other native work is
    /// still running. Memory: each engine's footprint just before it loaded against the
    /// footprint the moment its native delete finished.
    private static func analyzeTrace(into summary: inout Summary) {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?.appending(path: "litert-lifecycle.jsonl"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            summary.error = "No lifecycle trace; launch with --litert-lifecycle-trace."
            return
        }
        let events = text.split(separator: "\n").compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
        var running: [String: Int] = [:]
        var lastLoad: (at: String, bytes: UInt64)?
        var cycles = 0
        for event in events {
            let name = event["event"] as? String ?? ""
            let kind = event["kind"] as? String ?? ""
            let at = event["at"] as? String ?? ""
            let bytes = (event["physFootprint"] as? NSNumber)?.uint64Value ?? 0
            if name == "native-begin", kind == "load" || kind == "create-conversation" {
                let others = running.filter { $0.value > 0 }.map(\.key).sorted()
                if !others.isEmpty {
                    summary.overlaps.append(Overlap(at: at, event: kind, inFlight: others))
                }
            }
            if name == "native-begin" { running[kind, default: 0] += 1 }
            if name == "native-end" { running[kind, default: 0] -= 1 }
            if name == "load-begin" { lastLoad = (at, bytes) }
            if name == "native-end", kind == "engine-delete", let load = lastLoad, load.bytes > 0 {
                let ratio = Double(bytes) / Double(load.bytes)
                summary.memory.append(MemoryCheck(
                    loadAt: load.at,
                    beforeLoadBytes: load.bytes,
                    deletedAt: at,
                    afterUnloadBytes: bytes,
                    ratio: ratio,
                    withinTenPercent: ratio <= 1.10,
                    isWarmUp: cycles == 0
                ))
                cycles += 1
                lastLoad = nil
            }
        }
    }

    private static func write(_ summary: Summary) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let documents = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first, let data = try? encoder.encode(summary) else { return }
        try? data.write(
            to: documents.appending(path: "litert-lifecycle-result.json"),
            options: .atomic
        )
    }

    private static func seconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now).components
        return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
    }

    private static func seconds(since start: Date) -> Double {
        Date.now.timeIntervalSince(start)
    }
}
#endif
