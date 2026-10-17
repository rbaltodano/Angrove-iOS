import BackgroundAssets
import Foundation
import System

/// Versioned pack IDs and paths prevent a later model update from replacing the model that a
/// live engine is using. Changing the model requires a new ID/path and an app manifest change.
nonisolated struct AngroveModelAssetPack: Sendable, Equatable {
    let id: String
    let path: String
    let manifest: LiteRTModelManifest

    /// Gemma 4 E4B, essential on first install and update (`AssetPacks/Gemma4-E4B.json`, and
    /// `AssetPacks/Mac-Gemma4-E4B.json` for the Mac app).
    static let e4b = AngroveModelAssetPack(
        id: "angrove-gemma4-e4b-0b2a8980",
        path: "Models/angrove-gemma4-e4b-0b2a8980/gemma-4-E4B-it.litertlm",
        manifest: .angrove
    )

    #if os(macOS)
    // Mac-only packs. To ship another model: add its pack here (ID and path end in its digest
    // prefix), list it in `all`, give it a `MacModelTier`, and add an `AssetPacks/Mac-*.json`
    // manifest with the same ID and path. Delivery, download state and receipts follow the pack.

    /// The Mac's Large tier, Gemma 4 12B, downloaded on demand (`AssetPacks/Mac-Gemma4-12B.json`).
    static let gemma12B = AngroveModelAssetPack(
        id: "angrove-gemma4-12b-58fd31b7",
        path: "Models/angrove-gemma4-12b-58fd31b7/gemma-4-12B-it.litertlm",
        // Stock litert-community/gemma-4-12B-it-litert-lm package. Needs LiteRT-LM 0.17+.
        manifest: LiteRTModelManifest(
            fileName: "gemma-4-12B-it.litertlm",
            byteCount: 6_883_278_368,
            sha256: "58fd31b778ca2c21c80d634fb34fc5a89d11d563a38dfd3cbf1b40dbf252a8b6"
        )
    )
    static let all = [e4b, gemma12B]
    #else
    static let all = [e4b]
    #endif

    /// The iPhone's one pack; existing call sites read these.
    static var id: String { e4b.id }
    static var path: String { e4b.path }

    static func pack(for manifest: LiteRTModelManifest) -> AngroveModelAssetPack? {
        all.first { $0.manifest == manifest }
    }
}

nonisolated protocol ManagedModelAssetProviding: Sendable {
    func availableModelURL() async throws -> URL
    func availableModelURL(onStatus: @escaping @Sendable (ModelDeliveryPhase) async -> Void) async throws -> URL
}

extension ManagedModelAssetProviding {
    nonisolated func availableModelURL(onStatus: @escaping @Sendable (ModelDeliveryPhase) async -> Void) async throws -> URL {
        try await availableModelURL()
    }
}

nonisolated struct AppleHostedModelAssets: ManagedModelAssetProviding {
    var pack: AngroveModelAssetPack = .e4b

    static func isAvailableLocally(_ pack: AngroveModelAssetPack = .e4b) -> Bool {
        #if os(macOS)
        guard canUseAppleHosting else { return false }
        #endif
        return AssetPackManager.shared.assetPackIsAvailableLocally(withID: pack.id)
    }

    #if os(macOS)
    /// Whether this Mac build may call Background Assets. `AssetPackManager` trapped on the first
    /// call in a development-signed build (2026-10-17) rather than reporting an error, so only
    /// App Store and TestFlight installs (which carry a store receipt) use it, plus builds run
    /// with `ANGROVE_BACKGROUND_ASSETS_DEVELOPMENT=1` against Apple's `ba-serve` mock server.
    static let canUseAppleHosting: Bool = {
        if ProcessInfo.processInfo.environment["ANGROVE_BACKGROUND_ASSETS_DEVELOPMENT"] == "1" { return true }
        let receipt = Bundle.main.bundleURL.appending(path: "Contents/_MASReceipt/receipt")
        return FileManager.default.fileExists(atPath: receipt.path)
    }()
    #endif

    func availableModelURL() async throws -> URL {
        try await availableModelURL(onStatus: { _ in })
    }

    func availableModelURL(onStatus: @escaping @Sendable (ModelDeliveryPhase) async -> Void) async throws -> URL {
        try Task.checkCancellation()
        #if os(macOS)
        guard Self.canUseAppleHosting else { throw LiteRTModelStoreError.modelMissing }
        #endif
        let manager = AssetPackManager.shared
        let pack = self.pack
        await onStatus(.waiting)
        let observer = Task {
            var progressTask: Task<Void, Never>?
            defer { progressTask?.cancel() }
            for await update in manager.statusUpdates(forAssetPackWithID: pack.id) {
                guard !Task.isCancelled else { return }
                progressTask?.cancel()
                switch update {
                case .began: await onStatus(.waiting)
                case .paused: await onStatus(.paused)
                case let .downloading(_, progress):
                    progressTask = Task {
                        while !Task.isCancelled {
                            await onStatus(.downloading(completed: progress.completedUnitCount, total: progress.totalUnitCount))
                            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                        }
                    }
                case .finished: await onStatus(.verifying)
                case let .failed(_, error): await onStatus(.failed(.classify(error)))
                @unknown default: break
                }
            }
        }
        defer { observer.cancel() }
        let assetPack: AssetPack
        if #available(iOS 27, macOS 27, *) {
            let manifest = try await manager.manifest
            guard let selected = manifest.assetPack(withID: pack.id) else {
                throw LiteRTModelStoreError.modelMissing
            }
            assetPack = selected
        } else {
            assetPack = try await manager.assetPack(withID: pack.id)
        }
        // Keep the version selected by the app. Never request independent model updates while
        // a runtime might have the current model mapped into memory.
        try await manager.ensureLocalAvailability(of: assetPack, requireLatestVersion: false)
        try Task.checkCancellation()
        // URLs are process-local. Do not save them in preferences or verification receipts.
        return try manager.url(for: FilePath(pack.path))
    }
}

/// Stops detached progress callbacks from overwriting verification or the final result.
actor ModelDeliveryStatusRelay {
    private var open = true
    private let report: @Sendable (ModelDeliveryPhase) async -> Void
    init(report: @escaping @Sendable (ModelDeliveryPhase) async -> Void) { self.report = report }
    func send(_ phase: ModelDeliveryPhase) async {
        guard open else { return }
        await report(phase)
    }
    func close() { open = false }
}

/// Coalesces runtime preparation and verifies bytes before handing a path to LiteRT. Hashing
/// streams bounded chunks on a worker task, without making another model file or Data copy.
actor AppleHostedModelDelivery {
    static let shared = AppleHostedModelDelivery(onStatus: { phase in
        await ModelDeliveryState.shared.update(phase)
    })

    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var registry: [String: AppleHostedModelDelivery] = [:]

    /// The one delivery for a manifest's pack, so concurrent loads of a model coalesce; nil for a
    /// model no pack ships. E4B keeps `shared`; any other pack gets its own on first use.
    static func delivery(for manifest: LiteRTModelManifest) -> AppleHostedModelDelivery? {
        guard let pack = AngroveModelAssetPack.pack(for: manifest) else { return nil }
        if pack == .e4b { return shared }
        return registryLock.withLock {
            if let existing = registry[pack.id] { return existing }
            let delivery = AppleHostedModelDelivery(assets: AppleHostedModelAssets(pack: pack), pack: pack,
                onStatus: { phase in await ModelDeliveryState.state(for: pack).update(phase) })
            registry[pack.id] = delivery
            return delivery
        }
    }

    private let assets: any ManagedModelAssetProviding
    private let pack: AngroveModelAssetPack
    private let onStatus: @Sendable (ModelDeliveryPhase) async -> Void
    private var inFlight: (manifest: LiteRTModelManifest, task: Task<URL, Error>)?

    init(assets: any ManagedModelAssetProviding = AppleHostedModelAssets(),
         pack: AngroveModelAssetPack = .e4b,
         onStatus: @escaping @Sendable (ModelDeliveryPhase) async -> Void = { _ in }) {
        self.assets = assets
        self.pack = pack
        self.onStatus = onStatus
    }

    func prepareModel(manifest: LiteRTModelManifest = .angrove) async throws -> URL {
        // The shared production instance uses one pinned manifest. Tests use separate instances.
        if let inFlight {
            guard inFlight.manifest == manifest else {
                throw LiteRTModelStoreError.invalidModelDigest
            }
            let url = try await inFlight.task.value
            try Task.checkCancellation()
            return url
        }
        try Task.checkCancellation()
        let assets = self.assets
        let pack = self.pack
        let onStatus = self.onStatus
        let task = Task.detached(priority: .utility) {
            let relay = ModelDeliveryStatusRelay(report: onStatus)
            let url: URL
            do {
                url = try await assets.availableModelURL(onStatus: { await relay.send($0) })
            } catch {
                await relay.close()
                throw error
            }
            await relay.close()
            await onStatus(.verifying)
            let store = LiteRTModelStore(manifest: manifest)
            try store.validateModel(at: url)
            // A full digest reads every byte of a multi-gigabyte file. Skip it while the file is
            // provably the one already verified: same pinned digest, inode, size and timestamp.
            let fingerprint = try ModelVerificationReceipt(manifest: manifest, url: url, pack: pack)
            if !fingerprint.matchesStored() {
                guard try LiteRTModelInstaller.sha256(of: url) == manifest.sha256 else {
                    ModelVerificationReceipt.clear(pack: pack)
                    throw LiteRTModelStoreError.invalidModelDigest
                }
                fingerprint.store()
            }
            return url
        }
        inFlight = (manifest, task)
        defer { inFlight = nil }
        do {
            let url = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try Task.checkCancellation()
            await onStatus(.ready)
            return url
        } catch {
            await onStatus(error is CancellationError ? .notInstalled : .failed(.classify(error)))
            throw error
        }
    }
}

/// Identifies a model file whose bytes already matched the pinned digest. It records file
/// identity only, never the process-local URL, and is not personal data, so its key deliberately
/// avoids the encrypted `aquinas`/`angrove` preference prefixes.
nonisolated struct ModelVerificationReceipt: Codable, Equatable {
    static let defaultsKey = "modelDelivery.verifiedFile.v1"

    let sha256: String
    let packID: String
    let size: Int64
    let fileNumber: UInt64
    let modified: Date

    /// The iPhone's E4B receipt keeps its original key; other packs get one each.
    static func defaultsKey(for pack: AngroveModelAssetPack) -> String {
        pack == .e4b ? defaultsKey : "\(defaultsKey).\(pack.id)"
    }

    init(manifest: LiteRTModelManifest, url: URL, pack: AngroveModelAssetPack = .e4b) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = (attributes[.size] as? NSNumber)?.int64Value,
              let fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
              let modified = attributes[.modificationDate] as? Date else {
            throw LiteRTModelStoreError.modelMissing
        }
        self.sha256 = manifest.sha256
        self.packID = pack.id
        self.size = size
        self.fileNumber = fileNumber
        self.modified = modified
    }

    private var key: String {
        Self.defaultsKey(for: AngroveModelAssetPack.all.first { $0.id == packID } ?? .e4b)
    }

    func matchesStored(in defaults: UserDefaults = .standard) -> Bool {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(Self.self, from: data) else { return false }
        return stored == self
    }

    func store(in defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: key)
    }

    static func clear(in defaults: UserDefaults = .standard, pack: AngroveModelAssetPack = .e4b) {
        defaults.removeObject(forKey: defaultsKey(for: pack))
    }
}
