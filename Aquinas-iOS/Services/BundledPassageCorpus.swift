import Foundation
import os

/// The bundled `passages.json` is tens of megabytes. The Library homepage, the Library reader,
/// and on-device grounding all need it, so it is decoded at most once per file and shared,
/// together with a per-work index, instead of each caller decoding its own copy.
nonisolated final class BundledPassageCorpus: Sendable {
    let passages: [LibraryPassage]
    /// Passage indices for each source, in corpus order.
    let indicesBySource: [String: [Int]]

    private init(passages: [LibraryPassage]) {
        self.passages = passages
        self.indicesBySource = Dictionary(grouping: passages.indices, by: { passages[$0].sourceId })
    }

    /// Passages for one work, ordered by chunk index.
    func passages(forSource sourceID: String) -> [LibraryPassage] {
        (indicesBySource[sourceID] ?? []).map { passages[$0] }.sorted { $0.chunkIndex < $1.chunkIndex }
    }

    private static let cache = OSAllocatedUnfairLock<[URL: BundledPassageCorpus]>(initialState: [:])
    /// Serializes decoding so concurrent first callers don't each decode the file.
    private static let loadLock = NSLock()

    static func load(from url: URL) throws -> BundledPassageCorpus {
        if let cached = cache.withLock({ $0[url.standardizedFileURL] }) { return cached }
        loadLock.lock()
        defer { loadLock.unlock() }
        if let cached = cache.withLock({ $0[url.standardizedFileURL] }) { return cached }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let corpus = BundledPassageCorpus(passages: try JSONDecoder().decode([LibraryPassage].self, from: data))
        cache.withLock { $0[url.standardizedFileURL] = corpus }
        return corpus
    }

    /// The corpus shipped in the app bundle, or `nil` when it is missing or unreadable.
    static func bundled(in bundle: Bundle = .main) -> BundledPassageCorpus? {
        guard let url = bundledURL(in: bundle) else { return nil }
        return try? load(from: url)
    }

    static func bundledURL(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "passages", withExtension: "json", subdirectory: "LocalGrounding")
            ?? bundle.url(forResource: "passages", withExtension: "json")
    }
}
