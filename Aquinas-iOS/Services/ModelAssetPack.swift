//
//  ModelAssetPack.swift
//  Aquinas-iOS
//

import BackgroundAssets
import Foundation
import System

/// The Apple-hosted asset pack that carries the on-device model in TestFlight and App Store builds.
///
/// The model is too large to ship inside the app: with it, the app would pass the App Store's
/// 4 GB limit. Apple hosts the pack beside the app ("Apple-Hosted Background Assets", iOS 26+),
/// and with an essential download policy the system downloads it as part of installing the app,
/// so it is on the device before first launch. The pack is built by
/// `Tools/ModelAssetPack/package.sh`; see `Documentation/Model-Asset-Pack.md`.
nonisolated enum ModelAssetPack {
    static let id = "AquinasModel"

    /// Whether this build is configured for Apple-hosted asset packs. Development builds that
    /// bundle the model in `LocalModels/` aren't, and never touch the asset-pack system.
    static var isConfigured: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "BAHasManagedAssetPacks") as? Bool) == true
    }

    /// The model's path inside the pack, which is also its path in the packaging directory.
    static func relativePath(for manifest: LiteRTModelManifest) -> String {
        "Models/\(manifest.fileName)"
    }

    /// The model file, when the pack is on the device.
    static func localModelURL(for manifest: LiteRTModelManifest) -> URL? {
        guard isConfigured else { return nil }
        return try? AssetPackManager.shared.url(
            for: FilePath(relativePath(for: manifest))
        )
    }

    /// Downloads the pack if the system hasn't yet, for example after the user offloaded it.
    /// Returns at once when it is already local.
    static func ensureAvailable() async throws {
        guard isConfigured else { return }
        let pack = try await AssetPackManager.shared.assetPack(withID: id)
        try await AssetPackManager.shared.ensureLocalAvailability(of: pack)
    }
}
