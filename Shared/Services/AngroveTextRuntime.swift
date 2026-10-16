import Foundation
import LiteRTLM

/// The text-generation engine `LiteRTAngroveModel` drives. Prompt building and response parsing
/// stay in the model; an engine only turns a system instruction and messages into text.
/// `LiteRTAngroveRuntime` runs Gemma 4 E4B, and `LlamaAngroveRuntime` runs Ternary Bonsai 2 9B
/// behind the developer flag in `BonsaiModelFlag`.
protocol AngroveTextRuntime: Actor, ModelRuntimeDriver {
    nonisolated var supportsVision: Bool { get }
    /// `onText` receives the answer accumulated so far and `onThought` the reasoning so far.
    /// A non-nil `onThought` turns on the model's thinking.
    func generate(
        systemInstruction: String,
        initialMessages: [Message],
        message: Message,
        sampling: LiteRTSampling,
        onText: (@Sendable (String) async -> Void)?,
        onThought: (@Sendable (String) async -> Void)?
    ) async throws -> String
}

extension AngroveTextRuntime {
    nonisolated var supportsVision: Bool { false }

    func generate(
        systemInstruction: String,
        initialMessages: [Message] = [],
        message: Message,
        sampling: LiteRTSampling = .conversation,
        onText: (@Sendable (String) async -> Void)? = nil
    ) async throws -> String {
        try await generate(
            systemInstruction: systemInstruction,
            initialMessages: initialMessages,
            message: message,
            sampling: sampling,
            onText: onText,
            onThought: nil
        )
    }
}

extension LiteRTAngroveRuntime: AngroveTextRuntime {
    nonisolated var supportsVision: Bool { Self.supportsVision }
}
