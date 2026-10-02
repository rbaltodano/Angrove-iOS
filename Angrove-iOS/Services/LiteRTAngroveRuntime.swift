//
//  LiteRTAngroveRuntime.swift
//  Angrove-iOS
//

import Foundation
import LiteRTLM
import OSLog

/// Resumes a `CheckedContinuation` at most once, whichever of two racing unstructured `Task`s
/// gets there first. A plain `Task.isCancelled` check isn't enough here since the loser (a
/// wedged native call) never reaches its own cancellation checkpoint — this lock is what actually
/// prevents a double-resume when both sides eventually try.
nonisolated private final class StallRaceBox<T>: @unchecked Sendable {
    private let continuation: CheckedContinuation<T, Error>
    private let lock = NSLock()
    private var didResume = false

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<T, Error>) {
        lock.lock()
        let shouldResume = !didResume
        didResume = true
        lock.unlock()
        guard shouldResume else { return }
        continuation.resume(with: result)
    }
}

nonisolated enum LiteRTAngroveRuntimeError: LocalizedError, Sendable {
    case modelNotLoaded
    case emptyResponse
    case repetitiveResponse
    case corruptResponse
    case stalledGeneration

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            "The Angrove on-device runtime is not loaded."
        case .emptyResponse:
            "Angrove returned an empty response."
        case .repetitiveResponse:
            "The on-device model entered a repetitive response loop."
        case .corruptResponse:
            "The on-device model returned malformed mixed-script tokens."
        case .stalledGeneration:
            "The on-device model stopped producing output."
        }
    }
}

/// Owns the process-wide LiteRT engine and at most one active native conversation. The
/// `ModelTaskQueue` supplies exclusive generation leases; actor isolation additionally protects
/// direct callers and makes cancellation safe.
actor LiteRTAngroveRuntime: ModelRuntimeDriver {
    let supportsUnloading = true

    private let modelStore: LiteRTModelStore
#if DEBUG
    /// `--litert-force-cpu` runs the full app on the CPU executor (plan C7: the simulator's
    /// Metal limits reject some packages on GPU).
    private var evidenceExperimentUsesCPU = ProcessInfo.processInfo.arguments
        .contains("--litert-force-cpu")
    /// `--litert-stall-once-seconds <n>` lowers the stall watchdog until it fires once, forcing
    /// one stall timeout (plan C7); every later request uses the production value.
    private var forcedStallTimeout: Duration? = LiteRTProbeArguments
        .value(after: "--litert-stall-once-seconds", in: ProcessInfo.processInfo.arguments)
        .flatMap(Int.init)
        .map { .seconds($0) }

    func configureEvidenceExperimentCPU() {
        precondition(engine == nil)
        evidenceExperimentUsesCPU = true
    }

    /// Diagnostic only (plan C8 step 5): replaces conversation (non-structured) sampling so an
    /// evaluation can observe sampled decoding. Production decoding never sets it.
    private var evidenceConversationSampling: LiteRTSampling?

    func configureEvidenceConversationSampling(_ sampling: LiteRTSampling) {
        evidenceConversationSampling = sampling
    }

    /// Lowers the stall watchdog until it fires once (the lifecycle probe's forced stall).
    func forceStallOnce(after timeout: Duration) {
        forcedStallTimeout = timeout
    }
#endif
    private var engine: Engine?
    private var activeConversation: Conversation?
    private var lastLoadError: Error?
    private var completedGenerations = 0
    private var pendingTeardownDrain = false
    private var generationSlotHeld = false
    private var generationWaiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []
    private var lastTokenAt: ContinuousClock.Instant = .now
    /// When the stall watchdog last checked in, or its window opened; see `hasStalled()`.
    private var lastStallCheckAt: ContinuousClock.Instant?
    /// The conversation of a generation this runtime stopped waiting for (a stall, a guard
    /// rejection, or any other thrown error) while its native stream may still be running. The
    /// wrapper's stream context keeps it alive until the native side finishes, so it turns `nil`
    /// exactly when that native work ends. See `waitForAbandonedNativeWork()`.
    private weak var abandonedConversation: Conversation?
    private var didLogLoadedModel = false
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.aquinas",
        category: "LiteRTAngroveRuntime"
    )

    private static let generationsBeforeRefresh = 4
    /// Native decoding has no built-in time cutoff (by design — see MODEL-INTEGRATION.md), so a
    /// wedged call would otherwise hang indefinitely with no recovery short of the user finding
    /// Model Tasks and tapping Stop. This only fires when literally nothing has streamed back for
    /// this long — generous relative to the ~1.3s/sentence baseline — so it never interrupts a
    /// merely slow but progressing generation, only a genuinely stalled one.
    private static let stallTimeout: Duration = .seconds(45)
    /// Guards `initializeEngine()` specifically — cold load has measured ~4-5s in production, so
    /// this stays well clear of ordinary variance while still catching a genuinely wedged load.
    private static let loadStallTimeout: Duration = .seconds(60)
    /// The watchdog polls every 5 s. A gap far longer than that means the process was suspended
    /// (the app was backgrounded), which says nothing about native progress.
    private static let suspensionGap: Duration = .seconds(15)
    /// How long a new native call waits for an abandoned stream to finish before going ahead:
    /// the stall window, so a healthy stream that was merely abandoned can finish its answer.
    private static let abandonedWorkWait: Duration = .seconds(45)
    /// How long a new engine load waits for earlier engines and conversations to finish deleting.
    private static let nativeDeleteWait: Duration = .seconds(10)
    /// The production KV-cache size, shared by prompt, history, references, and answer.
    static let maxNumTokens = 4_096
    /// Gemma 4's multi-token-prediction drafter (a section of the E4B package) proposes several
    /// tokens for the main model to verify in one pass. Off for launch: on the phone GPU it saved
    /// under half a second on our short answers (median 7.1 s vs 7.5 s of generation), added
    /// variance (one 11.4 s run), and changed greedy wording (runs S1-on/off-*). Answers here are
    /// dominated by prefill, which MTP doesn't speed up. `--litert-mtp` turns it on in DEBUG.
    /// Executor activation precision (0 = F32). The E4B package prefers F16 on the GPU, but F16
    /// misreads multi-digit numbers on the phone: "John 14", "Psalm 23" and "John 11" were answered
    /// as John 4, Psalm 3 and John 1 from correct references, and the old E2B model did the same.
    /// F32 answered all three correctly at about 20% lower decode speed (runs S2-*).
    /// `--litert-f16` restores the package default in DEBUG builds, for comparison.
    static var activationDataTypeOverride: Int32? {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--litert-f16") ? nil : 0
#else
        0
#endif
    }

    static var usesSpeculativeDecoding: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--litert-mtp")
#else
        false
#endif
    }

    init(modelStore: LiteRTModelStore = LiteRTModelStore()) {
        self.modelStore = modelStore
    }

    /// Load and unload take the generation slot, like generation itself. The lifecycle manager
    /// calls them from outside that slot, and actor reentrancy otherwise lets a generation run
    /// against an engine that is half-loaded or was just dropped (seen on the phone: a request
    /// hit `modelNotLoaded` mid-load, and its retry then loaded a second engine beside the first).
    func loadModelWeights() async throws {
        try await acquireGenerationSlot()
        defer { releaseGenerationSlot() }
        try await loadEngineHoldingSlot()
    }

    func unloadModelWeights() async {
        // Never skip the slot: dropping the engine under a running generation is exactly the
        // race the slot prevents. A cancelled wait leaves the engine loaded; the next load is then
        // a no-op.
        guard (try? await acquireGenerationSlot()) != nil else { return }
        defer { releaseGenerationSlot() }
        unloadEngineHoldingSlot()
    }

    private func loadEngineHoldingSlot() async throws {
        if let engine, await engine.isInitialized() {
            return
        }

        var finalError: Error?
        for attempt in 1...2 {
            do {
                try await initializeEngine()
                return
            } catch {
                engine = nil
                lastLoadError = error
                finalError = error
#if DEBUG
                print("Angrove on-device model load attempt \(attempt) failed: \(error.localizedDescription)")
#endif
                if attempt == 1 {
                    try await Task.sleep(for: .milliseconds(250))
                }
            }
        }
        throw finalError ?? LiteRTAngroveRuntimeError.modelNotLoaded
    }

    private func unloadEngineHoldingSlot() {
        // Deliberately no `activeConversation.cancel()` here — confirmed via device console
        // capture that `litert_lm_conversation_cancel_process` can leave the native
        // `callback_thread_pool` (a single-worker pool) permanently stuck on
        // DEADLINE_EXCEEDED, wedging every later generation for the rest of the process. This
        // runs on every periodic engine refresh (`generationsBeforeRefresh`) and error-recovery
        // reinit — among the most frequently hit automatic paths in the app — so it was the
        // single biggest source of the "works once, then hangs forever" pattern. Simply
        // dropping the references is safe: the orphaned native call (if any) keeps running
        // against its own ARC-retained `Conversation`/`Engine` until it finishes on its own;
        // nothing dangles.
        //
        // v0.14.0 of the vendored LiteRTLM package removed explicit close() from both
        // Conversation and Engine; native cleanup now happens in deinit when the last
        // strong reference is released, so dropping these references is the teardown.
        let hadEngine = engine != nil
        activeConversation = nil
        engine = nil
        LiteRTLifecycleTrace.shared.record(
            "unload",
            ["hadEngine": hadEngine, "inFlight": LiteRTLifecycleTrace.shared.inFlightKinds()]
        )
#if DEBUG
        // Native teardown finishes on its own threads after the references drop; sample memory
        // once it has had time to settle (plan C7's post-unload memory check).
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(5))
            LiteRTLifecycleTrace.shared.record(
                "unload-settled",
                ["inFlight": LiteRTLifecycleTrace.shared.inFlightKinds()]
            )
        }
#endif
    }

    func generate(
        systemInstruction: String,
        initialMessages: [Message] = [],
        message: Message,
        sampling: LiteRTSampling = .conversation,
        onText: (@Sendable (String) async -> Void)? = nil,
        onThought: (@Sendable (String) async -> Void)? = nil
    ) async throws -> String {
#if DEBUG
        let sampling = sampling.isStructured ? sampling : (evidenceConversationSampling ?? sampling)
#endif
        return try await withGenerationSlot(sampling: sampling) { attemptSampling in
            try await self.generateOnce(
                systemInstruction: systemInstruction,
                initialMessages: initialMessages,
                message: message,
                sampling: attemptSampling,
                onText: onText,
                onThought: onThought
            )
        }
    }

    /// Shared serialization/refresh/retry scaffolding behind `generate`, parameterized by the
    /// actual per-attempt work so callers don't duplicate the slot, teardown-drain,
    /// periodic-refresh, or one-shot-recovery-retry logic.
    private func withGenerationSlot<T: Sendable>(
        sampling: LiteRTSampling,
        _ attempt: @Sendable (LiteRTSampling) async throws -> T
    ) async throws -> T {
        try await acquireGenerationSlot()
        defer { releaseGenerationSlot() }
        try Task.checkCancellation()

        await waitForAbandonedNativeWork()
        if pendingTeardownDrain {
            try await drainNativeTeardown()
            pendingTeardownDrain = false
        }
        // The lifecycle may have unloaded between granting this request's lease and this point;
        // load here instead of failing with `modelNotLoaded`.
        if engine == nil {
            try await loadEngineHoldingSlot()
        }

        if completedGenerations >= Self.generationsBeforeRefresh {
            unloadEngineHoldingSlot()
            try await initializeEngineWithWatchdog()
            try await drainNativeTeardown()
        }

        do {
            let result = try await attempt(sampling)
            completedGenerations += 1
            return result
        } catch {
            if error is CancellationError || Task.isCancelled {
                LiteRTLifecycleTrace.shared.record(
                    "cancelled",
                    ["inFlight": LiteRTLifecycleTrace.shared.inFlightKinds()]
                )
                throw CancellationError()
            }
            logger.error(
                "Local generation attempt failed: \(String(reflecting: error), privacy: .public)"
            )
            Self.debugConsoleLog("attempt failed: \(String(reflecting: error))")

            // A genuine stall (the watchdog gave up waiting for any native progress at all —
            // see `racingStall`) has been observed, via device console capture, to reproduce
            // identically on an immediate reinit-and-retry: the native engine reloads cleanly
            // both times, but conversation creation itself hangs the same way again, so the
            // retry just pays the full stall window a second time for no benefit — 90+ seconds
            // of "Thinking..." with zero user-visible feedback before the eventual failure.
            // Fail fast instead; only retry for other error shapes, where a fresh session has
            // actually been observed to recover.
            if case LiteRTAngroveRuntimeError.stalledGeneration = error {
                throw error
            }

            // A completed native Conversation can occasionally leave the mobile session unable
            // to create the next conversation. Rebuild the engine once and retry locally before
            // allowing the model boundary to use network recovery.
            // Rebuilding while the failed stream still runs would load a new engine next to a
            // live native session on the old one. If it hasn't ended, retry on this engine.
            if await waitForAbandonedNativeWork() {
                unloadEngineHoldingSlot()
                try await initializeEngineWithWatchdog()
            }
            try await drainNativeTeardown()
            do {
                let result = try await attempt(sampling.retryVariant)
                completedGenerations += 1
                return result
            } catch {
                logger.error(
                    "Local generation retry failed: \(String(reflecting: error), privacy: .public)"
                )
                Self.debugConsoleLog("retry failed: \(String(reflecting: error))")
                throw error
            }
        }
    }

    nonisolated private static func debugConsoleLog(_ message: String) {
#if DEBUG
        guard let data = "[LiteRTAngroveRuntime] \(message)\n".data(using: .utf8) else { return }
        try? FileHandle.standardError.write(contentsOf: data)
#endif
    }

    private func acquireGenerationSlot() async throws {
        if !generationSlotHeld {
            generationSlotHeld = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                generationWaiters.append((id, continuation))
            }
        } onCancel: {
            Task { await self.cancelGenerationWait(id: id) }
        }
    }

    /// Removes a still-waiting caller from the FIFO queue and resumes it with cancellation,
    /// instead of leaving it queued forever. Without this, a background task (e.g. Question of
    /// the Day) preempted while still waiting for the slot — its wrapping Task gets cancelled by
    /// `ModelTaskQueue`, but a plain non-throwing continuation ignores cancellation entirely —
    /// would sit as a permanent squatter, later winning the slot ahead of the actually-desired
    /// next request and forcing it to wait behind an abandoned generation nobody is listening
    /// for anymore.
    private func cancelGenerationWait(id: UUID) {
        guard let index = generationWaiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = generationWaiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func releaseGenerationSlot() {
        if generationWaiters.isEmpty {
            generationSlotHeld = false
        } else {
            let waiter = generationWaiters.removeFirst()
            waiter.continuation.resume()
        }
    }

    // Text-only. The E4B package ships a vision encoder, but it hasn't passed a load and memory
    // gate on the phone (optional plan step C12). Re-enable (.gpu) only once it has; until then
    // image turns become text notes (`supportsVision`).
    private static let visionBackend: Backend? = nil
    /// Whether image content may be sent to the engine. Without a vision executor LiteRT-LM
    /// rejects the whole request ("Vision executor should not be null").
    static let supportsVision = visionBackend != nil

    /// `Engine.close()` deletes the native handle synchronously, but the GPU backend's own
    /// worker pool can still be finishing teardown from the just-closed engine when the next
    /// engine starts its first Prefill. Give that teardown time to fully drain before use.
    private func drainNativeTeardown() async throws {
        try? await Task.sleep(for: .milliseconds(400))
    }

    /// A thrown generation (stall, guard rejection, error) stops the Swift side listening, but
    /// the native stream keeps decoding until it ends on its own: cancelling it natively can
    /// wedge LiteRT-LM's callback pool (see `unloadModelWeights`). Starting another conversation,
    /// or rebuilding the engine, while it runs puts two native sessions on one engine, or deletes
    /// the engine under a live one. Wait for it to end first, but only for a bounded time: a
    /// genuinely wedged stream never ends, and blocking every later request on it would be worse.
    /// Returns whether the abandoned stream (if any) has ended.
    @discardableResult
    private func waitForAbandonedNativeWork() async -> Bool {
        guard abandonedConversation != nil else { return true }
        let start = ContinuousClock.now
        LiteRTLifecycleTrace.shared.record("abandoned-wait-begin")
        while abandonedConversation != nil,
              start.duration(to: .now) < Self.abandonedWorkWait {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let finished = abandonedConversation == nil
        LiteRTLifecycleTrace.shared.record(
            "abandoned-wait-end",
            ["finished": finished, "seconds": Self.seconds(start.duration(to: .now))]
        )
        if !finished {
            logger.error("An abandoned native stream is still running; continuing anyway")
            abandonedConversation = nil
        }
        return finished
    }

    /// `Engine` and `Conversation` delete their native handles on detached threads after the
    /// last reference drops, so an unload returns before the old engine is gone. Loading the
    /// next engine meanwhile briefly holds two engines' memory and overlaps their native work.
    private func waitForPendingNativeDeletes() async {
        let kinds = ["engine-delete", "conversation-delete"]
        guard NativeActivityMonitor.runningCount(of: kinds) > 0 else { return }
        let start = ContinuousClock.now
        while NativeActivityMonitor.runningCount(of: kinds) > 0,
              start.duration(to: .now) < Self.nativeDeleteWait {
            try? await Task.sleep(for: .milliseconds(20))
        }
        LiteRTLifecycleTrace.shared.record(
            "delete-wait",
            ["seconds": Self.seconds(start.duration(to: .now)),
             "finished": NativeActivityMonitor.runningCount(of: kinds) == 0]
        )
    }

    private func initializeEngine() async throws {
        let modelURL = try modelStore.installedModelURL()
        let cacheURL = try modelStore.cacheDirectory()
        var backend: Backend = .gpu
#if DEBUG
        if evidenceExperimentUsesCPU { backend = .cpu() }
#endif
        let config = try EngineConfig(
            modelPath: modelURL.path,
            backend: backend,
            visionBackend: Self.visionBackend,
            maxNumTokens: Self.maxNumTokens,
            cacheDir: cacheURL.path
        )
        await waitForPendingNativeDeletes()
        ExperimentalFlags.optIntoExperimentalAPIs()
        ExperimentalFlags.enableSpeculativeDecoding = Self.usesSpeculativeDecoding
        ExperimentalFlags.activationDataType = Self.activationDataTypeOverride
        let newEngine = Engine(engineConfig: config)
        LiteRTLifecycleTrace.shared.record(
            "load-begin",
            ["inFlight": LiteRTLifecycleTrace.shared.inFlightKinds()]
        )
        try await LiteRTLifecycleTrace.shared.tracking("load") {
            try await newEngine.initialize()
        }
        engine = newEngine
        lastLoadError = nil
        completedGenerations = 0
        logLoadedModelOnce(at: modelURL)
    }

    /// Records which package this process actually loaded, once. DEBUG builds hash the file
    /// (after load, at utility priority, so the hash never warms the page cache ahead of a
    /// timed load); Release logs the manifest's declared digest rather than rereading gigabytes.
    private func logLoadedModelOnce(at modelURL: URL) {
        guard !didLogLoadedModel else { return }
        didLogLoadedModel = true
        let logger = logger
        let declaredSHA256 = modelStore.manifest.sha256
#if DEBUG
        Task.detached(priority: .utility) {
            let digest = (try? LiteRTModelInstaller.sha256(of: modelURL)) ?? "unreadable"
            logger.notice(
                "Loaded model \(modelURL.path, privacy: .public) sha256=\(digest, privacy: .public) (computed; manifest \(declaredSHA256, privacy: .public))"
            )
            Self.debugConsoleLog(
                "loaded model \(modelURL.path) sha256=\(digest) (computed; manifest \(declaredSHA256))"
            )
        }
#else
        logger.notice(
            "Loaded model \(modelURL.path, privacy: .public) sha256=\(declaredSHA256, privacy: .public) (manifest)"
        )
#endif
    }

    /// A hung `initializeEngine()` sits outside `generateOnce`'s own watchdog entirely — it runs
    /// in `generate()` before that call even starts — and would otherwise leave the actor's
    /// generation slot held forever, blocking every later call (including from unrelated model
    /// tasks) behind it indefinitely. Generous relative to the ~4-5s cold load this build has
    /// measured, so it only fires on a genuine hang, not ordinary load variance.
    private func initializeEngineWithWatchdog() async throws {
        try await Self.abandoningStall(timeout: Self.loadStallTimeout) {
            try await self.initializeEngine()
        } onTimeout: {}
    }

    private func generateOnce(
        systemInstruction: String,
        initialMessages: [Message],
        message: Message,
        sampling: LiteRTSampling,
        onText: (@Sendable (String) async -> Void)?,
        onThought: (@Sendable (String) async -> Void)?
    ) async throws -> String {
        guard let engine, await engine.isInitialized() else {
            throw lastLoadError ?? LiteRTAngroveRuntimeError.modelNotLoaded
        }

        // Conversation creation is itself a native call and has hung in practice — it needs its
        // own watchdog race, not to run unguarded before streaming's, or a wedged create leaves
        // this whole call (and the generation slot every later call queues behind) blocked
        // forever with no watchdog ever having started.
        let conversation = try await racingStall {
            try await LiteRTLifecycleTrace.shared.tracking("create-conversation") {
                try await self.makeConversation(
                    engine: engine,
                    systemInstruction: systemInstruction,
                    initialMessages: initialMessages,
                    sampling: sampling
                )
            }
        }
#if DEBUG
        let recordIndex = Self.recordGenerationStart(
            conversation: conversation,
            systemInstruction: systemInstruction,
            initialMessages: initialMessages,
            message: message,
            sampling: sampling
        )
#endif
        do {
            let result = try await racingStall {
                try await LiteRTLifecycleTrace.shared.tracking("generate") {
                    try await self.streamText(
                        on: conversation,
                        message: message,
                        // The repetition/corruption guard was built for — and, per its own doc
                        // comment, deliberately requires substantial repetition before firing —
                        // free-form conversational prose, where a genuine degenerate
                        // greedy-decoding loop is the real risk. Confirmed via device console
                        // capture that it also fires on short structured JSON payloads: cutting a
                        // ~26-word label+summary off mid-string, before the closing `"}`,
                        // guarantees a JSON parse failure — a worse outcome than the rare case this
                        // guard exists to prevent. Structured calls are short and bounded already;
                        // skip it.
                        appliesDegenerateOutputGuard: !sampling.isStructured,
                        onText: onText,
                        onThought: onThought
                    )
                }
            }
#if DEBUG
            if let recordIndex {
                LiteRTGenerationRecorder.shared.finish(recordIndex, output: result, error: nil)
            }
#endif
            await finishConversation()
            return result
        } catch {
#if DEBUG
            if let recordIndex {
                LiteRTGenerationRecorder.shared.finish(recordIndex, output: nil, error: error)
            }
#endif
            abandonedConversation = conversation
            await finishConversation()
            throw error
        }
    }

#if DEBUG
    /// Opt-in diagnostics (`--litert-record-generations`): renders the exact prompt through
    /// LiteRT-LM's own template before sending. Returns `nil`, and does nothing, when disabled.
    private static func recordGenerationStart(
        conversation: Conversation,
        systemInstruction: String,
        initialMessages: [Message],
        message: Message,
        sampling: LiteRTSampling
    ) -> Int? {
        guard LiteRTGenerationRecorder.isEnabled else { return nil }
        var preface: String?
        var rendered: String?
        var renderError: String?
        do {
            preface = try conversation.renderPrefaceIntoString()
            rendered = try conversation.renderMessageIntoString(message)
        } catch {
            renderError = String(reflecting: error)
        }
        return LiteRTGenerationRecorder.shared.begin(
            sampling: .init(
                topK: sampling.topK,
                topP: sampling.topP,
                temperature: sampling.temperature,
                seed: sampling.seed,
                isStructured: sampling.isStructured
            ),
            systemInstruction: systemInstruction,
            message: message.toString,
            initialMessageCount: initialMessages.count,
            renderedPreface: preface,
            renderedMessage: rendered,
            renderError: renderError
        )
    }
#endif

    /// v0.14.0 removed explicit close(); dropping the last strong reference (here and by letting
    /// `activeConversation` go out of scope) triggers native cleanup in deinit.
    private func finishConversation() {
        activeConversation = nil
        pendingTeardownDrain = true
    }

    /// Races `operation` against a stall timeout WITHOUT `TaskGroup`'s implicit "wait for every
    /// child before returning" guarantee. That guarantee is exactly what made the previous
    /// task-group-based watchdog useless in practice: a genuinely wedged native call doesn't
    /// respect Swift's cooperative cancellation, so `withThrowingTaskGroup` kept blocking this
    /// function's return until the wedged child eventually finished (which was never) — the
    /// watchdog "won" internally but the caller never found out. Firing `operation` as a truly
    /// unstructured `Task` detaches it from that guarantee: a wedged call is simply abandoned
    /// (left running harmlessly in the background) instead of blocking the caller forever.
    private static func abandoningStall<T: Sendable>(
        timeout: Duration,
        _ operation: @escaping @Sendable () async throws -> T,
        onTimeout: @escaping @Sendable () -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let box = StallRaceBox(continuation)
            var watchdog: Task<Void, Never>?
            let work = Task {
                do {
                    let value = try await operation()
                    box.resume(.success(value))
                } catch {
                    box.resume(.failure(error))
                }
                watchdog?.cancel()
            }
            watchdog = Task {
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                onTimeout()
                box.resume(.failure(LiteRTAngroveRuntimeError.stalledGeneration))
                work.cancel()
            }
        }
    }

    /// Polls `runtime.lastTokenAt` every 5s instead of using a flat deadline, so streaming
    /// activity keeps resetting the clock and only a true no-progress stall fires the timeout.
    private static func abandoningStall<T: Sendable>(
        pollingAgainst runtime: LiteRTAngroveRuntime,
        _ operation: @escaping @Sendable @concurrent () async throws -> T,
        onTimeout: @escaping @Sendable () -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let box = StallRaceBox(continuation)
            var watchdog: Task<Void, Never>?
            let work = Task {
                do {
                    let value = try await operation()
                    box.resume(.success(value))
                } catch {
                    box.resume(.failure(error))
                }
                watchdog?.cancel()
            }
            watchdog = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    guard await runtime.hasStalled() else { continue }
                    onTimeout()
                    box.resume(.failure(LiteRTAngroveRuntimeError.stalledGeneration))
                    work.cancel()
                    return
                }
            }
        }
    }

    private func hasStalled() -> Bool {
        let now = ContinuousClock.now
        defer { lastStallCheckAt = now }
        if let lastStallCheckAt, lastStallCheckAt.duration(to: now) > Self.suspensionGap {
            // The process was suspended between checks. Restart the window rather than count
            // time the native side could not have used.
            lastTokenAt = now
            LiteRTLifecycleTrace.shared.record(
                "stall-window-reset-after-suspension",
                ["gapSeconds": Self.seconds(lastStallCheckAt.duration(to: now))]
            )
            return false
        }
        var timeout = Self.stallTimeout
#if DEBUG
        if let forcedStallTimeout { timeout = forcedStallTimeout }
#endif
        let stalled = Self.seconds(lastTokenAt.duration(to: .now)) >= Self.seconds(timeout)
        if stalled {
#if DEBUG
            forcedStallTimeout = nil
#endif
            LiteRTLifecycleTrace.shared.record(
                "stall-timeout",
                ["timeoutSeconds": Self.seconds(timeout),
                 "inFlight": LiteRTLifecycleTrace.shared.inFlightKinds()]
            )
        }
        return stalled
    }

    /// Convenience over `abandoningStall(pollingAgainst:)`: resets the stall clock and races
    /// `operation`. Used to guard each native phase (conversation creation, main answer,
    /// follow-up) as its own independent stall window rather than one window spanning all of
    /// them — so a stall in a later phase can be caught and swallowed by its caller without
    /// discarding an already-produced result from an earlier phase.
    ///
    /// Deliberately does NOT call `cancelCurrentGeneration()` on timeout or on the wrapping
    /// Task being cancelled (covers both a stall-watchdog firing and `ModelTaskQueue` preempting
    /// or stopping this job — they're indistinguishable at this layer). Confirmed via device
    /// console capture that `Conversation.cancel()` can leave the native `callback_thread_pool`
    /// (a single-worker pool) permanently stuck on DEADLINE_EXCEEDED, wedging every later
    /// generation for the rest of the process — far worse than just abandoning the call.
    private func racingStall<T: Sendable>(
        _ operation: @escaping @Sendable @concurrent () async throws -> T
    ) async throws -> T {
        lastTokenAt = .now
        lastStallCheckAt = lastTokenAt
        return try await Self.abandoningStall(pollingAgainst: self, operation, onTimeout: {})
    }

    private func makeConversation(
        engine: Engine,
        systemInstruction: String,
        initialMessages: [Message],
        sampling: LiteRTSampling
    ) async throws -> Conversation {
        let sampler = try SamplerConfig(
            topK: sampling.topK,
            topP: sampling.topP,
            temperature: sampling.temperature,
            seed: sampling.seed
        )
        let conversation = try await engine.createConversation(
            with: ConversationConfig(
                systemMessage: Message(systemInstruction, role: .system),
                initialMessages: initialMessages,
                samplerConfig: sampler
            )
        )
        activeConversation = conversation
        return conversation
    }

    private func streamText(
        on conversation: Conversation,
        message: Message,
        appliesDegenerateOutputGuard: Bool,
        onText: (@Sendable (String) async -> Void)?,
        onThought: (@Sendable (String) async -> Void)?
    ) async throws -> String {
        var accumulated = ""
        var thought = ""
        // Gemma 4's native thinking mode: the chat template prepends `<|think|>` to the system
        // turn, and LiteRT-LM routes the reasoning into the `thought` channel, separate from the
        // answer text. Only requested when a caller wants to display it.
        let extraContext: [String: Any]? = onThought == nil ? nil : ["enable_thinking": true]
        do {
            for try await chunk in conversation.sendMessageStream(
                message,
                extraContext: extraContext
            ) {
                try Task.checkCancellation()
                lastTokenAt = .now
                if let onThought, let thoughtDelta = chunk.channels["thought"], !thoughtDelta.isEmpty {
                    thought += thoughtDelta
                    await onThought(thought)
                }
                let text = chunk.toString
                guard !text.isEmpty else { continue }
                accumulated += text
                if appliesDegenerateOutputGuard {
                    if LiteRTGenerationGuard.hasMixedScriptCorruption(in: accumulated) {
                        throw LiteRTAngroveRuntimeError.corruptResponse
                    }
                    if let prefix = LiteRTGenerationGuard.responseBeforeRepetition(
                        in: accumulated
                    ) {
                        let cleanedPrefix = prefix.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        guard cleanedPrefix.split(whereSeparator: { $0.isWhitespace }).count >= 12 else {
                            throw LiteRTAngroveRuntimeError.repetitiveResponse
                        }
                        if let onText {
                            await onText(cleanedPrefix)
                        }
                        return cleanedPrefix
                    }
                }
                if let onText {
                    await onText(accumulated)
                }
            }
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            throw error
        }

        let cleaned = accumulated.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !cleaned.isEmpty else {
            throw LiteRTAngroveRuntimeError.emptyResponse
        }
        return cleaned
    }

    nonisolated private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

nonisolated struct LiteRTSampling: Sendable {
    static let conversation = LiteRTSampling(
        topK: 1,
        topP: 1,
        temperature: 0,
        seed: 0,
        isStructured: false
    )
    static let structured = LiteRTSampling(
        topK: 1,
        topP: 1,
        temperature: 0,
        seed: 7,
        isStructured: true
    )

    let topK: Int
    let topP: Float
    let temperature: Float
    let seed: Int
    /// Short, bounded JSON-contract calls (key terms, labels, definitions, this Insight Tree
    /// seed) vs. free-form conversational prose. Governs whether `streamText` applies the
    /// degenerate-repetition/corruption guard — see its call site's doc comment for why that
    /// guard is conversation-only.
    let isStructured: Bool

    var retryVariant: LiteRTSampling {
        guard seed == Self.conversation.seed else { return self }
        return LiteRTSampling(
            topK: 1,
            topP: 1,
            temperature: 0,
            seed: 0,
            isStructured: isStructured
        )
    }
}

/// Rejects the exact phrase/sentence loops that greedy decoding can produce with quantized
/// weights. It deliberately requires substantial consecutive repetition so normal rhetorical
/// emphasis is not treated as a generation failure.
nonisolated enum LiteRTGenerationGuard {
    /// Runs against in-progress output while tokens stream, so it is compiled once.
    private static let wordPattern = try! NSRegularExpression(pattern: #"[\p{L}\p{N}]+"#)

    static func hasDegenerateOutput(in text: String) -> Bool {
        hasDegenerateRepetition(in: text) || hasMixedScriptCorruption(in: text)
    }

    static func hasDegenerateRepetition(in text: String) -> Bool {
        responseBeforeRepetition(in: text) != nil
    }

    static func responseBeforeRepetition(in text: String) -> String? {
        let sentences = text
            .split(whereSeparator: { ".!?\n".contains($0) })
            .map(normalizedText)
            .filter { !$0.isEmpty }
        if sentences.count >= 2,
           let last = sentences.last,
           last.count >= 40,
           last == sentences[sentences.count - 2] {
            let repeatedSentence = String(
                text.split(whereSeparator: { ".!?\n".contains($0) }).last ?? ""
            )
            if let range = text.range(of: repeatedSentence, options: .backwards) {
                return String(text[..<range.lowerBound])
            }
        }

        let source = text as NSString
        let matches = wordPattern.matches(
            in: text,
            range: NSRange(location: 0, length: source.length)
        )
        let words = matches.map {
            source.substring(with: $0.range).lowercased()
        }
        var earliestRepeatedLocation: Int?
        // A loop is not always adjacent or aligned with the end of the output. Find any exact,
        // substantial phrase that appears twice without overlapping itself.
        for windowSize in [10, 16, 24] where words.count >= windowSize * 2 {
            var firstPositionByPhrase: [String: Int] = [:]
            for start in 0...(words.count - windowSize) {
                let phrase = words[start..<(start + windowSize)]
                    .joined(separator: " ")
                if let firstPosition = firstPositionByPhrase[phrase],
                   start - firstPosition >= windowSize {
                    let location = matches[start].range.location
                    earliestRepeatedLocation = min(
                        earliestRepeatedLocation ?? location,
                        location
                    )
                    break
                }
                firstPositionByPhrase[phrase] = firstPositionByPhrase[phrase] ?? start
            }
        }
        guard let earliestRepeatedLocation else { return nil }
        return source.substring(
            with: NSRange(location: 0, length: earliestRepeatedLocation)
        )
    }

    /// The 4-bit checkpoint can collapse under sampling into long runs that mix CJK, Arabic, and
    /// Hangul fragments with malformed code-like tokens. A few non-Latin terms are valid, so this
    /// requires both a meaningful count and proportion before rejecting a draft.
    static func hasMixedScriptCorruption(in text: String) -> Bool {
        let letters = text.unicodeScalars.filter {
            CharacterSet.letters.contains($0)
        }
        guard letters.count >= 40 else { return false }
        let suspiciousCount = letters.count(where: isUnexpectedScript)
        return suspiciousCount >= 12
            && Double(suspiciousCount) / Double(letters.count) >= 0.08
    }

    private static func isUnexpectedScript(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, // Hiragana and Katakana
             0x3400...0x9FFF, // CJK ideographs
             0xAC00...0xD7AF, // Hangul syllables
             0x0600...0x06FF: // Arabic
            true
        default:
            false
        }
    }

    private static func normalizedText<S: StringProtocol>(_ text: S) -> String {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }
}
