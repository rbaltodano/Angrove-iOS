import Foundation

/// An inline source chip placed after a response sentence that quotes a retrieved corpus passage.
nonisolated struct ResponseCitation: Equatable, Sendable {
    let label: String
    let sourceID: String
    let chunkIndex: Int
    /// UTF-16 offset in the plain response text where the chip is inserted.
    let insertionOffset: Int
}

/// Persisted form of a citation chip inside the saved response string:
/// `[Label](aq-cite://source-id/chunk-index)`. It rides alongside the `aq://` Insight links so
/// saved conversations need no schema change, and it is stripped from any plain-text use.
nonisolated enum ResponseCitationMarkup {
    static let scheme = "aq-cite"

    private static let pattern = try! NSRegularExpression(
        pattern: #" ?\[[^\]]+\]\(aq-cite://[^)]+\)"#
    )

    static func markup(for citation: ResponseCitation) -> String {
        // Brackets and parentheses would end the Markdown link early.
        let label = citation.label.filter { !"[]()".contains($0) }
        return "[\(label)](\(scheme)://\(citation.sourceID)/\(citation.chunkIndex))"
    }

    static func target(from url: URL) -> (sourceID: String, chunkIndex: Int)? {
        guard url.scheme == scheme,
              let sourceID = url.host(),
              let chunkIndex = Int(url.lastPathComponent)
        else { return nil }
        return (sourceID, chunkIndex)
    }

    static func removing(from text: String) -> String {
        pattern.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: ""
        )
    }
}

/// Finds response sentences that quote a retrieved passage. This is deterministic text matching
/// rather than model-emitted markup: the on-device model is never trusted to produce citations,
/// so a chip appears only where the response demonstrably reproduces the passage's own words.
nonisolated enum ResponseCitationMatcher {
    /// Consecutive words a sentence must share with a passage to count as quoting it. Shorter
    /// runs match stock phrases ("the grace of God and the") rather than genuine quotation.
    static let minimumSharedRun = 7
    /// A span the response puts in quotation marks may be shorter, since marking it as a
    /// quotation is itself the claim of quoting.
    static let minimumQuotedWords = 4

    static func citations(
        in text: String,
        references: [AngroveGroundingReference],
        label: (_ sourceID: String, _ chunkIndex: Int) -> String?
    ) -> [ResponseCitation] {
        let passages: [(sourceID: String, chunkIndex: Int, words: String, runs: Set<String>)] =
            references.compactMap { reference in
                guard let sourceID = reference.sourceID, let chunkIndex = reference.chunkIndex else {
                    return nil
                }
                let words = normalizedWords(reference.facts)
                return (sourceID, chunkIndex, " \(words.joined(separator: " ")) ", runs(of: words))
            }
        guard !passages.isEmpty else { return [] }

        var matches: [(passage: Int, sentenceEnd: Int, breaksRun: Bool)] = []
        let nsText = text as NSString
        nsText.enumerateSubstrings(
            in: NSRange(location: 0, length: nsText.length),
            options: .bySentences
        ) { sentence, range, _, _ in
            guard let sentence else { return }
            let words = normalizedWords(sentence)
            let quoted = quotedSpans(in: sentence)
            var best: (index: Int, score: Int)?
            for (index, passage) in passages.enumerated() {
                var score = runs(of: words).intersection(passage.runs).count
                for quote in quoted where passage.words.contains(" \(quote) ") {
                    score += 100
                }
                if score > 0, score > best?.score ?? 0 {
                    best = (index, score)
                }
            }
            guard let best else { return }
            matches.append((
                best.index,
                insertionOffset(forSentence: sentence, at: range.location),
                sentence.contains("\n")
            ))
        }

        // A run of sentences quoting the same passage gets one chip, after the last of them.
        var citations: [ResponseCitation] = []
        for (offset, match) in matches.enumerated() {
            if offset + 1 < matches.count,
               matches[offset + 1].passage == match.passage,
               !match.breaksRun {
                continue
            }
            let passage = passages[match.passage]
            guard let text = label(passage.sourceID, passage.chunkIndex) else { continue }
            citations.append(ResponseCitation(
                label: text,
                sourceID: passage.sourceID,
                chunkIndex: passage.chunkIndex,
                insertionOffset: match.sentenceEnd
            ))
        }
        return citations
    }

    /// Places the chip before the sentence's final punctuation ("… God [chip]."), or after the
    /// sentence when it closes a quotation or emphasis, so the chip never lands inside either.
    private static func insertionOffset(forSentence sentence: String, at location: Int) -> Int {
        let trimmed = sentence.replacingOccurrences(
            of: #"\s+$"#, with: "", options: .regularExpression
        )
        let trailing = trimmed.reversed().prefix { ".!?;:,\"”’')*".contains($0) }
        let closesQuotation = trailing.contains { "\"”’')*".contains($0) }
        let end = location + (trimmed as NSString).length
        return closesQuotation ? end : end - String(trailing).utf16.count
    }

    private static func normalizedWords(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private static func runs(of words: [String]) -> Set<String> {
        guard words.count >= minimumSharedRun else { return [] }
        return Set((0...(words.count - minimumSharedRun)).map {
            words[$0..<($0 + minimumSharedRun)].joined(separator: " ")
        })
    }

    private static let quotation = try! NSRegularExpression(pattern: #"["“]([^"”]+)["”]"#)

    private static func quotedSpans(in sentence: String) -> [String] {
        quotation.matches(in: sentence, range: NSRange(sentence.startIndex..., in: sentence))
            .compactMap { Range($0.range(at: 1), in: sentence) }
            .map { normalizedWords(String(sentence[$0])) }
            .filter { $0.count >= minimumQuotedWords }
            .map { $0.joined(separator: " ") }
    }
}
