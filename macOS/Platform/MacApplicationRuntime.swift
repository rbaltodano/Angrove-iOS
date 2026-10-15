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
    /// The tier this launch runs; a Settings change applies at the next launch.
    let modelTier: MacModelTier

    #if DEBUG
    /// Explicitly injected boundaries for isolated tests; the live app uses `shared`.
    init(testModel: any AngroveModel, queue: ModelTaskQueue) {
        model = testModel
        modelTasks = queue
        embeddingProvider = LazySemanticEmbeddingProvider()
        modelIsAvailable = true
        modelURL = nil
        modelTier = .standard
    }
    #endif

    private init() {
        let stores = Dictionary(uniqueKeysWithValues: MacModelTier.allCases.map { ($0, $0.modelStore()) })
        let tier = MacModelTier.resolve(
            selected: MacModelTier.storedSelection,
            physicalMemory: ProcessInfo.processInfo.physicalMemory,
            isInstalled: { stores[$0]?.hasInstalledModel() == true }
        )
        modelTier = tier
        let store = stores[tier] ?? tier.modelStore()
        let installed = try? store.installedModelURL()
        modelURL = installed
        modelIsAvailable = installed != nil
        if let installed {
            let native = LiteRTAngroveRuntime(modelStore: store, contextTokens: tier.contextTokens)
            let driver = VerifiedMacRuntimeDriver(runtime: native, url: installed, sha256: store.manifest.sha256)
            let lifecycle = ModelRuntimeLifecycleManager(driver: driver, configuration: .adaptiveOnDevice)
            modelTasks = ModelTaskQueue(runtimeLifecycle: lifecycle)
            model = LiteRTAngroveModel(runtime: native, groundingProvider: LazyGroundingProvider())
        } else {
            modelTasks = ModelTaskQueue()
            model = UnavailableAngroveModel()
        }
        embeddingProvider = LazySemanticEmbeddingProvider()
        if let cache = try? store.cacheDirectory() {
            Task.detached(priority: .background) { MacModelTier.removeCaches(except: tier, in: cache) }
        }
    }
}

/// Keep integrity checking off the main thread and inside the serialized runtime lease.
private actor VerifiedMacRuntimeDriver: ModelRuntimeDriver {
    nonisolated let supportsUnloading = true
    let runtime: LiteRTAngroveRuntime
    let url: URL
    let sha256: String
    private var verified = false
    init(runtime: LiteRTAngroveRuntime, url: URL, sha256: String) {
        self.runtime = runtime
        self.url = url
        self.sha256 = sha256
    }
    func loadModelWeights() async throws {
        if !verified {
            let url = url
            let digest = try await Task.detached(priority: .utility) { try LiteRTModelInstaller.sha256(of: url) }.value
            guard digest == sha256 else { throw LiteRTModelStoreError.invalidModelDigest }
            verified = true
        }
        try await runtime.loadModelWeights()
    }
    func unloadModelWeights() async { await runtime.unloadModelWeights() }
}
