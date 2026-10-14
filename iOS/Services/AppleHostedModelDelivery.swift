import BackgroundAssets
import Foundation
import System

/// Versioned pack IDs and paths prevent a later model update from replacing the model that a
/// live engine is using. Changing the model requires a new ID/path and an app manifest change.
nonisolated enum AngroveModelAssetPack {
    static let id = "angrove-gemma4-e4b-0b2a8980"
    static let path = "Models/\(id)/gemma-4-E4B-it.litertlm"
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
    static func isAvailableLocally() -> Bool {
        AssetPackManager.shared.assetPackIsAvailableLocally(withID: AngroveModelAssetPack.id)
    }

    func availableModelURL() async throws -> URL {
        try await availableModelURL(onStatus: { _ in })
    }

    func availableModelURL(onStatus: @escaping @Sendable (ModelDeliveryPhase) async -> Void) async throws -> URL {
        try Task.checkCancellation()
        let manager = AssetPackManager.shared
        await onStatus(.waiting)
        let observer = Task {
            var progressTask: Task<Void, Never>?
            defer { progressTask?.cancel() }
            for await update in manager.statusUpdates(forAssetPackWithID: AngroveModelAssetPack.id) {
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
        let pack: AssetPack
        if #available(iOS 27, *) {
            let manifest = try await manager.manifest
            guard let selected = manifest.assetPack(withID: AngroveModelAssetPack.id) else {
                throw LiteRTModelStoreError.modelMissing
            }
            pack = selected
        } else {
            pack = try await manager.assetPack(withID: AngroveModelAssetPack.id)
        }
        // Keep the version selected by the app. Never request independent model updates while
        // a runtime might have the current model mapped into memory.
        try await manager.ensureLocalAvailability(of: pack, requireLatestVersion: false)
        try Task.checkCancellation()
        // URLs are process-local. Do not save them in preferences or verification receipts.
        return try manager.url(for: FilePath(AngroveModelAssetPack.path))
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
    private let assets: any ManagedModelAssetProviding
    private let onStatus: @Sendable (ModelDeliveryPhase) async -> Void
    private var inFlight: (manifest: LiteRTModelManifest, task: Task<URL, Error>)?

    init(assets: any ManagedModelAssetProviding = AppleHostedModelAssets(),
         onStatus: @escaping @Sendable (ModelDeliveryPhase) async -> Void = { _ in }) {
        self.assets = assets
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
            let fingerprint = try ModelVerificationReceipt(manifest: manifest, url: url)
            if !fingerprint.matchesStored() {
                guard try LiteRTModelInstaller.sha256(of: url) == manifest.sha256 else {
                    ModelVerificationReceipt.clear()
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

    init(manifest: LiteRTModelManifest, url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = (attributes[.size] as? NSNumber)?.int64Value,
              let fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
              let modified = attributes[.modificationDate] as? Date else {
            throw LiteRTModelStoreError.modelMissing
        }
        self.sha256 = manifest.sha256
        self.packID = AngroveModelAssetPack.id
        self.size = size
        self.fileNumber = fileNumber
        self.modified = modified
    }

    func matchesStored(in defaults: UserDefaults = .standard) -> Bool {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let stored = try? JSONDecoder().decode(Self.self, from: data) else { return false }
        return stored == self
    }

    func store(in defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    static func clear(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}
