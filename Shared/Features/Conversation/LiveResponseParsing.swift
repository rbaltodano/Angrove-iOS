import Foundation

struct LiveResponseToken: Identifiable {
    struct Annotation {
        let title: String
        let url: URL
        let leadingPunctuation: String
        let trailingPunctuation: String
        let sequence: Int
    }

    /// Generated prose is append-only, so the visible word ordinal remains stable
    /// when annotation metadata is attached at completion.
    let id: Int
    let source: String
    let annotation: Annotation?
    /// Source chips take negative ids so inserting one at completion leaves every word's ordinal
    /// (and so its revealed state) unchanged.
    var citation: ParsedInsightLink? = nil
    /// Position among the source's raw tokens, which is how Define finds a plain word again.
    var rawIndex: Int = 0

    static func parse(
        _ source: String,
        annotationSequenceStart: Int
    ) -> [LiveResponseToken] {
        let rawTokens = ResponseRegex.tokenizer.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        )
        .map { String(source[Range($0.range, in: source)!]) }

        var result: [LiveResponseToken] = []
        var annotationSequence = annotationSequenceStart
        var citationCount = 0

        for (rawIndex, rawToken) in rawTokens.enumerated() {
            if let link = insightLink(from: rawToken), link.isCitation {
                citationCount += 1
                result.append(LiveResponseToken(
                    id: -citationCount,
                    source: rawToken,
                    annotation: nil,
                    citation: link
                ))
                continue
            }
            guard let link = insightLink(from: rawToken) else {
                result.append(
                    LiveResponseToken(
                        id: result.count - citationCount,
                        source: rawToken,
                        annotation: nil,
                        rawIndex: rawIndex
                    )
                )
                continue
            }

            let visibleWords = link.title.split(whereSeparator: \.isWhitespace)
            for (index, visibleWord) in visibleWords.enumerated() {
                result.append(
                    LiveResponseToken(
                        id: result.count - citationCount,
                        source: String(visibleWord),
                        annotation: Annotation(
                            title: link.title,
                            url: link.url,
                            leadingPunctuation: index == 0
                                ? link.leadingPunctuation
                                : "",
                            trailingPunctuation: index == visibleWords.count - 1
                                ? link.trailingPunctuation
                                : "",
                            sequence: annotationSequence
                        )
                    )
                )
            }
            annotationSequence += 1
        }

        return result
    }

    private static func insightLink(
        from token: String
    ) -> ParsedInsightLink? {
        ParsedInsightLink(token: token)
    }
}

struct LiveResponseBlock: Identifiable {
    enum Kind {
        case paragraph(String)
        case heading(level: Int, text: String)
        case orderedList([String])
        case unorderedList([String])
    }

    let id: Int
    let kind: Kind
    let annotationSequenceStart: Int

    var isParagraph: Bool {
        if case .paragraph = kind { return true }
        return false
    }

    static func parse(_ text: String) -> [LiveResponseBlock] {
        var blocks: [LiveResponseBlock] = []
        var paragraphLines: [String] = []
        var orderedItems: [String] = []
        var unorderedItems: [String] = []
        var nextAnnotationSequence = 0

        func appendBlock(_ kind: Kind) {
            blocks.append(
                LiveResponseBlock(
                    id: blocks.count,
                    kind: kind,
                    annotationSequenceStart: nextAnnotationSequence
                )
            )
            nextAnnotationSequence += insightCount(in: kind)
        }

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            appendBlock(.paragraph(paragraphLines.joined(separator: " ")))
            paragraphLines.removeAll(keepingCapacity: true)
        }

        func flushOrderedList() {
            guard !orderedItems.isEmpty else { return }
            appendBlock(.orderedList(orderedItems))
            orderedItems.removeAll(keepingCapacity: true)
        }

        func flushUnorderedList() {
            guard !unorderedItems.isEmpty else { return }
            appendBlock(.unorderedList(unorderedItems))
            unorderedItems.removeAll(keepingCapacity: true)
        }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // A blank Markdown line is a real block boundary. Flush now so the live formatter
            // and completed-response formatter both preserve paragraph separation instead of
            // collapsing the entire answer into one continuous flow.
            guard !trimmed.isEmpty else {
                flushParagraph()
                flushOrderedList()
                flushUnorderedList()
                continue
            }

            if let item = orderedListItem(from: trimmed) {
                flushParagraph()
                flushUnorderedList()
                orderedItems.append(item)
                continue
            }

            if let item = unorderedListItem(from: trimmed) {
                flushParagraph()
                flushOrderedList()
                unorderedItems.append(item)
                continue
            }

            flushOrderedList()
            flushUnorderedList()
            if let heading = heading(from: trimmed) {
                flushParagraph()
                appendBlock(.heading(level: heading.level, text: heading.text))
            } else {
                paragraphLines.append(trimmed)
            }
        }

        flushParagraph()
        flushOrderedList()
        flushUnorderedList()
        return blocks
    }

    private static let insightCountMemo = ParseMemo<Int>(countLimit: 512)

    static func insightCount(in source: String) -> Int {
        insightCountMemo.value(for: source) { uncachedInsightCount(in: source) }
    }

    private static func uncachedInsightCount(in source: String) -> Int {
        ResponseRegex.tokenizer.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        )
        .reduce(into: 0) { count, match in
            let token = String(source[Range(match.range, in: source)!])
            if let link = ParsedInsightLink(token: token), !link.isCitation {
                count += 1
            }
        }
    }

    private static func insightCount(in kind: Kind) -> Int {
        switch kind {
        case .paragraph(let source), .heading(_, let source):
            insightCount(in: source)
        case .orderedList(let items), .unorderedList(let items):
            items.reduce(0) { $0 + insightCount(in: $1) }
        }
    }

    private static func orderedListItem(from line: String) -> String? {
        guard let match = ResponseRegex.orderedListLine.firstMatch(
            in: line,
            range: NSRange(line.startIndex..., in: line)
        ),
        let itemRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[itemRange])
    }

    private static func unorderedListItem(from line: String) -> String? {
        guard let match = ResponseRegex.unorderedListLine.firstMatch(
            in: line,
            range: NSRange(line.startIndex..., in: line)
        ),
        let itemRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[itemRange])
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        if line.hasPrefix("### ") {
            return (3, String(line.dropFirst(4)))
        }
        if line.hasPrefix("## ") {
            return (2, String(line.dropFirst(3)))
        }
        if line.hasPrefix("# ") {
            return (1, String(line.dropFirst(2)))
        }
        if line.hasPrefix("**"), line.hasSuffix("**"), line.count > 4 {
            return (1, String(line.dropFirst(2).dropLast(2)))
        }
        if line.hasPrefix("*"), line.hasSuffix("*"), line.count > 2 {
            return (2, String(line.dropFirst().dropLast()))
        }
        return nil
    }
}
