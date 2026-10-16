import Foundation
import LiteRTLM
import llama

nonisolated enum LlamaAngroveRuntimeError: LocalizedError, Sendable {
    case modelLoadFailed
    case contextCreationFailed
    case promptTooLong(tokens: Int, limit: Int)
    case tokenizationFailed
    case decodeFailed(code: Int32)

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed:
            "The llama.cpp model file couldn’t be loaded."
        case .contextCreationFailed:
            "llama.cpp couldn’t create a context for the model."
        case .promptTooLong(let tokens, let limit):
            "The prompt is \(tokens) tokens, past the \(limit)-token context."
        case .tokenizationFailed:
            "The prompt couldn’t be tokenized."
        case .decodeFailed(let code):
            "llama.cpp failed to evaluate the prompt (\(code))."
        }
    }
}

/// Runs Ternary Bonsai 2 9B (a Qwen3.5-9B with ternary weights) through PrismML's llama.cpp
/// fork, on Metal. Prompts use the model's ChatML template; its `<think>` block is routed to
/// `onThought` when a caller asks for thinking and skipped otherwise.
///
/// One generation runs at a time. `ModelTaskQueue` already serializes leases; the slot below
/// also protects direct callers, because awaiting the stream callbacks lets the actor re-enter.
actor LlamaAngroveRuntime {
    nonisolated let supportsUnloading = true

    private let modelURL: URL
    private let engine: EngineConfiguration

    /// llama.cpp context settings. The default is the configuration every measurement so far
    /// used; others exist for on-device engine benchmarks.
    nonisolated struct EngineConfiguration: Sendable, Encodable, Equatable {
        enum FlashAttention: String, Sendable, Encodable { case auto, enabled, disabled }
        var contextTokens = LlamaAngroveRuntime.defaultContextTokens
        /// Largest token count one `llama_decode` call accepts (prompt chunking).
        var batch = 512
        /// Tokens the GPU processes per step within a batch.
        var microBatch = 512
        var flashAttention = FlashAttention.auto
    }

    nonisolated enum SamplingProfile: String, Sendable {
        case caller
        case prismRecommended
    }
    private let samplingProfile: SamplingProfile
    private let recordsGenerationStats: Bool
    private var recordedGenerations: [GenerationStats] = []
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var isGenerating = false
    private var slotWaiters: [CheckedContinuation<Void, Never>] = []

    /// Timing for the most recent load and generation, for developer probes.
    nonisolated struct GenerationStats: Encodable, Sendable {
        var promptTokens = 0
        var prefillSeconds = 0.0
        var generatedTokens = 0
        var decodeSeconds = 0.0
        var firstAnswerSeconds: Double?
        var samplingProfile = "caller"
        var temperature: Float = 0
        var topP: Float = 1
        var topK = 1
        var presencePenalty: Float = 0
        var penaltyWindow = 0
        var structured = false
        var seed = 0
        var stopReason = "error"
        var decodeTokensPerSecond: Double { decodeSeconds > 0 ? Double(generatedTokens) / decodeSeconds : 0 }
    }
    private(set) var lastLoadSeconds: Double?
    private(set) var lastStats: GenerationStats?

    /// The most one request may generate, reasoning included.
    private static let maxOutputTokens = 3_072
    /// A request is refused when its prompt leaves less room than this to answer.
    private static let minimumOutputTokens = 256
    /// Reasoning tokens allowed before the runtime closes the `<think>` block itself.
    private static let thinkingBudget = 1_024
    /// Qwen's suggested wording for ending reasoning at a budget.
    private static let thinkingBudgetClose =
        "\n\nConsidering the limited time, I have to give the answer based on the thinking directly now.\n</think>\n\n"

    /// Qwen3.5's hybrid attention keeps only every fourth layer's KV cache, so a 16K window
    /// costs about 0.5 GB.
    static let defaultContextTokens = 16_384

    init(
        modelURL: URL,
        contextTokens: Int = defaultContextTokens,
        samplingProfile: SamplingProfile = .caller,
        recordsGenerationStats: Bool = false,
        engine: EngineConfiguration? = nil
    ) {
        self.modelURL = modelURL
        self.engine = engine ?? EngineConfiguration(contextTokens: contextTokens)
        self.samplingProfile = samplingProfile
        self.recordsGenerationStats = recordsGenerationStats
    }

    nonisolated struct BenchmarkResult: Encodable, Sendable {
        let promptTokens: Int
        let prefillSeconds: Double
        let generatedTokens: Int
        let decodeSeconds: Double
        var prefillTokensPerSecond: Double { prefillSeconds > 0 ? Double(promptTokens) / prefillSeconds : 0 }
        var decodeTokensPerSecond: Double { decodeSeconds > 0 ? Double(generatedTokens) / decodeSeconds : 0 }

        enum CodingKeys: String, CodingKey {
            case promptTokens, prefillSeconds, generatedTokens, decodeSeconds
            case prefillTokensPerSecond, decodeTokensPerSecond
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(promptTokens, forKey: .promptTokens)
            try container.encode(prefillSeconds, forKey: .prefillSeconds)
            try container.encode(generatedTokens, forKey: .generatedTokens)
            try container.encode(decodeSeconds, forKey: .decodeSeconds)
            try container.encode(prefillTokensPerSecond, forKey: .prefillTokensPerSecond)
            try container.encode(decodeTokensPerSecond, forKey: .decodeTokensPerSecond)
        }
    }

    /// Raw engine speed, like llama-bench's pp/tg: prefill `promptTokens` of `text` (repeated as
    /// needed) from an empty cache, then greedily generate `generateTokens` ignoring stop tokens.
    /// Developer benchmarks only; it bypasses prompts, sampling profiles and guards.
    func benchmark(text: String, promptTokens: Int, generateTokens: Int) async throws -> BenchmarkResult {
        await acquireSlot()
        defer { releaseSlot() }
        if model == nil { try await loadModelWeights() }
        guard let model, let context else { throw LiteRTAngroveRuntimeError.modelNotLoaded }
        let vocab = llama_model_get_vocab(model)
        var source = try Self.tokenize(text, vocab: vocab)
        guard !source.isEmpty else { throw LlamaAngroveRuntimeError.tokenizationFailed }
        while source.count < promptTokens { source += source }
        var prompt = Array(source.prefix(promptTokens))
        llama_memory_clear(llama_get_memory(context), true)
        let prefillStart = ContinuousClock.now
        try Self.evaluate(&prompt, in: context, batch: engine.batch)
        let prefillSeconds = Self.seconds(since: prefillStart)
        let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        defer { llama_sampler_free(sampler) }
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())
        let decodeStart = ContinuousClock.now
        for _ in 0..<generateTokens {
            try Task.checkCancellation()
            var next = [llama_sampler_sample(sampler, context, -1)]
            try Self.evaluate(&next, in: context, batch: engine.batch)
        }
        return BenchmarkResult(
            promptTokens: promptTokens, prefillSeconds: prefillSeconds,
            generatedTokens: generateTokens, decodeSeconds: Self.seconds(since: decodeStart)
        )
    }

    /// Opt-in eval recording includes retries and audits, not only the final generation.
    func takeGenerationStats() -> [GenerationStats] {
        defer { recordedGenerations.removeAll(keepingCapacity: true) }
        return recordedGenerations
    }

    // MARK: Lifecycle

    func loadModelWeights() async throws {
        guard model == nil else { return }
        Self.initializeBackend
        let loadStart = ContinuousClock.now
        defer { if model != nil { lastLoadSeconds = Self.seconds(since: loadStart) } }
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 999
        guard let loaded = llama_model_load_from_file(modelURL.path, modelParams) else {
            throw LlamaAngroveRuntimeError.modelLoadFailed
        }
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(engine.contextTokens)
        contextParams.n_batch = UInt32(engine.batch)
        contextParams.n_ubatch = UInt32(engine.microBatch)
        contextParams.flash_attn_type = switch engine.flashAttention {
        case .auto: LLAMA_FLASH_ATTN_TYPE_AUTO
        case .enabled: LLAMA_FLASH_ATTN_TYPE_ENABLED
        case .disabled: LLAMA_FLASH_ATTN_TYPE_DISABLED
        }
        let threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))
        contextParams.n_threads = threads
        contextParams.n_threads_batch = threads
        guard let created = llama_init_from_model(loaded, contextParams) else {
            llama_model_free(loaded)
            throw LlamaAngroveRuntimeError.contextCreationFailed
        }
        model = loaded
        context = created
        LlamaExitCleanup.track(model: loaded, context: created)
    }

    func unloadModelWeights() async {
        await acquireSlot()
        defer { releaseSlot() }
        if let model, let context { LlamaExitCleanup.untrack(model: model, context: context) }
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        context = nil
        model = nil
    }

    /// llama.cpp logs every tensor and token type while loading; keep only errors.
    private static let initializeBackend: Void = {
        llama_log_set({ level, text, _ in
            guard let text else { return }
            let line = String(cString: text)
            LlamaEngineLog.record(line)
            guard level == GGML_LOG_LEVEL_ERROR else { return }
            fputs(line, stderr)
        }, nil)
        llama_backend_init()
    }()

    // MARK: Generation

    func generate(
        systemInstruction: String,
        initialMessages: [Message],
        message: Message,
        sampling: LiteRTSampling,
        onText: (@Sendable (String) async -> Void)?,
        onThought: (@Sendable (String) async -> Void)?
    ) async throws -> String {
        await acquireSlot()
        defer { releaseSlot() }
        try Task.checkCancellation()
        if model == nil { try await loadModelWeights() }
        guard let model, let context else { throw LiteRTAngroveRuntimeError.modelNotLoaded }

        let thinks = onThought != nil
        let generationStart = ContinuousClock.now
        let prompt = Self.chatPrompt(
            system: systemInstruction,
            history: initialMessages,
            latest: message,
            thinking: thinks
        )
        let vocab = llama_model_get_vocab(model)
        var tokens = try Self.tokenize(prompt, vocab: vocab)
        // The answer gets whatever room the prompt leaves, up to the cap.
        let room = Int(llama_n_ctx(context)) - tokens.count
        guard room >= Self.minimumOutputTokens else {
            throw LlamaAngroveRuntimeError.promptTooLong(
                tokens: tokens.count,
                limit: Int(llama_n_ctx(context)) - Self.minimumOutputTokens
            )
        }
        let outputBudget = min(Self.maxOutputTokens, room)

        // Each request is self-contained, as with LiteRT: start from an empty cache.
        llama_memory_clear(llama_get_memory(context), true)
        var stats = GenerationStats(promptTokens: tokens.count)
        let configuration = SamplerConfiguration(sampling: sampling, profile: samplingProfile, thinking: thinks)
        stats.samplingProfile = samplingProfile.rawValue
        stats.temperature = configuration.temperature
        stats.topP = configuration.topP
        stats.topK = configuration.topK
        stats.presencePenalty = configuration.presencePenalty
        stats.penaltyWindow = configuration.penaltyWindow
        stats.structured = sampling.isStructured
        stats.seed = sampling.seed
        defer {
            lastStats = stats
            if recordsGenerationStats { recordedGenerations.append(stats) }
        }
        let prefillStart = ContinuousClock.now
        try Self.evaluate(&tokens, in: context, batch: engine.batch)
        stats.prefillSeconds = Self.seconds(since: prefillStart)
        let decodeStart = ContinuousClock.now
        defer {
            stats.decodeSeconds = Self.seconds(since: decodeStart)
        }

        let sampler = Self.makeSampler(configuration, vocabularySize: llama_vocab_n_tokens(vocab), seed: sampling.seed)
        defer { llama_sampler_free(sampler) }
        if configuration.presencePenalty != 0 {
            for token in tokens.suffix(configuration.penaltyWindow) { llama_sampler_accept(sampler, token) }
        }

        var stream = ThinkingSplitter(startsInThought: thinks)
        var pieces = Utf8Accumulator()
        var generationGuard = IncrementalGenerationGuard()

        while stats.generatedTokens < outputBudget {
            try Task.checkCancellation()
            // Past the thinking budget, close the reasoning for the model so it answers.
            if stream.isInThought, stats.generatedTokens >= Self.thinkingBudget {
                var closing = try Self.tokenize(Self.thinkingBudgetClose, vocab: vocab)
                try Self.evaluate(&closing, in: context, batch: engine.batch)
                for token in closing { llama_sampler_accept(sampler, token) }
                _ = stream.append(Self.thinkingBudgetClose)
                if let onThought { await onThought(stream.thought) }
                continue
            }
            let token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) {
                stats.stopReason = "endOfGeneration"
                break
            }
            var next = [token]
            try Self.evaluate(&next, in: context, batch: engine.batch)
            stats.generatedTokens += 1

            guard let delta = pieces.append(Self.piece(for: token, vocab: vocab)) else { continue }
            let change = stream.append(delta)
            if change.thoughtChanged, let onThought {
                await onThought(stream.thought)
            }
            guard !change.answerDelta.isEmpty else { continue }
            if stats.firstAnswerSeconds == nil { stats.firstAnswerSeconds = Self.seconds(since: generationStart) }
            if !sampling.isStructured {
                let guardResult = generationGuard.append(change.answerDelta)
                if guardResult.corrupt { throw LiteRTAngroveRuntimeError.corruptResponse }
                if let prefix = guardResult.repetitionPrefix {
                    let cleaned = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard cleaned.split(whereSeparator: \.isWhitespace).count >= 12 else {
                        throw LiteRTAngroveRuntimeError.repetitiveResponse
                    }
                    await onText?(cleaned)
                    stats.stopReason = "repetitionGuard"
                    return cleaned
                }
            }
            await onText?(stream.answer)
        }

        let cleaned = stream.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw LiteRTAngroveRuntimeError.emptyResponse }
        if stats.generatedTokens == outputBudget { stats.stopReason = "tokenLimit" }
        return cleaned
    }

    // MARK: Prompt

    /// The model's own ChatML template (`tokenizer.chat_template` in the GGUF), written out
    /// directly. With thinking off, the template closes an empty `<think>` block for the model.
    nonisolated static func chatPrompt(
        system: String,
        history: [Message],
        latest: Message,
        thinking: Bool
    ) -> String {
        var prompt = ""
        let trimmedSystem = system.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSystem.isEmpty {
            prompt += "<|im_start|>system\n\(trimmedSystem)<|im_end|>\n"
        }
        for message in history + [latest] {
            let role = switch message.role {
            case .model: "assistant"
            case .system: "system"
            default: "user"
            }
            prompt += "<|im_start|>\(role)\n\(text(of: message))<|im_end|>\n"
        }
        prompt += "<|im_start|>assistant\n"
        prompt += thinking ? "<think>\n" : "<think>\n\n</think>\n\n"
        return prompt
    }

    /// Text parts only for now; images need the vision projector (`mtmd`), not yet wired.
    nonisolated private static func text(of message: Message) -> String {
        message.contents.compactMap { content -> String? in
            if case .text(let text) = content { return text }
            return nil
        }
        .joined(separator: "\n")
    }

    // MARK: llama.cpp

    nonisolated private static func tokenize(_ text: String, vocab: OpaquePointer?) throws -> [llama_token] {
        let utf8Count = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(utf8Count) + 16)
        let count = llama_tokenize(vocab, text, utf8Count, &tokens, Int32(tokens.count), false, true)
        guard count >= 0 else { throw LlamaAngroveRuntimeError.tokenizationFailed }
        return Array(tokens.prefix(Int(count)))
    }

    nonisolated private static func evaluate(_ tokens: inout [llama_token], in context: OpaquePointer, batch: Int) throws {
        var start = 0
        while start < tokens.count {
            let count = min(batch, tokens.count - start)
            let code = tokens.withUnsafeMutableBufferPointer { buffer in
                llama_decode(context, llama_batch_get_one(buffer.baseAddress! + start, Int32(count)))
            }
            guard code == 0 else { throw LlamaAngroveRuntimeError.decodeFailed(code: code) }
            start += count
        }
    }

    nonisolated private static func piece(for token: llama_token, vocab: OpaquePointer?) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 64)
        var length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        if length < 0 {
            buffer = [CChar](repeating: 0, count: Int(-length))
            length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        }
        return buffer.prefix(Int(max(0, length))).map { UInt8(bitPattern: $0) }
    }

    nonisolated struct SamplerConfiguration: Sendable {
        let temperature: Float
        let topP: Float
        let topK: Int
        let presencePenalty: Float
        let penaltyWindow: Int

        init(sampling: LiteRTSampling, profile: SamplingProfile, thinking: Bool) {
            // Structured app contracts retain their caller's deterministic decoding.
            let recommended = profile == .prismRecommended && !sampling.isStructured
            temperature = recommended ? (thinking ? 1 : 0.7) : sampling.temperature
            topP = recommended ? (thinking ? 0.95 : 0.8) : sampling.topP
            topK = recommended ? 20 : sampling.topK
            presencePenalty = recommended ? (thinking ? 1 : 1.5) : 0
            penaltyWindow = recommended ? 64 : 0
        }
    }

    nonisolated static func makeSampler(
        _ configuration: SamplerConfiguration, vocabularySize: Int32, seed: Int
    ) -> UnsafeMutablePointer<llama_sampler> {
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        if configuration.presencePenalty != 0 {
            llama_sampler_chain_add(chain, llama_sampler_init_penalties(
                vocabularySize, Int32(configuration.penaltyWindow), 1, 0, configuration.presencePenalty
            ))
        }
        if configuration.temperature <= 0 {
            llama_sampler_chain_add(chain, llama_sampler_init_greedy())
        } else {
            llama_sampler_chain_add(chain, llama_sampler_init_top_k(Int32(configuration.topK)))
            llama_sampler_chain_add(chain, llama_sampler_init_top_p(configuration.topP, 1))
            // min-p is disabled (0), as specified by Prism's small-model profile.
            llama_sampler_chain_add(chain, llama_sampler_init_temp(configuration.temperature))
            llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32(truncatingIfNeeded: seed)))
        }
        return chain
    }

    nonisolated private static func seconds(since start: ContinuousClock.Instant) -> Double {
        let components = (ContinuousClock.now - start).components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    // MARK: Slot

    private func acquireSlot() async {
        if !isGenerating {
            isGenerating = true
            return
        }
        await withCheckedContinuation { slotWaiters.append($0) }
    }

    private func releaseSlot() {
        if slotWaiters.isEmpty {
            isGenerating = false
        } else {
            slotWaiters.removeFirst().resume()
        }
    }
}

// Keep protocol-conformance isolation inference separate from the actor declaration.
extension LlamaAngroveRuntime: AngroveTextRuntime {}

/// While a developer benchmark captures, keeps llama.cpp's backend setup lines (Metal device
/// features, tensor API, flash attention, batch sizes) that the quiet logger otherwise drops.
nonisolated enum LlamaEngineLog {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var capturing = false
    nonisolated(unsafe) private static var lines: [String] = []
    private static let keywords = ["metal", "mtl", "tensor", "flash", "simdgroup", "bfloat", "bf16",
                                   "residency", "unified", "n_ubatch", "n_batch", "n_ctx", "gpu", "kv"]

    static func start() {
        lock.lock(); defer { lock.unlock() }
        capturing = true
        lines = []
    }

    static func stop() -> [String] {
        lock.lock(); defer { lock.unlock() }
        capturing = false
        return lines
    }

    static func record(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        guard capturing, lines.count < 400 else { return }
        let lower = line.lowercased()
        guard keywords.contains(where: { lower.contains($0) }) else { return }
        lines.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Frees loaded models when the process exits. llama.cpp's Metal backend asserts in its own exit
/// cleanup if a model is still resident, which would leave a crash report on every quit. Exit
/// handlers run in reverse order of registration, so registering after the first load (which
/// set up the Metal backend) runs this first.
nonisolated enum LlamaExitCleanup {
    private struct Handles: @unchecked Sendable {
        let model: OpaquePointer
        let context: OpaquePointer
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var live: [Handles] = []
    nonisolated(unsafe) private static var isRegistered = false

    static func track(model: OpaquePointer, context: OpaquePointer) {
        lock.lock()
        defer { lock.unlock() }
        live.append(Handles(model: model, context: context))
        guard !isRegistered else { return }
        isRegistered = true
        atexit { LlamaExitCleanup.freeAll() }
    }

    static func untrack(model: OpaquePointer, context: OpaquePointer) {
        lock.lock()
        defer { lock.unlock() }
        live.removeAll { $0.model == model && $0.context == context }
    }

    private static func freeAll() {
        lock.lock()
        let handles = live
        live = []
        lock.unlock()
        for handle in handles {
            llama_free(handle.context)
            llama_model_free(handle.model)
        }
    }
}

/// Joins token bytes into text, holding back a multi-byte character split across tokens.
nonisolated struct Utf8Accumulator {
    private var pending: [UInt8] = []

    mutating func append(_ bytes: [UInt8]) -> String? {
        pending += bytes
        if let text = String(validating: pending, as: UTF8.self) {
            pending = []
            return text
        }
        // Give up on a sequence that can't become valid, rather than stalling the stream.
        if pending.count > 8 {
            let text = String(decoding: pending, as: UTF8.self)
            pending = []
            return text
        }
        return nil
    }
}

/// Separates the model's `<think>…</think>` reasoning from its answer as text streams in.
nonisolated struct ThinkingSplitter {
    private(set) var thought = ""
    private(set) var answer = ""
    private var inThought: Bool
    private var buffer = ""
    private static let closeTag = "</think>"

    init(startsInThought: Bool) {
        inThought = startsInThought
    }

    var isInThought: Bool { inThought }

    mutating func append(_ delta: String) -> (thoughtChanged: Bool, answerDelta: String) {
        guard inThought else {
            answer += delta
            return (false, delta)
        }
        buffer += delta
        if let range = buffer.range(of: Self.closeTag) {
            thought += buffer[..<range.lowerBound]
            let rest = String(buffer[range.upperBound...]).trimmingPrefixNewlines()
            buffer = ""
            inThought = false
            answer += rest
            return (true, rest)
        }
        // Keep a possible partial close tag buffered; release everything before it.
        let keep = Self.partialTagSuffixLength(of: buffer)
        let releasable = String(buffer.dropLast(keep))
        buffer = String(buffer.suffix(keep))
        thought += releasable
        return (!releasable.isEmpty, "")
    }

    private static func partialTagSuffixLength(of text: String) -> Int {
        for length in stride(from: min(closeTag.count - 1, text.count), to: 0, by: -1) {
            if closeTag.hasPrefix(text.suffix(length)) { return length }
        }
        return 0
    }
}

private extension String {
    func trimmingPrefixNewlines() -> String {
        String(drop(while: \.isNewline))
    }
}
