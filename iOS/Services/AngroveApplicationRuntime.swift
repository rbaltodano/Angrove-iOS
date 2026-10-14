//
//  AngroveApplicationRuntime.swift
//  Angrove-iOS
//

import Foundation
import UIKit

/// Constructs the live model and queue together so every queued operation leases the same engine
/// that performs generation. The object is process-scoped and intentionally survives navigation.
@MainActor
final class AngroveApplicationRuntime {
    static let shared = AngroveApplicationRuntime()

    let model: any AngroveModel
    let modelTasks: ModelTaskQueue
    let isOnDevice: Bool
    /// The relatedness signal for on-device Insight clustering (the global Insight Library, and
    /// any local fallback before a conversation's persisted tree loads). MiniLM when the bundled
    /// on-device model is available; `NLEmbedding` only as a last resort, since its similarity
    /// scores are too noisy on short Insight text to cluster on — see
    /// `MiniLMEmbeddingProvider`'s doc comment.
    let embeddingProvider: any EmbeddingProvider
#if DEBUG
    /// The live runtime and its lifecycle, for the lifecycle probe only (plan C7/C9).
    private(set) var debugLiteRTRuntime: LiteRTAngroveRuntime?
    private(set) var debugRuntimeLifecycle: ModelRuntimeLifecycleManager?
#endif

    private init(modelStore defaultModelStore: LiteRTModelStore = LiteRTModelStore()) {
        embeddingProvider = LazySemanticEmbeddingProvider()
#if DEBUG
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
        Self.installDebugMemoryWarningTrigger()
#else
        let modelStore = defaultModelStore
#endif
        if modelStore.usesAppleHostedDelivery || modelStore.hasInstalledModel() {
            let runtime = LiteRTAngroveRuntime(modelStore: modelStore)
            var configuration = ModelRuntimeLifecycleConfiguration.adaptiveOnDevice
#if DEBUG
            // `--litert-idle-timeout-seconds <n>` shortens idle unload for lifecycle tests (C7).
            if let seconds = LiteRTProbeArguments.value(
                after: "--litert-idle-timeout-seconds",
                in: ProcessInfo.processInfo.arguments
            ).flatMap(TimeInterval.init) {
                configuration = ModelRuntimeLifecycleConfiguration(
                    retentionPolicy: .adaptive,
                    normalIdleTimeout: seconds,
                    seriousThermalIdleTimeout: seconds
                )
            }
#endif
            let lifecycle = ModelRuntimeLifecycleManager(
                driver: runtime,
                configuration: configuration
            )
            var groundingProvider: any AngroveGroundingProviding = LazyGroundingProvider()
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--litert-sustained-probe") {
                groundingProvider = LiteRTC9GroundingObserver(base: groundingProvider)
            }
#endif
            model = LiteRTAngroveModel(runtime: runtime, groundingProvider: groundingProvider)
            modelTasks = ModelTaskQueue(runtimeLifecycle: lifecycle)
            isOnDevice = true
#if DEBUG
            debugLiteRTRuntime = runtime
            debugRuntimeLifecycle = lifecycle
#endif
        } else {
            model = UnavailableAngroveModel()
            modelTasks = ModelTaskQueue()
            isOnDevice = false
        }
    }

#if DEBUG
    /// A headless simulator has no Debug menu, so lifecycle tests (plan C7) raise a memory
    /// warning with `xcrun simctl spawn <device> notifyutil -p com.aquinas.debug.memory-warning`.
    private static func installDebugMemoryWarningTrigger() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                Task { @MainActor in
                    NotificationCenter.default.post(
                        name: UIApplication.didReceiveMemoryWarningNotification,
                        object: UIApplication.shared
                    )
                }
            },
            "com.aquinas.debug.memory-warning" as CFString,
            nil,
            .deliverImmediately
        )
    }
#endif

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
