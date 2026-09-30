//
//  SummaArticleIndex.swift
//  Aquinas-iOS
//

import Foundation

/// Finds Summa Theologica articles in the chunked corpus and assembles Aquinas's own answer.
///
/// The corpus was chunked from a paginated edition with no knowledge of the Summa's structure. An
/// article runs: the question ("Whether…?"), objections Aquinas will go on to answer, "On the
/// contrary", his own answer ("I answer that…"), then replies to the objections. Chunks cut across
/// all of these, and each page's running header ("1521 Article. 5 - Whether…") is a chunk of its
/// own. Semantic search therefore returned headers with no content, or objections without the
/// answer, and the model reported an objection as Aquinas's teaching (held-B1 reversed his
/// position on a mistaken conscience; held-C4 received three objections and no answer).
nonisolated struct SummaArticleIndex: Sendable {
    static let sourceID = "summa-theologica"

    /// Aquinas's answer to one article, ready to hand to the model as a single reference.
    struct Evidence: Equatable, Sendable {
        /// Corpus index of the chunk that opens the article.
        let articleStart: Int
        /// "Whether the will is evil when it is at variance with erring reason?"
        let question: String
        /// From "I answer that" up to the first reply, shortened to the character budget.
        let answer: String
        /// The sentence that closes the answer, when it states the conclusion ("Hence…", "We must
        /// therefore conclude…"). An answer often opens with a view Aquinas goes on to reject, so
        /// the conclusion is given to the model first.
        let conclusion: String?
        /// Corpus index of the chunk where the answer begins, for citations.
        let answerIndex: Int
    }

    /// Corpus indices of the chunks that open an article, ascending.
    private let starts: [Int]
    /// One past the last Summa chunk.
    private let sourceEnd: Int

    /// `indices` are the corpus positions of the Summa's chunks, in reading order.
    init(passages: [LibraryPassage], indices: [Int]) {
        starts = indices.filter { Self.opensArticle(passages[$0].text) }
        sourceEnd = (indices.last ?? -1) + 1
    }

    var articleCount: Int { starts.count }

    /// The chunk that opens the article containing `index`, or `nil` for front matter, indexes,
    /// and anything outside the Summa.
    func articleStart(containing index: Int, in passages: [LibraryPassage]) -> Int? {
        guard index < sourceEnd, let first = starts.first else { return nil }
        // A page header printed just above an article belongs to that article, not to the one
        // ending on the previous page.
        if Self.isHeadingOnly(passages[index].text),
           let next = starts.first(where: { $0 > index }),
           next == index + 1 {
            return next
        }
        guard index >= first else { return nil }
        var low = 0
        var high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= index { low = middle } else { high = middle - 1 }
        }
        return starts[low]
    }

    /// The chunk that opens the article whose question contains `phrase`. A question's wording
    /// also appears in the list of articles that heads each Summa question, which sits at the end
    /// of the previous article, so a plain text search lands one article early.
    func articleStart(questionContaining phrase: String, in passages: [LibraryPassage]) -> Int? {
        let phrase = phrase.lowercased()
        return starts.first { Self.question(in: passages[$0].text).lowercased().contains(phrase) }
    }

    /// The article that follows the one opening at `start`, when its question shares a subject
    /// word with it. Adjacent articles often carry the qualification that completes the first:
    /// I–II q.19 a.5 (an erring conscience binds) with a.6 (but error doesn't always excuse), or
    /// II–II q.64 a.2 (killing sinners) with a.3 (only by public authority). The questions must
    /// share two subject words.
    func relatedNextArticle(after start: Int, in passages: [LibraryPassage]) -> Int? {
        guard let position = starts.firstIndex(of: start), position + 1 < starts.count else {
            return nil
        }
        let next = starts[position + 1]
        let subject = Self.subjectWords(in: Self.question(in: passages[start].text))
        let nextSubject = Self.subjectWords(in: Self.question(in: passages[next].text))
        // One shared word is too weak: "Whether conscience be a power?" and "Whether the appetite
        // is a special power of the soul?" share only "power".
        return subject.intersection(nextSubject).count >= 2 ? next : nil
    }

    /// Aquinas's answer for the article opening at `start`, or `nil` when the article has no
    /// recognizable "I answer that".
    func evidence(
        forArticleAt start: Int,
        in passages: [LibraryPassage],
        characterBudget: Int
    ) -> Evidence? {
        guard let position = starts.firstIndex(of: start) else { return nil }
        let end = position + 1 < starts.count ? starts[position + 1] : sourceEnd
        // Join the article first: a chunk boundary can fall inside "I answer that" itself.
        var article = ""
        var chunkOffsets: [(offset: Int, index: Int)] = []
        for index in start..<end {
            let text = Self.cleaned(passages[index].text)
            guard !text.isEmpty else { continue }
            if !article.isEmpty { article += " " }
            chunkOffsets.append((article.count, index))
            article += text
        }
        guard let marker = article.range(of: "I answer that") else { return nil }
        let markerOffset = article.distance(from: article.startIndex, to: marker.lowerBound)
        var answer = article[marker.lowerBound...]
        if let reply = answer.range(of: "Reply to Objection 1") {
            answer = answer[..<reply.lowerBound]
        }
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > "I answer that".count + 20,
              let answerIndex = chunkOffsets.last(where: { $0.offset <= markerOffset })?.index
        else { return nil }
        let conclusion = Self.conclusion(of: trimmed)
        return Evidence(
            articleStart: start,
            question: Self.question(in: passages[start].text),
            answer: Self.shortened(trimmed, to: characterBudget - (conclusion?.count ?? 0)),
            conclusion: conclusion,
            answerIndex: answerIndex
        )
    }

    // MARK: - Text handling

    /// A page's running header: "1521 Article. 5 - Whether the will is evil when it is at…".
    private static let pageHeader = try! NSRegularExpression(
        pattern: #"\b\d{1,5}\s+(?:Article|Question)\.\s*\d+\s*-\s*[^?…]{0,300}[?…]\s*"#
    )
    /// A word the edition broke across lines: "ac- cord".
    private static let brokenWord = try! NSRegularExpression(pattern: #"(?<=\p{Ll})- (?=\p{Ll})"#)

    /// Chunk text without page headers or line-break hyphens.
    static func cleaned(_ text: String) -> String {
        var cleaned = text
        for pattern in [pageHeader, brokenWord] {
            cleaned = pattern.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether a chunk is only a page header, with no source text of its own.
    static func isHeadingOnly(_ text: String) -> Bool {
        cleaned(text).count < 12
    }

    private static func opensArticle(_ text: String) -> Bool {
        let body = cleaned(text)
        guard body.hasPrefix("Whether "),
              let end = body.firstIndex(of: "?"),
              body.distance(from: body.startIndex, to: end) < 400
        else { return false }
        return body[end...].dropFirst().drop(while: \.isWhitespace).hasPrefix("Objection 1")
    }

    private static func question(in text: String) -> String {
        let body = cleaned(text)
        guard let end = body.firstIndex(of: "?") else { return body }
        return String(body[...end])
    }

    /// Words every Summa question shares, which say nothing about its subject.
    private static let questionBoilerplate: Set<String> = [
        "whether", "lawful", "there", "their", "these", "those", "which", "should", "would",
        "could", "being", "other", "every", "always", "anything", "something", "thing", "things",
        "only", "also", "than", "that", "this", "with", "from", "when", "what", "into", "such",
        "some", "more", "same", "have", "does", "will", "must", "been", "were", "them", "they"
    ]

    private static func subjectWords(in question: String) -> Set<String> {
        Set(
            question.lowercased()
                .split(whereSeparator: { !$0.isLetter })
                .map(String.init)
                .filter { $0.count >= 4 && !questionBoilerplate.contains($0) }
                // "sinners" and "sinned" name one subject.
                .map { String($0.prefix(5)) }
        )
    }

    /// A closing sentence that states the conclusion: it opens with "Hence", "We must therefore
    /// conclude" and the like, and runs to the end of the answer.
    private static let closingConclusion = try! NSRegularExpression(
        pattern: #"(?:^|[.;:!?]["”’']?\s+)((?:Hence|Therefore|Wherefore|Consequently|Accordingly|Thus|So then|We must therefore|It follows|It is therefore|It is evident|It is clear|It is manifest)\b[^.]{20,400}\.?)\s*$"#
    )

    /// The answer's final sentence, when it reads as a conclusion and is short enough to quote.
    static func conclusion(of answer: String) -> String? {
        let body = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = closingConclusion.firstMatch(
                in: body,
                range: NSRange(body.startIndex..., in: body)
              ),
              let range = Range(match.range(at: 1), in: body)
        else { return nil }
        let sentence = body[range].trimmingCharacters(in: .whitespaces)
        return sentence.hasSuffix(".") ? sentence : sentence + "."
    }

    /// Keeps the opening and the close of a long answer. A scholastic answer states its
    /// distinction first and its conclusion last, so the middle is what can be dropped.
    static func shortened(_ answer: String, to budget: Int) -> String {
        guard answer.count > budget, budget > 200 else { return answer }
        let headBudget = budget * 2 / 5
        let tailBudget = budget - headBudget
        let head = sentencePrefix(of: answer, atMost: headBudget)
        let tail = sentenceSuffix(of: answer, atMost: tailBudget)
        return "\(head) […] \(tail)"
    }

    private static func sentencePrefix(of text: String, atMost budget: Int) -> String {
        let prefix = text.prefix(budget)
        guard let stop = prefix.lastIndex(where: { $0 == "." || $0 == ";" || $0 == ":" }) else {
            return String(prefix)
        }
        return String(prefix[...stop])
    }

    private static func sentenceSuffix(of text: String, atMost budget: Int) -> String {
        let suffix = text.suffix(budget)
        guard let stop = suffix.firstIndex(where: { $0 == "." || $0 == ";" }),
              suffix.index(after: stop) < suffix.endIndex
        else { return String(suffix) }
        return suffix[suffix.index(after: stop)...].trimmingCharacters(in: .whitespaces)
    }
}
