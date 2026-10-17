import Foundation

/// Whether a model is already usable on this Mac without its Apple-hosted pack (Shared delivery
/// state reports these as `.development`, which shows no download status).
nonisolated enum MacModelLocalCopy {
    static func isInstalled(_ manifest: LiteRTModelManifest) -> Bool {
        MacModelTier.allCases.first { $0.manifest == manifest }?.modelStore().hasInstalledModel() == true
    }
}
