import Foundation

public nonisolated struct LiteRTModelManifest: Sendable, Equatable {
    // Gemma 4 E4B instruction-tuned, LiteRT Community standard package (M4-Ls in the E4B
    // migration ledger). Mixed INT4/INT2/INT8 weights, consistent with QAT, but Google hasn't
    // confirmed its provenance, so it's labelled "LiteRT Community" rather than "QAT" (plan D8).
    // Not fine-tuned. Text-only here (see LiteRTAngroveRuntime).
    // Rollback: the fine-tuned E2B package, "gemma-4-E2B-it.litertlm",
    // 3_862_121_696 bytes, SHA-256 9a6345f1a6cd39283f957977c84d31cc63b8dd56f2b8fffeb784940f63365282.
    public static let angrove = LiteRTModelManifest(
        fileName: "gemma-4-E4B-it.litertlm",
        byteCount: 3_659_530_240,
        sha256: "0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0"
    )

    public let fileName: String
    public let byteCount: Int64
    public let sha256: String

    public init(fileName: String, byteCount: Int64, sha256: String) {
        self.fileName = fileName
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

/// Versioned pack IDs and paths prevent a later model update from replacing the model that a
/// live engine is using. Changing the model requires a new ID/path and an app manifest change.
public nonisolated struct AngroveModelAssetPack: Sendable, Equatable {
    public let id: String
    public let path: String
    public let manifest: LiteRTModelManifest

    public init(id: String, path: String, manifest: LiteRTModelManifest) {
        self.id = id
        self.path = path
        self.manifest = manifest
    }

    /// Gemma 4 E4B, essential on first install and update (`AssetPacks/Gemma4-E4B.json`, and
    /// `AssetPacks/Mac-Gemma4-E4B.json` for the Mac app).
    public static let e4b = AngroveModelAssetPack(
        id: "angrove-gemma4-e4b-0b2a8980",
        path: "Models/angrove-gemma4-e4b-0b2a8980/gemma-4-E4B-it.litertlm",
        manifest: .angrove
    )

    /// The iPhone's one pack; existing call sites read these.
    public static var id: String { e4b.id }
    public static var path: String { e4b.path }
}
