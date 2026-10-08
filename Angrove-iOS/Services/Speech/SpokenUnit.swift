//
//  SpokenUnit.swift
//  Angrove-iOS
//

import Foundation

/// Where a reading comes from: shown as the Lock Screen title and used to mark its conversation.
struct SpeechSource {
    var title = ""
    var conversationID: UUID?
    /// Set when the reading is a Library page, so the Reading card can lead back to the work.
    var libraryWorkID: String?
}

/// A stretch of a response read as one block (a paragraph, heading, or list item), keeping the
/// displayed word each spoken word belongs to so playback can highlight it.
struct SpokenUnit {
    struct Word {
        /// Index in the response's flat word array, as `CompletedResponseSegments` numbers it.
        let index: Int
        let token: String
    }

    var words: [Word]
    /// Where the unit begins in the response's flat word array, for units without words of their own.
    var startIndex: Int
    /// What is sent to the synthesizer. Equals the words joined, unless the unit has none.
    var text: String

    init(words: [Word]) {
        self.words = words
        startIndex = words.first?.index ?? 0
        text = words.map { InlineInsightMarkup.plainText(from: $0.token) }.joined(separator: " ")
    }

    /// A block with no displayed words of its own (an inline Insight card), spoken without highlight.
    init(unhighlightedText: String, at startIndex: Int = 0) {
        words = []
        self.startIndex = startIndex
        text = unhighlightedText
    }

    static func units(from segments: [ResponseSegment]) -> [SpokenUnit] {
        segments.flatMap { segment -> [SpokenUnit] in
            func words(_ range: Range<Int>) -> [Word] {
                range.map { Word(index: segment.wordStart + $0, token: segment.words[$0]) }
            }
            switch segment.kind {
            case .paragraph, .heading:
                return [SpokenUnit(words: words(0..<segment.words.count))]
            case .orderedList, .unorderedList:
                let offsets = segment.itemWordOffsets
                return offsets.indices.map { item in
                    let end = item + 1 < offsets.count ? offsets[item + 1] : segment.words.count
                    return SpokenUnit(words: words(offsets[item]..<end))
                }
            case .insight(let insight):
                return [SpokenUnit(unhighlightedText: "\(insight.word)\n\(insight.meaning)", at: segment.wordStart)]
            }
        }
    }

    /// The units from displayed word `index` onward, with the unit that word is in cut to begin there.
    static func units(_ units: [SpokenUnit], fromWord index: Int) -> [SpokenUnit] {
        units.compactMap { unit in
            guard !unit.words.isEmpty else { return unit.startIndex > index ? unit : nil }
            guard let first = unit.words.firstIndex(where: { $0.index >= index }) else { return nil }
            return first == 0 ? unit : SpokenUnit(words: Array(unit.words[first...]))
        }
    }

    /// How long a token takes to say, relative to others. Used on both the displayed words and the
    /// normalized sentences so the two can be lined up without a forced aligner.
    static func weight(of token: String) -> Double {
        let visible = token.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression
        )
        let core = visible.filter { $0.isLetter || $0.isNumber }.count
        guard core > 0 else { return 0 }
        var weight = Double(core)
        if let last = visible.last {
            if ".!?…".contains(last) { weight += 3 } else if ",;:—".contains(last) { weight += 1.5 }
        }
        return weight
    }
}
