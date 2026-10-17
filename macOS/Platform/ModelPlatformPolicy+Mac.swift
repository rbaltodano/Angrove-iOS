import Foundation

extension ModelPlatformPolicy {
    /// The Mac: E4B plus larger on-demand packs, files under "Angrove-macOS", and a verified local
    /// copy always used first (development, or a Mac set up before Apple hosting).
    nonisolated static let current = ModelPlatformPolicy(
        additionalPacks: [.gemma12B],
        storageFolder: "Angrove-macOS",
        prefersLocalCopy: true,
        canUseAppleHosting: { canUseAppleHosting },
        hasLocalCopy: { MacModelLocalCopy.isInstalled($0) },
        storageFailureMessage: "There isn’t enough space to download the model. Free up storage on this Mac, then retry. Installation may need more space than the model file."
    )

    /// `AssetPackManager` trapped on its first call in a development-signed build (2026-10-17)
    /// rather than reporting an error, so only App Store and TestFlight installs (which carry a
    /// store receipt) use it, plus builds run with `ANGROVE_BACKGROUND_ASSETS_DEVELOPMENT=1`
    /// against Apple's `ba-serve` mock server.
    nonisolated static let canUseAppleHosting: Bool = {
        if ProcessInfo.processInfo.environment["ANGROVE_BACKGROUND_ASSETS_DEVELOPMENT"] == "1" { return true }
        let receipt = Bundle.main.bundleURL.appending(path: "Contents/_MASReceipt/receipt")
        return FileManager.default.fileExists(atPath: receipt.path)
    }()
}

// Mac-only packs. To ship another desktop model: add its pack here (ID and path end in its digest
// prefix), list it in `additionalPacks` above, give it a `MacModelTier`, and add an
// `AssetPacks/Mac-*.json` manifest with the same ID and path. Delivery, download state and
// receipts follow the pack.
extension AngroveModelAssetPack {
    /// The Mac's Large tier, Gemma 4 12B, downloaded on demand (`AssetPacks/Mac-Gemma4-12B.json`).
    nonisolated static let gemma12B = AngroveModelAssetPack(
        id: "angrove-gemma4-12b-58fd31b7",
        path: "Models/angrove-gemma4-12b-58fd31b7/gemma-4-12B-it.litertlm",
        // Stock litert-community/gemma-4-12B-it-litert-lm package. Needs LiteRT-LM 0.17+.
        manifest: LiteRTModelManifest(
            fileName: "gemma-4-12B-it.litertlm",
            byteCount: 6_883_278_368,
            sha256: "58fd31b778ca2c21c80d634fb34fc5a89d11d563a38dfd3cbf1b40dbf252a8b6"
        )
    )
}
