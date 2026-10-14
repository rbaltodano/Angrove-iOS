//
//  LibrarySpeech.swift
//  Angrove-iOS
//

import Foundation

/// Reading a Library page aloud. Each reader paragraph is a unit, and each word of its cleaned
/// text a spoken word whose index is `chunkIndex * wordsPerChunk + position`, so a paragraph can
/// find its own words in the player's timeline without counting those before it.
enum LibrarySpeech {
    static let wordsPerChunk = 100_000

    struct Token {
        /// Position among all the paragraph's whitespace-separated tokens.
        let local: Int
        let range: NSRange
        let text: String
    }

    private static let tokenPattern = try! NSRegularExpression(pattern: #"\S+"#)

    /// The words of an already-cleaned paragraph. The Bible's verse numbers are left out: they are
    /// markers, not words to say.
    static func tokens(in clean: String, sourceID: String) -> [Token] {
        let text = clean as NSString
        var local = 0
        var tokens: [Token] = []
        for match in tokenPattern.matches(in: clean, range: NSRange(location: 0, length: text.length)) {
            let word = text.substring(with: match.range)
            defer { local += 1 }
            if sourceID == "web-bible", word.count <= 3, word.allSatisfy(\.isNumber) { continue }
            tokens.append(Token(local: local, range: match.range, text: word))
        }
        return tokens
    }

    static func units(for passages: [LibraryPassage], sourceID: String) -> [SpokenUnit] {
        passages.compactMap { passage in
            let words = tokens(in: LibraryTextFormatter.cleaned(passage.text), sourceID: sourceID).map {
                SpokenUnit.Word(index: passage.chunkIndex * wordsPerChunk + $0.local, token: $0.text)
            }
            return words.isEmpty ? nil : SpokenUnit(words: words)
        }
    }

    /// Identifies a page's reading to the speech player.
    static func key(workID: String, outlineID: String) -> String {
        "library:\(workID):\(outlineID)"
    }
}
