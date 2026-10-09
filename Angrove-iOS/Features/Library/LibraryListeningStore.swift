import Foundation
import Observation
import os

/// Word offsets in the complete edition, independent of the page currently being synthesized.
nonisolated struct LibraryListeningIndex: Sendable {
    private static let cache = OSAllocatedUnfairLock<[String: LibraryListeningIndex]>(initialState: [:])
    struct Entry: Sendable {
        let chunkIndex: Int
        let offset: Int
        let count: Int
    }
    let entries: [Entry]
    let byChunk: [Int: Entry]
    let totalWords: Int

    static func forWork(_ workID: String, passages: [LibraryPassage]) -> Self {
        if let existing = cache.withLock({ $0[workID] }) { return existing }
        let index = Self(passages: passages)
        cache.withLock { $0[workID] = index }
        return index
    }

    init(passages: [LibraryPassage]) {
        var offset = 0
        entries = passages.sorted { $0.chunkIndex < $1.chunkIndex }.map { passage in
            let count = LibraryTextFormatter.cleaned(passage.text).split(whereSeparator: \.isWhitespace).count
            defer { offset += count }
            return Entry(chunkIndex: passage.chunkIndex, offset: offset, count: count)
        }
        byChunk = Dictionary(uniqueKeysWithValues: entries.map { ($0.chunkIndex, $0) })
        totalWords = offset
    }

    func progress(at word: Int) -> Double {
        guard totalWords > 0, let entry = byChunk[word / 100_000] else { return 0 }
        return min(1, max(0, Double(entry.offset + min(word % 100_000, entry.count)) / Double(totalWords)))
    }

    func wordAfterParagraph(containing word: Int) -> Int {
        let chunk = word / 100_000
        guard let entry = byChunk[chunk] else { return word }
        if let next = entries.first(where: { $0.chunkIndex > chunk && $0.count > 0 }) {
            return next.chunkIndex * 100_000
        }
        return chunk * 100_000 + entry.count
    }
}

enum LibraryListeningActions {
    static func request(for work: LibraryWork, startsListening: Bool = false) -> LibraryNavigationRequest {
        let speech = ResponseSpeechPlayer.shared
        let bookmark = LibraryListeningStore.shared.bookmark(for: work.id)
        let activeWord = speech.activeLibraryWorkID == work.id ? speech.activeWord ?? speech.firstWord : nil
        let savedWord = startsListening && bookmark?.progress == 1 ? nil : bookmark?.wordIndex
        let word = activeWord ?? savedWord
        if activeWord != nil { speech.requestScrollToActiveWord() }
        return LibraryNavigationRequest(sourceTitle: work.title, sourceName: work.title, sourceID: work.id,
            readerChunkIndex: word.map { $0 / 100_000 }, listeningWordIndex: word, startsListening: startsListening)
    }

    static func toggle(_ work: LibraryWork, open: (LibraryNavigationRequest) -> Void) {
        let speech = ResponseSpeechPlayer.shared
        if speech.activeLibraryWorkID == work.id, speech.phase != .idle {
            if speech.isPaused { speech.resume() } else { speech.pause() }
        } else {
            open(request(for: work, startsListening: true))
        }
    }
}

nonisolated struct LibraryListeningBookmark: Codable, Equatable, Sendable {
    let workID: String
    let title: String
    let wordIndex: Int
    let progress: Double
    var readerChunkIndex: Int { wordIndex / 100_000 }
}

/// Listening history is personal data and uses the app's encrypted preferences boundary.
@Observable
final class LibraryListeningStore {
    static let shared = LibraryListeningStore()
    static let storageKey = "aquinas.library.listening.v1"
    private(set) var bookmarks: [String: LibraryListeningBookmark] = [:]
    private(set) var mostRecentWorkID: String?
    @ObservationIgnored private let preferences: PrivatePreferences

    private nonisolated struct Snapshot: Codable {
        let bookmarks: [String: LibraryListeningBookmark]
        let mostRecentWorkID: String?
    }

    init(preferences: PrivatePreferences = .standard) {
        self.preferences = preferences
        do {
            if let data = try preferences.read(Self.storageKey) as? Data {
                let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
                bookmarks = snapshot.bookmarks
                mostRecentWorkID = snapshot.mostRecentWorkID
            }
        } catch { PersonalDataProtection.report(error) }
    }

    func bookmark(for workID: String) -> LibraryListeningBookmark? { bookmarks[workID] }

    func record(workID: String, title: String, wordIndex: Int, progress: Double) {
        bookmarks[workID] = LibraryListeningBookmark(workID: workID, title: title,
            wordIndex: max(0, wordIndex), progress: min(1, max(0, progress)))
        mostRecentWorkID = workID
        do {
            let snapshot = Snapshot(bookmarks: bookmarks, mostRecentWorkID: mostRecentWorkID)
            try preferences.write(try JSONEncoder().encode(snapshot), key: Self.storageKey)
        } catch { PersonalDataProtection.report(error, duringWrite: true) }
    }
}
