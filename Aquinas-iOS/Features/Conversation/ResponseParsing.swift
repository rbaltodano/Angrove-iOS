import Foundation

// MARK: - Cached Regex

/// Compiled once per process — never inside init or hot-path functions.
enum ResponseRegex {
    static let orderedListLine = try! NSRegularExpression(pattern: #"^\s*\d+[.)]\s+(.+)"#)
    static let unorderedListLine = try! NSRegularExpression(pattern: #"^\s*[-*+]\s+(.+)"#)
    static let insightLink = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#)
    static let tokenizer   = try! NSRegularExpression(pattern: #"\S*\[[^\]]+\]\([^)]+\)\S*|\*\*[^*]+\*\*[.,!?;:]*|\*[^*]+\*[.,!?;:]*|\S+"#)
}

/// A tappable Insight link plus any punctuation or Markdown emphasis wrapped around it.
/// The model can emit `*term*` or `(term)` before annotation inserts the aq:// link,
/// yielding tokens such as `(*[term](aq://term)*)`.
struct ParsedInsightLink {
    let leadingPunctuation: String
    let title: String
    let url: URL
    let trailingPunctuation: String

    init?(token: String) {
        guard let match = ResponseRegex.insightLink.firstMatch(
            in: token,
            range: NSRange(token.startIndex..., in: token)
        ),
        match.numberOfRanges == 3,
        let fullRange = Range(match.range(at: 0), in: token),
        let titleRange = Range(match.range(at: 1), in: token),
        let urlRange = Range(match.range(at: 2), in: token),
        let parsedURL = URL(string: String(token[urlRange])) else {
            return nil
        }

        leadingPunctuation = Self.removingEmphasis(
            from: String(token[..<fullRange.lowerBound])
        )
        title = String(token[titleRange])
        url = parsedURL
        trailingPunctuation = Self.removingEmphasis(
            from: String(token[fullRange.upperBound...])
        )
    }

    private static func removingEmphasis(from text: String) -> String {
        String(text.filter { $0 != "*" })
    }
}

// MARK: - Response Segment Model

/// A parsed response block with its Markdown-level structure preserved.
struct ResponseSegment: Identifiable {
    enum Kind {
        case paragraph
        case heading(level: Int)
        case orderedList([String])
        case unorderedList([String])
        case insight(ConceptDefinition)
    }

    /// Stable for the lifetime of a response because generated blocks append in order.
    let id: Int
    let kind: Kind
    /// Flat word array for this segment (drives streaming progress).
    let words: [String]
    /// Where this segment starts in the global flat word array.
    let wordStart: Int
    /// For lists: word index (relative to segment start) where each item begins.
    let itemWordOffsets: [Int]

    var wordCount: Int { words.count }

    var isInsight: Bool {
        if case .insight = kind { return true }
        return false
    }

    var isParagraph: Bool {
        if case .paragraph = kind { return true }
        return false
    }
}

enum ResponseParser {
    // MARK: - Parsing

    /// Splits fullText into paragraph, heading, ordered-list, and unordered-list segments.
    static func parseSegments(from text: String) -> [ResponseSegment] {
        enum ListKind: Equatable {
            case ordered
            case unordered
        }

        struct RawLine {
            let listKind: ListKind?
            let headingLevel: Int?
            let content: String
            let insight: ConceptDefinition?
            let startsNewBlock: Bool
        }

        var rawLines: [RawLine] = []
        var nextLineStartsNewBlock = false
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                nextLineStartsNewBlock = true
                continue
            }

            if let insight = InlineInsightMarkup.insight(from: trimmed) {
                rawLines.append(
                    RawLine(
                        listKind: nil,
                        headingLevel: nil,
                        content: "",
                        insight: insight,
                        startsNewBlock: nextLineStartsNewBlock
                    )
                )
            } else if let match = ResponseRegex.orderedListLine.firstMatch(
                in: trimmed,
                range: NSRange(trimmed.startIndex..., in: trimmed)
            ),
               let itemRange = Range(match.range(at: 1), in: trimmed) {
                rawLines.append(
                    RawLine(
                        listKind: .ordered,
                        headingLevel: nil,
                        content: String(trimmed[itemRange]),
                        insight: nil,
                        startsNewBlock: nextLineStartsNewBlock
                    )
                )
            } else if let match = ResponseRegex.unorderedListLine.firstMatch(
                in: trimmed,
                range: NSRange(trimmed.startIndex..., in: trimmed)
            ),
                      let itemRange = Range(match.range(at: 1), in: trimmed) {
                rawLines.append(
                    RawLine(
                        listKind: .unordered,
                        headingLevel: nil,
                        content: String(trimmed[itemRange]),
                        insight: nil,
                        startsNewBlock: nextLineStartsNewBlock
                    )
                )
            } else if let heading = markdownHeading(from: trimmed) {
                rawLines.append(
                    RawLine(
                        listKind: nil,
                        headingLevel: heading.level,
                        content: heading.text,
                        insight: nil,
                        startsNewBlock: nextLineStartsNewBlock
                    )
                )
            } else {
                rawLines.append(
                    RawLine(
                        listKind: nil,
                        headingLevel: nil,
                        content: trimmed,
                        insight: nil,
                        startsNewBlock: nextLineStartsNewBlock
                    )
                )
            }
            nextLineStartsNewBlock = false
        }

        var result: [ResponseSegment] = []
        var wordCursor = 0
        var i = 0

        while i < rawLines.count {
            if let insight = rawLines[i].insight {
                result.append(
                    ResponseSegment(
                        id: result.count,
                        kind: .insight(insight),
                        words: [insight.word],
                        wordStart: wordCursor,
                        itemWordOffsets: []
                    )
                )
                wordCursor += 1
                i += 1
            } else if let listKind = rawLines[i].listKind {
                // Gather consecutive items of the same list style into one segment.
                var items: [String] = []
                while i < rawLines.count
                    && rawLines[i].listKind == listKind
                    && (items.isEmpty || !rawLines[i].startsNewBlock) {
                    items.append(rawLines[i].content)
                    i += 1
                }
                var allWords: [String] = []
                var itemOffsets: [Int] = []
                for item in items {
                    itemOffsets.append(allWords.count)
                    allWords.append(contentsOf: tokenize(item))
                }
                result.append(ResponseSegment(
                    id: result.count,
                    kind: listKind == .ordered
                        ? .orderedList(items)
                        : .unorderedList(items),
                    words: allWords,
                    wordStart: wordCursor,
                    itemWordOffsets: itemOffsets
                ))
                wordCursor += allWords.count
            } else if let headingLevel = rawLines[i].headingLevel {
                let words = tokenize(rawLines[i].content)
                result.append(ResponseSegment(
                    id: result.count,
                    kind: .heading(level: headingLevel),
                    words: words,
                    wordStart: wordCursor,
                    itemWordOffsets: []
                ))
                wordCursor += words.count
                i += 1
            } else {
                // Gather consecutive non-list lines into one paragraph segment.
                var paraWords: [String] = []
                while i < rawLines.count
                    && rawLines[i].listKind == nil
                    && rawLines[i].headingLevel == nil
                    && rawLines[i].insight == nil
                    && (paraWords.isEmpty || !rawLines[i].startsNewBlock) {
                    paraWords.append(contentsOf: tokenize(rawLines[i].content))
                    i += 1
                }
                result.append(ResponseSegment(
                    id: result.count,
                    kind: .paragraph,
                    words: paraWords,
                    wordStart: wordCursor,
                    itemWordOffsets: []
                ))
                wordCursor += paraWords.count
            }
        }

        return result
    }

    static func markdownHeading(from line: String) -> (level: Int, text: String)? {
        if line.hasPrefix("### ") {
            return (3, String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces))
        }
        if line.hasPrefix("## ") {
            return (2, String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces))
        }
        if line.hasPrefix("# ") {
            return (1, String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
        }
        if line.hasPrefix("**"), line.hasSuffix("**"), line.count > 4 {
            return (1, String(line.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces))
        }
        if line.hasPrefix("*"), line.hasSuffix("*"), line.count > 2 {
            return (2, String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    /// Tokenises a single line into words (and markdown links as single tokens).
    static func tokenize(_ text: String) -> [String] {
        return ResponseRegex.tokenizer.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .map { String(text[Range($0.range, in: text)!]) }
    }

    static func insightLinkSequenceByWordStart(
        in segments: [ResponseSegment]
    ) -> [Int: Int] {
        var sequenceByWordStart: [Int: Int] = [:]
        var sequence = 0

        for segment in segments {
            for (offset, word) in segment.words.enumerated()
            where Self.insightLink(from: word) != nil {
                sequenceByWordStart[segment.wordStart + offset] = sequence
                sequence += 1
            }
        }

        return sequenceByWordStart
    }

    static func insightLink(from word: String) -> ParsedInsightLink? {
        ParsedInsightLink(token: word)
    }

}
