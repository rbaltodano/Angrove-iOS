import Foundation

/// Preserves the batch guard's decisions at each chunk while retaining completed word windows
/// and script counts. The unfinished word is rescanned because token boundaries can split words.
nonisolated struct IncrementalGenerationGuard {
    private static let words = try! NSRegularExpression(pattern: #"[\p{L}\p{N}]+"#)
    private var text = ""
    private var rescanOffset = 0
    private var completed: [(word: String, offset: Int)] = []
    private var first: [Int: [String: Int]] = [10: [:], 16: [:], 24: [:]]
    private var repeated: [Int: Int] = [:]
    private var letterCount = 0
    private var suspiciousCount = 0
    private var sentences: [String] = []
    private var currentSentence = ""
    private var pendingSentenceCharacter = ""

    /// Explicit because Swift 6.2 (Xcode 26) makes the synthesized one private: every stored
    /// property is private.
    init() {}

    mutating func append(_ delta: String) -> (corrupt: Bool, repetitionPrefix: String?) {
        for scalar in delta.unicodeScalars where CharacterSet.letters.contains(scalar) {
            letterCount += 1
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x9FFF, 0xAC00...0xD7AF, 0x0600...0x06FF:
                suspiciousCount += 1
            default: break
            }
        }
        // A chunk can split CRLF or extend a punctuation grapheme with a combining scalar.
        // Keep the last grapheme provisional so segmentation matches the accumulated String.
        let characters = Array(pendingSentenceCharacter + delta)
        for character in characters.dropLast() {
            Self.consumeSentence(character, sentences: &sentences, current: &currentSentence)
        }
        pendingSentenceCharacter = characters.last.map(String.init) ?? ""
        var visibleSentences = sentences
        var visibleCurrent = currentSentence
        if let last = characters.last {
            Self.consumeSentence(last, sentences: &visibleSentences, current: &visibleCurrent)
        }
        text += delta
        let corrupt = letterCount >= 40 && suspiciousCount >= 12
            && Double(suspiciousCount) / Double(letterCount) >= 0.08
        let source = text as NSString
        let matches = Self.words.matches(in: text, range: NSRange(location: rescanOffset, length: source.length - rescanOffset))
        var pendingWord: (word: String, offset: Int)?
        for match in matches {
            let word = (source.substring(with: match.range).lowercased(), match.range.location)
            if NSMaxRange(match.range) == source.length {
                pendingWord = word
                rescanOffset = match.range.location
            } else {
                completed.append(word)
                recordLastWindow()
                rescanOffset = NSMaxRange(match.range)
            }
        }
        if pendingWord == nil { rescanOffset = source.length }

        // Adjacent sentence repetition takes precedence over phrase repetition in the batch guard.
        let lastSentences = (visibleSentences + (Self.normalize(visibleCurrent).isEmpty ? [] : [visibleCurrent])).suffix(2)
        if lastSentences.count == 2 {
            let items = Array(lastSentences)
            let last = Self.normalize(items[1])
            if last.count >= 40, last == Self.normalize(items[0]),
               let range = text.range(of: items[1], options: .backwards) {
                return (corrupt, String(text[..<range.lowerBound]))
            }
        }
        let count = completed.count + (pendingWord == nil ? 0 : 1)
        var earliest: Int?
        for size in [10, 16, 24] where count >= size * 2 {
            if let location = repeated[size] { earliest = min(earliest ?? location, location) }
            if let pendingWord {
                let start = count - size
                let window = Array(completed.suffix(size - 1)) + [pendingWord]
                let phrase = window.map(\.word).joined(separator: " ")
                if let original = first[size]?[phrase], start - original >= size {
                    let location = window[0].offset
                    earliest = min(earliest ?? location, location)
                }
            }
        }
        return (corrupt, earliest.map { source.substring(to: $0) })
    }

    private mutating func recordLastWindow() {
        for size in [10, 16, 24] where completed.count >= size {
            let start = completed.count - size
            let window = completed.suffix(size)
            let phrase = window.map(\.word).joined(separator: " ")
            if let original = first[size]?[phrase] {
                if start - original >= size, repeated[size] == nil { repeated[size] = window.first!.offset }
            } else { first[size]?[phrase] = start }
        }
    }

    private static func consumeSentence(_ character: Character, sentences: inout [String], current: inout String) {
        if ".!?\n".contains(character) {
            if !normalize(current).isEmpty {
                sentences.append(current)
                if sentences.count > 2 { sentences.removeFirst() }
            }
            current = ""
        } else { current.append(character) }
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }
}
