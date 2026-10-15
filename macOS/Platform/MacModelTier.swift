import Foundation

/// The Mac's on-device model choices. A Mac uses the tier chosen in Settings when its installed
/// memory qualifies and that model is installed; otherwise it uses Standard. A change applies at
/// the next launch, because the process keeps one runtime and one engine.
/// Extended (the tuned-voice E4B INT8 package) joins once that package is re-exported.
nonisolated enum MacModelTier: String, CaseIterable, Identifiable, Sendable {
    case standard
    case large

    static let selectionKey = "angrove.mac.modelTier"

    var id: String { rawValue }

    var manifest: LiteRTModelManifest {
        switch self {
        case .standard:
            .angrove
        case .large:
            // Stock litert-community/gemma-4-12B-it-litert-lm package. Needs LiteRT-LM 0.17+.
            LiteRTModelManifest(
                fileName: "gemma-4-12B-it.litertlm",
                byteCount: 6_883_278_368,
                sha256: "58fd31b778ca2c21c80d634fb34fc5a89d11d563a38dfd3cbf1b40dbf252a8b6"
            )
        }
    }

    /// Installed memory a Mac needs for this tier. Large's 24 GiB is a placeholder until it is
    /// measured on a 16 GB Mac (model card: about 7.9 GB of GPU memory).
    var minimumMemoryBytes: UInt64 {
        switch self {
        case .standard: MacHardwareSupport.minimumMemoryBytes
        case .large: 24 * 1_024 * 1_024 * 1_024
        }
    }

    /// KV-cache size. Every tier keeps the iPhone's 4,096 for now: a larger window needs a memory
    /// measurement, and `AngroveContextBudget` would have to follow it.
    var contextTokens: Int { LiteRTAngroveRuntime.maxNumTokens }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .large: "Large"
        }
    }

    var detail: String {
        switch self {
        case .standard: "Gemma 4 E4B, the model the iPhone app uses."
        case .large: "Gemma 4 12B. Fuller answers, but slower and not yet evaluated. Needs 24 GB of memory."
        }
    }

    func isEligible(physicalMemory: UInt64) -> Bool {
        physicalMemory >= minimumMemoryBytes
    }

    /// The tier this launch runs: the selection when it qualifies and is installed, else Standard.
    static func resolve(
        selected: MacModelTier?,
        physicalMemory: UInt64,
        isInstalled: (MacModelTier) -> Bool
    ) -> MacModelTier {
        guard let selected, selected.isEligible(physicalMemory: physicalMemory), isInstalled(selected) else {
            return .standard
        }
        return selected
    }

    static var storedSelection: MacModelTier? {
        UserDefaults.standard.string(forKey: selectionKey).flatMap(MacModelTier.init(rawValue:))
    }

    func modelStore() -> LiteRTModelStore {
        var source: URL?
        #if DEBUG
        // Reuse the owner's existing, pinned artifacts without copying weights into this worktree.
        let developer = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let existing = developer.appending(path: developmentRelativePath)
        if FileManager.default.fileExists(atPath: existing.path) { source = existing }
        #endif
        return LiteRTModelStore(manifest: manifest, developmentModelURL: source)
    }

    private var developmentRelativePath: String {
        switch self {
        case .standard: "Aquinas-iOS-main/iOS/LocalModels/gemma-4-E4B-it.litertlm"
        case .large: "Aquinas_Backend/models/LiteRT-Stock/gemma-4-12B-it.litertlm"
        }
    }

    /// LiteRT names compiled caches `<model file>_<mtime>_<size>_…`, so every tier shares one
    /// cache folder. Removes the other tiers' caches (12B's is 5.6 GB); switching back recompiles.
    static func removeCaches(except active: MacModelTier, in directory: URL) {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        let stale = allCases.filter { $0 != active }.map { $0.manifest.fileName }
        for name in names where stale.contains(where: { name.hasPrefix($0) }) {
            try? fileManager.removeItem(at: directory.appending(path: name))
        }
    }
}
