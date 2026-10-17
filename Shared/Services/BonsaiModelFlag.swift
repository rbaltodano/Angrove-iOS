import Foundation

/// Developer flag for running Ternary Bonsai 2 9B through llama.cpp instead of Gemma 4 E4B.
/// Off by default. Turn it on with the `--bonsai-9b` launch argument or the
/// `angrove.dev.bonsai9b` default, and place the model file in Application Support/Bonsai
/// (or Documents/Bonsai on iPhone, so it can be copied in through Finder).
nonisolated enum BonsaiModelFlag {
    static let defaultsKey = "angrove.dev.bonsai9b"
    static let launchArgument = "--bonsai-9b"
    static let modelFileName = "Ternary-Bonsai-2-9B-PQ2_0.gguf"
    /// Matches the published file (Hugging Face prism-ml/Ternary-Bonsai-2-9B-gguf).
    static let modelByteCount: Int64 = 2_416_851_840

    static var isEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(launchArgument)
            || UserDefaults.standard.bool(forKey: defaultsKey)
        #else
        false
        #endif
    }

    /// The installed model, when its size matches the published file.
    static func installedModelURL(fileManager: FileManager = .default) -> URL? {
        let roots: [FileManager.SearchPathDirectory] = [.applicationSupportDirectory, .documentDirectory]
        for root in roots {
            guard let base = fileManager.urls(for: root, in: .userDomainMask).first else { continue }
            let url = base.appending(path: "Bonsai").appending(path: modelFileName)
            let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
            if size == modelByteCount { return url }
        }
        return nil
    }
}
