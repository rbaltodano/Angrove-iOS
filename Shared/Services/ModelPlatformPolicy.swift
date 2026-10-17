import Foundation

/// What differs about on-device models between the iPhone and Mac apps. Shared model code reads
/// `ModelPlatformPolicy.current`, which each app defines in its own folder
/// (`iOS/Services/ModelPlatformPolicy+iOS.swift`, `macOS/Platform/ModelPlatformPolicy+Mac.swift`),
/// so platform rules live with the platform rather than as `#if os(…)` branches in Shared.
nonisolated struct ModelPlatformPolicy: Sendable {
    /// Apple-hosted packs this app can download besides E4B.
    let additionalPacks: [AngroveModelAssetPack]
    /// Folder under Application Support and Caches holding the app's model files; nil for the root.
    let storageFolder: String?
    /// Whether a verified local model file is used before the Apple-hosted pack.
    let prefersLocalCopy: Bool
    /// Whether this build may call Background Assets at all.
    let canUseAppleHosting: @Sendable () -> Bool
    /// Whether a manifest's model is already usable without its pack. Delivery state reports such
    /// a model as `.development`, which shows no download status.
    let hasLocalCopy: @Sendable (LiteRTModelManifest) -> Bool
    /// Advice when a download runs out of space.
    let storageFailureMessage: LocalizedStringResource

    /// `component` inside this app's storage folder, e.g. "Angrove-macOS/Models" on the Mac.
    func storagePath(_ component: String) -> String {
        storageFolder.map { "\($0)/\(component)" } ?? component
    }
}
