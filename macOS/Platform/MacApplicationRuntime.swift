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
    /// The tier new model tasks use. A switch takes effect once no task holds the runtime.
    private(set) var modelTier: MacModelTier
    @ObservationIgnored private let lifecycle: ModelRuntimeLifecycleManager?
    @ObservationIgnored private let driver: VerifiedMacRuntimeDriver?
    @ObservationIgnored private var switchTask: Task<Void, Never>?

    #if DEBUG
    /// Explicitly injected boundaries for isolated tests; the live app uses `shared`.
    init(testModel: any AngroveModel, queue: ModelTaskQueue) {
        model = testModel
        modelTasks = queue
        embeddingProvider = LazySemanticEmbeddingProvider()
        modelIsAvailable = true
        modelURL = nil
        modelTier = .standard
        lifecycle = nil
        driver = nil
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
            let driver = VerifiedMacRuntimeDriver(
                runtime: native,
                target: .init(store: store, url: installed, contextTokens: tier.contextTokens)
            )
            let lifecycle = ModelRuntimeLifecycleManager(driver: driver, configuration: .adaptiveOnDevice)
            self.driver = driver
            self.lifecycle = lifecycle
            modelTasks = ModelTaskQueue(runtimeLifecycle: lifecycle)
            model = LiteRTAngroveModel(runtime: native, groundingProvider: LazyGroundingProvider())
        } else {
            driver = nil
            lifecycle = nil
            modelTasks = ModelTaskQueue()
            model = UnavailableAngroveModel()
        }
        embeddingProvider = LazySemanticEmbeddingProvider()
        if let cache = try? store.cacheDirectory() {
            Task.detached(priority: .background) { MacModelTier.removeCaches(except: tier, in: cache) }
        }
    }

    /// Tiers this Mac can switch to now: enough installed memory and the package installed.
    var availableTiers: [MacModelTier] {
        let memory = ProcessInfo.processInfo.physicalMemory
        return MacModelTier.allCases.filter {
            $0.isEligible(physicalMemory: memory) && $0.modelStore().hasInstalledModel()
        }
    }

    /// Switches the model without relaunching. The running task finishes on the current model;
    /// the engine then unloads, and the next task loads (and verifies) the new package.
    func selectModel(_ tier: MacModelTier) {
        guard tier != modelTier, let driver, let lifecycle, availableTiers.contains(tier) else { return }
        let store = tier.modelStore()
        guard let url = try? store.installedModelURL() else { return }
        modelTier = tier
        UserDefaults.standard.set(tier.rawValue, forKey: MacModelTier.selectionKey)
        let previous = switchTask
        switchTask = Task {
            await previous?.value
            await driver.switchTarget(to: .init(store: store, url: url, contextTokens: tier.contextTokens))
            // A task can take a lease just before the unload runs; keep trying until the old
            // engine is gone or the next load has already applied the switch.
            while await driver.hasPendingSwitch, await lifecycle.currentState() != .unloaded {
                await lifecycle.unloadAsSoonAsIdle(reason: .modelSwitch)
                if await driver.hasPendingSwitch, await lifecycle.currentState() != .unloaded {
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        }
    }
}

/// Keep integrity checking off the main thread and inside the serialized runtime lease.
/// A model switch is applied at the next load, after the lifecycle has unloaded the old engine.
actor VerifiedMacRuntimeDriver: ModelRuntimeDriver {
    struct Target: Sendable {
        let store: LiteRTModelStore
        let url: URL
        let contextTokens: Int
    }

    nonisolated let supportsUnloading = true
    let runtime: LiteRTAngroveRuntime
    private var target: Target
    private var pending: Target?
    private var verified = false

    init(runtime: LiteRTAngroveRuntime, target: Target) {
        self.runtime = runtime
        self.target = target
    }

    func switchTarget(to newTarget: Target) {
        pending = newTarget
    }

    var hasPendingSwitch: Bool { pending != nil }

    /// The package the next (or current) engine load uses.
    var loadedFileName: String { target.store.manifest.fileName }

    func loadModelWeights() async throws {
        if let pending {
            target = pending
            self.pending = nil
            verified = false
            await runtime.replaceModelStore(target.store, contextTokens: target.contextTokens)
        }
        if !verified {
            let url = target.url
            let digest = try await Task.detached(priority: .utility) { try LiteRTModelInstaller.sha256(of: url) }.value
            guard digest == target.store.manifest.sha256 else { throw LiteRTModelStoreError.invalidModelDigest }
            verified = true
        }
        try await runtime.loadModelWeights()
    }

    func unloadModelWeights() async { await runtime.unloadModelWeights() }
}
