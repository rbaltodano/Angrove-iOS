import Foundation

/// Turns a plain word of a completed response into an annotated Insight term.
///
/// Annotation normally comes from the model's key terms (`ModelResponse.annotatedText`). Define
/// lets the reader pick a word the model did not annotate: the word is wrapped in the same
/// `[term](aq://slug)` markup, so it renders, loads, and opens exactly like an annotated term.
enum DefinedTermMarkup {
    /// Where the pressed token sits, as the response view that rendered it knows it.
    enum Location: Equatable {
        /// Index among the response's displayed word tokens, in reading order, not counting
        /// inline Insight cards.
        case displayedToken(Int)
        /// Index among the tokens of one block's source text (a paragraph, heading, or list item).
        case sourceToken(source: String, index: Int)
    }

    struct Result: Equatable {
        /// The response text with the term annotated.
        let text: String
        let term: String
    }

    /// The term a token names, without surrounding punctuation, emphasis, or a possessive.
    /// Nil when the token has no word in it or is already a link.
    static func term(in token: String) -> String? {
        termRange(in: token).map { String(token[$0]) }
    }

    /// Annotates the pressed token. When `location` no longer matches the text, the first
    /// displayed occurrence of the same token is annotated instead.
    static func defining(token: String, at location: Location, in text: String) -> Result? {
        guard let termRange = termRange(in: token) else { return nil }
        let term = String(token[termRange])
        let source = text as NSString
        let tokenRange = resolvedRange(of: token, at: location, in: text)
            ?? displayedTokenRanges(in: text).first { source.substring(with: $0) == token }
        guard let tokenRange else { return nil }

        let termOffset = token[..<termRange.lowerBound].utf16.count
        let range = NSRange(location: tokenRange.location + termOffset, length: term.utf16.count)
        return Result(
            text: source.replacingCharacters(in: range, with: "[\(term)](aq://\(slug(for: term)))"),
            term: term
        )
    }

    /// The response's word tokens in reading order, split exactly as the response views split
    /// them: list markers and heading prefixes are not tokens, and inline Insight cards are skipped.
    static func displayedTokenRanges(in text: String) -> [NSRange] {
        let source = text as NSString
        var ranges: [NSRange] = []
        var lineStart = 0
        for line in text.components(separatedBy: "\n") {
            let lineLength = (line as NSString).length
            defer { lineStart += lineLength + 1 }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, InlineInsightMarkup.insight(from: trimmed) == nil else { continue }

            let leading = line.prefix { $0.unicodeScalars.allSatisfy(CharacterSet.whitespaces.contains) }
            let content = contentRange(inTrimmedLine: trimmed)
            let absolute = NSRange(
                location: lineStart + leading.utf16.count + content.location,
                length: content.length
            )
            ranges += ResponseRegex.tokenizer.matches(in: source as String, range: absolute).map(\.range)
        }
        return ranges
    }

    // MARK: - Private

    private static func resolvedRange(of token: String, at location: Location, in text: String) -> NSRange? {
        let source = text as NSString
        let candidate: NSRange?
        switch location {
        case .displayedToken(let index):
            let ranges = displayedTokenRanges(in: text)
            candidate = ranges.indices.contains(index) ? ranges[index] : nil
        case .sourceToken(let blockSource, let index):
            let blockRange = source.range(of: blockSource)
            guard blockRange.location != NSNotFound else { return nil }
            let ranges = ResponseRegex.tokenizer.matches(in: text, range: blockRange).map(\.range)
            candidate = ranges.indices.contains(index) ? ranges[index] : nil
        }
        guard let candidate, source.substring(with: candidate) == token else { return nil }
        return candidate
    }

    /// The part of a line the response views tokenize, mirroring `ResponseParser.parseSegments`.
    private static func contentRange(inTrimmedLine trimmed: String) -> NSRange {
        let whole = NSRange(location: 0, length: (trimmed as NSString).length)
        for listLine in [ResponseRegex.orderedListLine, ResponseRegex.unorderedListLine] {
            if let match = listLine.firstMatch(in: trimmed, range: whole) {
                return match.range(at: 1)
            }
        }
        let (prefix, suffix): (Int, Int) = {
            if trimmed.hasPrefix("### ") { return (4, 0) }
            if trimmed.hasPrefix("## ") { return (3, 0) }
            if trimmed.hasPrefix("# ") { return (2, 0) }
            if trimmed.hasPrefix("**"), trimmed.hasSuffix("**"), trimmed.count > 4 { return (2, 2) }
            if trimmed.hasPrefix("*"), trimmed.hasSuffix("*"), trimmed.count > 2 { return (1, 1) }
            return (0, 0)
        }()
        return NSRange(location: prefix, length: whole.length - prefix - suffix)
    }

    private static func termRange(in token: String) -> Range<String.Index>? {
        guard !token.contains("](") else { return nil }
        func isWordCharacter(_ character: Character) -> Bool {
            character.isLetter || character.isNumber
        }
        guard let first = token.firstIndex(where: isWordCharacter),
              let last = token.lastIndex(where: isWordCharacter) else { return nil }
        var range = first..<token.index(after: last)

        // "virtue—the" is one token; the longer side is the likelier term.
        let dashes: Set<Character> = ["—", "–"]
        if token[range].contains(where: dashes.contains) {
            let parts = token[range].split(whereSeparator: dashes.contains)
            guard let longest = parts.max(by: { $0.count < $1.count }),
                  let start = longest.firstIndex(where: isWordCharacter),
                  let end = longest.lastIndex(where: isWordCharacter) else { return nil }
            range = start..<longest.index(after: end)
        }
        for possessive in ["'s", "’s"] where token[range].count > 2 && token[range].hasSuffix(possessive) {
            range = range.lowerBound..<token.index(range.upperBound, offsetBy: -2)
        }

        let term = token[range]
        guard term.contains(where: \.isLetter),
              !term.contains(where: { "[]()".contains($0) }) else { return nil }
        return range
    }

    private static func slug(for term: String) -> String {
        let slug = term.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map { $0.filter { $0.isLetter || $0.isNumber || $0 == "-" } }
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return slug.isEmpty ? "term" : slug
    }
}
