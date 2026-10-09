import CryptoKit
import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Library listening history", .serialized)
@MainActor
struct LibraryListeningStoreTests {
    @Test("Progress uses the whole work and resumes at paragraph boundaries")
    func completeWorkProgress() {
        let index = LibraryListeningIndex(passages: [
            LibraryPassage(text: "one two three", title: "A", sourceId: "test", chunkIndex: 2),
            LibraryPassage(text: "four five", title: "B", sourceId: "test", chunkIndex: 7)
        ])
        #expect(index.totalWords == 5)
        #expect(index.progress(at: 200_001) == 0.2)
        #expect(index.progress(at: 700_000) == 0.6)
        #expect(index.progress(at: 700_001) == 0.8)
        #expect(index.wordAfterParagraph(containing: 200_002) == 700_000)
        #expect(index.wordAfterParagraph(containing: 700_001) == 700_002)
        #expect(index.progress(at: 700_002) == 1)
        #expect(index.progress(at: 700_099) == 1)
        #expect(LibraryListeningIndex(passages: []).progress(at: 0) == 0)
    }

    @Test("Bookmarks and the most recent work survive reload in encrypted storage")
    func encryptedRoundTrip() throws {
        let suite = "LibraryListeningTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = SymmetricKey(size: .bits256)
        let preferences = PrivatePreferences(defaults: defaults, cipher: LocalDataCipher { _ in key })
        let store = LibraryListeningStore(preferences: preferences)
        #expect(store.mostRecentWorkID == nil)
        store.record(workID: "first", title: "Private reading", wordIndex: 700_012, progress: 0.4)
        store.record(workID: "second", title: "Other reading", wordIndex: 100_003, progress: 0.2)
        let reloaded = LibraryListeningStore(preferences: preferences)
        #expect(reloaded.mostRecentWorkID == "second")
        #expect(reloaded.bookmark(for: "first") == store.bookmark(for: "first"))
        #expect(reloaded.bookmark(for: "first")?.readerChunkIndex == 7)
        #expect(reloaded.bookmark(for: "second")?.wordIndex == 100_003)
        let bytes = try #require(defaults.data(forKey: LibraryListeningStore.storageKey))
        #expect(LocalDataCipher.isEncrypted(bytes))
        #expect(!String(decoding: bytes, as: UTF8.self).contains("Private reading"))
        reloaded.record(workID: "first", title: "Private reading", wordIndex: 700_020, progress: 0.5)
        #expect(LibraryListeningStore(preferences: preferences).mostRecentWorkID == "first")
    }

    @Test("Resuming keeps exact word offsets, including Scripture's silent verse numbers")
    func resumeWord() {
        let passages = [
            LibraryPassage(text: "1 In the beginning 2 was the Word", title: "A", sourceId: "web-bible", chunkIndex: 3),
            LibraryPassage(text: "The next paragraph", title: "B", sourceId: "web-bible", chunkIndex: 9)
        ]
        let units = LibrarySpeech.units(for: passages, sourceID: "web-bible")
        let remaining = SpokenUnit.units(units, fromWord: 300_006)
        #expect(remaining.first?.words.first?.index == 300_006)
        #expect(remaining.first?.text == "the Word")
        #expect(remaining.last?.words.first?.index == 900_000)
        #expect(SpokenUnit.units(units, fromWord: 900_003).isEmpty)
    }
}
