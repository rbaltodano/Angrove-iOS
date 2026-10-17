import Foundation

extension ModelPlatformPolicy {
    /// The iPhone: one essential E4B pack. Only source-checkout Debug builds use a local model.
    nonisolated static let current = ModelPlatformPolicy(
        additionalPacks: [],
        storageFolder: nil,
        prefersLocalCopy: isDebugBuild,
        canUseAppleHosting: { true },
        hasLocalCopy: { _ in isDebugBuild && LiteRTModelStore().hasInstalledModel() },
        storageFailureMessage: "There isn’t enough space to download the model. Free up storage in iPhone Settings, then retry. Installation may need more space than the 3.66 GB model file."
    )

    private nonisolated static let isDebugBuild: Bool = {
        #if DEBUG
        true
        #else
        false
        #endif
    }()
}
