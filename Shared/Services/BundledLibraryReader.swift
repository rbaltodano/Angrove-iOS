import Foundation
import os

/// Complete edition text is independent of the frozen retrieval chunk/embedding indices.
nonisolated enum BundledLibraryReader {
    struct Section: Decodable, Sendable {
        let id: String
        let title: String
        let lowerBound: Int
        let upperBound: Int
        let children: [Section]
    }

    struct Document: Decodable, Sendable {
        let id: String
        let title: String
        let context: String
        let filename: String
        let paragraphCount: Int
        let sections: [Section]
        let retrievalLocations: [String: Int]

        var hasValidStructure: Bool {
            paragraphCount > 0
                && Self.covers(sections, range: 0..<paragraphCount)
                && retrievalLocations.values.allSatisfy { (0..<paragraphCount).contains($0) }
        }

        func readerIndex(forRetrievalChunk index: Int) -> Int? {
            retrievalLocations[String(index)]
        }

        func loadPassages(in bundle: Bundle = .main) -> [LibraryPassage]? {
            guard let url = BundledLibraryReader.resource(filename, in: bundle),
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let passages = try? JSONDecoder().decode([LibraryPassage].self, from: data),
                  passages.count == paragraphCount,
                  passages.enumerated().allSatisfy({ $0.element.sourceId == id && $0.element.chunkIndex == $0.offset }),
                  Self.covers(sections, range: 0..<passages.count),
                  retrievalLocations.values.allSatisfy({ passages.indices.contains($0) })
            else { return nil }
            return passages
        }

        private static func covers(_ sections: [Section], range: Range<Int>) -> Bool {
            guard !sections.isEmpty else { return false }
            var next = range.lowerBound
            for section in sections {
                guard section.lowerBound == next, section.upperBound >= next,
                      section.upperBound < range.upperBound else { return false }
                if !section.children.isEmpty,
                   !covers(section.children, range: section.lowerBound..<(section.upperBound + 1)) {
                    return false
                }
                next = section.upperBound + 1
            }
            return next == range.upperBound
        }
    }

    private struct Index: Decodable {
        let schemaVersion: Int
        let documents: [Document]
    }

    private static let cache = OSAllocatedUnfairLock<[URL: [String: Document]]>(initialState: [:])

    static func document(sourceID: String, in bundle: Bundle = .main) -> Document? {
        guard let url = resource("library-index.json", in: bundle) else { return nil }
        if let cached = cache.withLock({ $0[url] }) { return cached[sourceID] }
        guard let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode(Index.self, from: data),
              index.schemaVersion == 1,
              index.documents.allSatisfy(\.hasValidStructure),
              Set(index.documents.map(\.id)).count == index.documents.count
        else { return nil }
        let documents = Dictionary(uniqueKeysWithValues: index.documents.map { ($0.id, $0) })
        cache.withLock { $0[url] = documents }
        return documents[sourceID]
    }

    private static func resource(_ filename: String, in bundle: Bundle) -> URL? {
        let name = (filename as NSString).deletingPathExtension
        return bundle.url(forResource: name, withExtension: "json", subdirectory: "LibraryDocuments")
            ?? bundle.url(forResource: name, withExtension: "json")
    }
}
