//
//  AquinasApplicationRuntime.swift
//  Aquinas-iOS
//

import Foundation

/// Constructs the live model and queue together so every queued operation leases the same engine
/// that performs generation. The object is process-scoped and intentionally survives navigation.
@MainActor
final class AquinasApplicationRuntime {
    static let shared = AquinasApplicationRuntime()

    let model: any AquinasModel
    let modelTasks: ModelTaskQueue
    let isOnDevice: Bool
    /// The relatedness signal for on-device Insight clustering (the global Insight Library, and
    /// any local fallback before a conversation's persisted tree loads). MiniLM when the bundled
    /// on-device model is available; `NLEmbedding` only as a last resort, since its similarity
    /// scores are too noisy on short Insight text to cluster on — see
    /// `MiniLMEmbeddingProvider`'s doc comment.
    let embeddingProvider: any EmbeddingProvider

    private init(modelStore defaultModelStore: LiteRTModelStore = LiteRTModelStore()) {
        do {
            embeddingProvider = try MiniLMEmbeddingProvider()
        } catch {
            // Missing/corrupt on-device model assets fall back to NLEmbedding rather than
            // losing Insight clustering entirely — degraded (noisy) rather than broken.
            embeddingProvider = NLEmbeddingProvider()
        }
#if DEBUG
        let forcesMacBackend = ProcessInfo.processInfo.arguments.contains(
            "--force-backend-model"
        )
        let modelStore: LiteRTModelStore
        do {
            modelStore = try Self.developmentOverrideModelStore(
                arguments: ProcessInfo.processInfo.arguments,
                documentsDirectory: FileManager.default.urls(
                    for: .documentDirectory,
                    in: .userDomainMask
                ).first,
                isDebugBuild: true
            ) ?? defaultModelStore
        } catch {
            // A diagnostic override that can't be honored must not silently fall back to the
            // bundled model: every comparison run under it would be measuring the wrong file.
            fatalError("Model override failed: \(error.localizedDescription)")
        }
#else
        let forcesMacBackend = false
        let modelStore = defaultModelStore
#endif
        if !forcesMacBackend, modelStore.hasInstalledModel() {
            let runtime = LiteRTAquinasRuntime(modelStore: modelStore)
            let lifecycle = ModelRuntimeLifecycleManager(
                driver: runtime,
                configuration: .adaptiveOnDevice
            )
            let groundingProvider: any AquinasGroundingProviding
            do {
                groundingProvider = try MiniLMGroundingProvider()
            } catch {
                // Missing/corrupt corpus assets fall back to the small hardcoded
                // reference set rather than losing grounding entirely.
                groundingProvider = LocalAquinasGroundingProvider()
            }
            model = LiteRTAquinasModel(runtime: runtime, groundingProvider: groundingProvider)
            modelTasks = ModelTaskQueue(runtimeLifecycle: lifecycle)
            isOnDevice = true
        } else {
            model = BackendAquinasModel()
            modelTasks = ModelTaskQueue()
            isOnDevice = false
        }
    }

    /// DEBUG-only model override (`--litert-model-path <abs>` or `--litert-model-document
    /// <name>`) for evaluating a candidate package through the full app. Release builds never
    /// call this with `isDebugBuild: true`, so they ignore both flags.
    nonisolated static func developmentOverrideModelStore(
        arguments: [String],
        documentsDirectory: URL?,
        isDebugBuild: Bool
    ) throws -> LiteRTModelStore? {
        guard isDebugBuild,
              let url = try LiteRTModelOverride.resolvedModelURL(
                arguments: arguments,
                documentsDirectory: documentsDirectory
              ) else {
            return nil
        }
        return try LiteRTModelOverride.developmentStore(for: url)
    }
}
