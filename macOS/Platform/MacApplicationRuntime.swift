import Foundation
import Observation

/// One runtime and one queue for this process, including across Mac windows.
@MainActor @Observable final class MacApplicationRuntime {
    static let shared = MacApplicationRuntime()
    let modelTasks: ModelTaskQueue
    let model: any AngroveModel
    let embeddingProvider: any EmbeddingProvider
    let modelIsAvailable: Bool
    let modelURL: URL?

    #if DEBUG
    /// Explicitly injected boundaries for isolated tests; the live app uses `shared`.
    init(testModel: any AngroveModel, queue: ModelTaskQueue) {
        model = testModel
        modelTasks = queue
        embeddingProvider = LazySemanticEmbeddingProvider()
        modelIsAvailable = true
        modelURL = nil
    }
    #endif

    private init() {
        var source: URL?
        #if DEBUG
        // Reuse the owner's existing, pinned E4B artifact without copying weights into this worktree.
        let developer = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let existing = developer.appending(path: "Aquinas-iOS-main/iOS/LocalModels/gemma-4-E4B-it.litertlm")
        if FileManager.default.fileExists(atPath: existing.path) { source = existing }
        #endif
        let store = LiteRTModelStore(developmentModelURL: source)
        let installed = try? store.installedModelURL()
        modelURL = installed
        modelIsAvailable = installed != nil
        if let installed {
            let native = LiteRTAngroveRuntime(modelStore: store)
            let lifecycle = ModelRuntimeLifecycleManager(driver: VerifiedMacRuntimeDriver(runtime: native, url: installed), configuration: .adaptiveOnDevice)
            modelTasks = ModelTaskQueue(runtimeLifecycle: lifecycle)
            model = LiteRTAngroveModel(runtime: native, groundingProvider: LazyGroundingProvider())
        } else {
            modelTasks = ModelTaskQueue()
            model = UnavailableAngroveModel()
        }
        embeddingProvider = LazySemanticEmbeddingProvider()
    }
}

/// Keep integrity checking off the main thread and inside the serialized runtime lease.
private actor VerifiedMacRuntimeDriver: ModelRuntimeDriver {
    nonisolated let supportsUnloading = true
    let runtime: LiteRTAngroveRuntime
    let url: URL
    private var verified = false
    init(runtime: LiteRTAngroveRuntime, url: URL) { self.runtime = runtime; self.url = url }
    func loadModelWeights() async throws {
        if !verified {
            let url = url
            let digest = try await Task.detached(priority: .utility) { try LiteRTModelInstaller.sha256(of: url) }.value
            guard digest == LiteRTModelManifest.angrove.sha256 else { throw LiteRTModelStoreError.invalidModelDigest }
            verified = true
        }
        try await runtime.loadModelWeights()
    }
    func unloadModelWeights() async { await runtime.unloadModelWeights() }
}
