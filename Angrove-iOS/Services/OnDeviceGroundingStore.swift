//
//  OnDeviceGroundingStore.swift
//  Angrove-iOS
//

import Accelerate
import Foundation

/// A passage retrieved from the local grounding corpus. Mirrors the
/// backend's `GroundingPassage` (see Aquinas_Backend/grounding_retrieval.py)
/// so the local and backend prompt-construction paths can share the same
/// shape and wording.
nonisolated struct GroundingPassage: Sendable {
    let text: String
    let title: String
    let sourceID: String
    let distance: Float
    /// The passage's position in its source, so a citation can open the Library reader there.
    var chunkIndex: Int? = nil
    /// The passage's position in the whole corpus.
    var corpusIndex: Int? = nil
}

private typealias PassageRecord = LibraryPassage

/// Loads the pre-embedded grounding corpus once (a flat float32 embeddings
/// file plus a parallel-indexed JSON metadata file, exported from the
/// backend's Chroma collection — see Aquinas_Backend/grounding_retrieval.py
/// for the matching embedding space) and serves nearest-passage queries with
/// a vectorized linear scan. At ~41k chunks this is comfortably faster than
/// generation itself, so no on-device approximate-NN index is needed.
nonisolated final class OnDeviceGroundingStore: Sendable {
    private let embeddingDimension = 384
    private let passages: [PassageRecord]
    private let embeddings: Data
    private let sourceIndices: [String: [Int]]
    /// "JHN14" -> the passage range covering that chapter, built once from the
    /// corpus's own leading `[JHN14]` locator tags. Lets an explicit citation
    /// be resolved as a lookup key instead of a semantic query.
    private let chapterRanges: [String: Range<Int>]
    private let summaArticles: SummaArticleIndex

    /// Cosine distance on MiniLM embeddings is a ranking signal, not a
    /// calibrated probability (see MODEL-INTEGRATION.md), so this is a
    /// measured separation point rather than a confidence level.
    ///
    /// The former value of 1.0 admitted any non-negative similarity, which in
    /// practice screened nothing: "what did the Council of Nicaea decide about
    /// the Son?" passed five straight Livy/Herodotus/Plutarch passages (0.55,
    /// matching "council" and *Nicaea the Greek city*) into the prompt as
    /// grounding. Scored against the bundled corpus, clearly relevant
    /// questions land at 0.64-0.83 similarity while clearly irrelevant ones
    /// top out at 0.60, so 0.38 distance (0.62 similarity) separates them.
    /// Retrieving nothing is the safe outcome here: generation then proceeds
    /// ungrounded, which is strictly better than grounding it in Roman
    /// history.
    ///
    /// The value is 0.45, chosen by sweeping it against the 56-case set in
    /// `Aquinas_Backend/evaluation/evaluate_retrieval.py` rather than by
    /// eyeballing a handful of queries. An earlier 0.38 was calibrated only on
    /// doctrinal questions, where the Summa's "Whether X..." phrasing closely
    /// mirrors the question, and it silently discarded ordinary narrative
    /// scripture -- the Lord's Prayer, the Good Samaritan and the prodigal son
    /// all returned nothing despite being in the corpus (61% overall, 17
    /// no-coverage failures). Loosening to 0.45 distance recovers them (75%,
    /// 7 no-coverage) while still screening every out-of-scope question in the
    /// set. Going further to 0.50 scores higher overall but begins grounding
    /// "how do I bake sourdough bread", which is the failure this floor
    /// exists to prevent, so it is not the maximum of the score curve.
    private let defaultMaxDistance: Float = 0.45

    init(embeddingsURL: URL, passagesURL: URL) throws {
        let corpus = try BundledPassageCorpus.load(from: passagesURL)
        self.passages = corpus.passages
        self.embeddings = try Data(contentsOf: embeddingsURL, options: .alwaysMapped)

        let expectedBytes = passages.count * embeddingDimension * MemoryLayout<Float>.size
        guard embeddings.count == expectedBytes else {
            throw OnDeviceGroundingStoreError.corpusMismatch
        }
        self.chapterRanges = Self.indexChapters(in: passages)
        self.sourceIndices = corpus.indicesBySource
        self.summaArticles = SummaArticleIndex(
            passages: corpus.passages,
            indices: corpus.indicesBySource[SummaArticleIndex.sourceID] ?? []
        )
    }

    /// The Summa article a retrieved passage belongs to, as the corpus index of its opening chunk.
    func summaArticleStart(containing passage: GroundingPassage) -> Int? {
        guard passage.sourceID == SummaArticleIndex.sourceID,
              let index = passage.corpusIndex
        else { return nil }
        return summaArticles.articleStart(containing: index, in: passages)
    }

    /// The opening chunk of the Summa article whose question contains every one of `phrases`.
    func summaArticleOpening(questionContaining phrases: Set<String>) -> GroundingPassage? {
        guard let first = phrases.sorted().first,
              let start = summaArticles.articleStart(questionContaining: first, in: passages),
              phrases.allSatisfy({ passages[start].text.localizedCaseInsensitiveContains($0) })
        else { return nil }
        let record = passages[start]
        return GroundingPassage(
            text: record.text,
            title: record.title,
            sourceID: record.sourceId,
            distance: 0,
            chunkIndex: record.chunkIndex,
            corpusIndex: start
        )
    }

    /// The opening chunk of the Summa article that defines `term`, if there is one.
    func summaDefiningArticleOpening(for term: String) -> GroundingPassage? {
        guard let start = summaArticles.definingArticleStart(for: term, in: passages) else {
            return nil
        }
        let record = passages[start]
        return GroundingPassage(
            text: record.text,
            title: record.title,
            sourceID: record.sourceId,
            distance: 0,
            chunkIndex: record.chunkIndex,
            corpusIndex: start
        )
    }

    /// The following article, when its question shares a subject with the one at `start`.
    func relatedNextSummaArticle(after start: Int) -> Int? {
        summaArticles.relatedNextArticle(after: start, in: passages)
    }

    /// Aquinas's own answer to the article opening at `start`, as one passage. `nil` when the
    /// article has no recognizable answer, in which case the caller keeps the raw chunk.
    func summaArticleAnswer(
        at start: Int,
        distance: Float,
        characterBudget: Int
    ) -> GroundingPassage? {
        guard let evidence = summaArticles.evidence(
            forArticleAt: start,
            in: passages,
            characterBudget: characterBudget
        ) else { return nil }
        let record = passages[evidence.answerIndex]
        return GroundingPassage(
            text: [
                "Question: \(evidence.question)",
                evidence.conclusion.map { "Aquinas's conclusion: \($0)" },
                "Aquinas's own answer: \(evidence.answer)"
            ].compactMap { $0 }.joined(separator: "\n"),
            title: record.title,
            sourceID: record.sourceId,
            distance: distance,
            chunkIndex: record.chunkIndex,
            corpusIndex: evidence.answerIndex
        )
    }

    /// Whether a passage carries no source text of its own: a page header, or a fragment left by
    /// a page break ("salva-").
    static func isContentless(_ passage: GroundingPassage) -> Bool {
        if passage.sourceID == SummaArticleIndex.sourceID {
            return SummaArticleIndex.cleaned(passage.text).count < 40
        }
        return passage.text.trimmingCharacters(in: .whitespacesAndNewlines).count < 40
    }

    /// Chapters are chunked across several passages, but only the first chunk
    /// of each carries the `[JHN14]` tag, so a chapter runs from its tagged
    /// chunk up to the next tagged chunk in the same source.
    private static func indexChapters(in passages: [PassageRecord]) -> [String: Range<Int>] {
        var starts: [(key: String, index: Int)] = []
        for (index, passage) in passages.enumerated() {
            guard let key = chapterKey(inLeadingTagOf: passage.text) else { continue }
            starts.append((key, index))
        }
        var ranges: [String: Range<Int>] = [:]
        for (offset, entry) in starts.enumerated() {
            let sourceID = passages[entry.index].sourceId
            var end = entry.index + 1
            while end < passages.count, passages[end].sourceId == sourceID {
                if offset + 1 < starts.count, starts[offset + 1].index == end { break }
                // Book-level tags like `[ROM]` and trailing front/back matter are not chapter
                // starts, so they would otherwise be swallowed into the preceding chapter.
                if hasLeadingTag(passages[end].text) { break }
                end += 1
            }
            // Later duplicates of a tag (the corpus carries a handful) keep the
            // first occurrence, which is the canonical chapter opening.
            if ranges[entry.key] == nil {
                ranges[entry.key] = entry.index..<end
            }
        }
        return ranges
    }

    /// Whether a passage opens with any bracketed corpus tag, chapter-level
    /// (`[JHN14]`) or book-level (`[ROM]`).
    private static func hasLeadingTag(_ text: String) -> Bool {
        let trimmed = text.drop { $0 == "\u{FEFF}" || $0.isWhitespace }
        guard trimmed.first == "[",
              let close = trimmed.firstIndex(of: "]")
        else { return false }
        let body = trimmed[trimmed.index(after: trimmed.startIndex)..<close]
        return !body.isEmpty
            && body.count <= 8
            && body.allSatisfy { $0.isUppercase || $0.isNumber }
    }

    /// Reads a leading `[JHN14]` tag: a three-character USFM book code followed
    /// by the chapter number.
    private static func chapterKey(inLeadingTagOf text: String) -> String? {
        let trimmed = text.drop { $0 == "\u{FEFF}" || $0.isWhitespace }
        guard trimmed.first == "[",
              let close = trimmed.firstIndex(of: "]")
        else { return nil }
        let body = trimmed[trimmed.index(after: trimmed.startIndex)..<close]
        guard body.count > 3 else { return nil }
        let code = body.prefix(3)
        let chapter = body.dropFirst(3)
        guard code.allSatisfy({ $0.isUppercase || $0.isNumber }),
              chapter.allSatisfy(\.isNumber),
              let number = Int(chapter)
        else { return nil }
        return "\(code)\(number)"
    }

    /// The passages making up an explicitly cited chapter, in reading order. A named passage may
    /// supply a literal source-text anchor, in which case reading begins at that chunk instead of
    /// at the chapter opening. Returns an empty array when the corpus does not carry the chapter
    /// or a claimed anchor is absent, so a stale pointer cannot silently supply the wrong text.
    func chapter(for citation: ScriptureCitation, limit: Int) -> [GroundingPassage] {
        guard limit > 0,
              let range = chapterRanges["\(citation.bookCode)\(citation.chapter)"]
        else { return [] }
        let start: Int
        if let anchorText = citation.anchorText {
            guard let anchor = range.first(where: {
                passages[$0].text.localizedCaseInsensitiveContains(anchorText)
            }) else { return [] }
            start = anchor
        } else {
            start = range.lowerBound
        }
        return passages.indices[start..<range.upperBound].prefix(limit).map { index in
            let record = passages[index]
            return GroundingPassage(
                text: record.text,
                title: "\(citation.displayName) — \(record.title)",
                sourceID: record.sourceId,
                // An exact citation match is a lookup hit, not a ranked one.
                distance: 0,
                chunkIndex: record.chunkIndex
            )
        }
    }

    var passageCount: Int { passages.count }

    /// Returns a source-local run beginning at a known section heading or formula. Authority
    /// pointers identify the first passage exactly; the following chunks supply the explanation
    /// that a short heading alone cannot carry. This never crosses into another source.
    func section(
        sourceIDs: Set<String>,
        requiredTerms: Set<String>,
        limit: Int
    ) -> [GroundingPassage] {
        guard limit > 0, !requiredTerms.isEmpty else { return [] }
        let indices = sourceIDs.sorted().flatMap { sourceIndices[$0] ?? [] }
        guard let anchorOffset = indices.firstIndex(where: { index in
            requiredTerms.allSatisfy { passages[index].text.localizedCaseInsensitiveContains($0) }
        }) else { return [] }

        let anchorSourceID = passages[indices[anchorOffset]].sourceId
        return indices[anchorOffset...]
            .prefix { passages[$0].sourceId == anchorSourceID }
            .prefix(limit)
            .map { index in
                let record = passages[index]
                return GroundingPassage(
                    text: record.text,
                    title: record.title,
                    sourceID: record.sourceId,
                    distance: 0,
                    chunkIndex: record.chunkIndex,
                    corpusIndex: index
                )
            }
    }

    func retrieve(
        queryEmbedding: [Float],
        k: Int = 4,
        maxDistance: Float? = nil,
        sourceIDs: Set<String>? = nil,
        prioritizingTerms: Set<String> = [],
        requiredTerms: Set<String> = []
    ) -> [GroundingPassage] {
        guard queryEmbedding.count == embeddingDimension, !passages.isEmpty else {
            return []
        }
        let threshold = maxDistance ?? defaultMaxDistance
        guard k > 0 else { return [] }
        struct Ranked {
            let index: Int
            let distance: Float
            let matchedTerms: Int
        }
        // Insertion keeps only k results and preserves encounter order for exact ties.
        var ranked: [Ranked] = []
        ranked.reserveCapacity(min(k, passages.count))
        let permitsNamedSourceLookup = sourceIDs != nil
        PerformanceTrace.measure("Exact Passage Ranking") {
            embeddings.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                guard let base = raw.bindMemory(to: Float.self).baseAddress else { return }
                queryEmbedding.withUnsafeBufferPointer { query in
                    guard let queryBase = query.baseAddress else { return }
                    func consider(_ index: Int) {
                        let record = passages[index]
                        guard requiredTerms.allSatisfy({ record.text.localizedCaseInsensitiveContains($0) }) else { return }
                        var dot: Float = 0
                        vDSP_dotpr(queryBase, 1, base + index * embeddingDimension, 1, &dot, vDSP_Length(embeddingDimension))
                        let distance = 1 - dot
                        let matched = prioritizingTerms.reduce(0) { $0 + (record.text.localizedCaseInsensitiveContains($1) ? 1 : 0) }
                        guard distance <= threshold || (permitsNamedSourceLookup && (prioritizingTerms.isEmpty || matched > 0)) else { return }
                        let entry = Ranked(index: index, distance: distance, matchedTerms: matched)
                        let slot = ranked.firstIndex { matched > $0.matchedTerms || (matched == $0.matchedTerms && distance < $0.distance) } ?? ranked.count
                        guard slot < k else { return }
                        ranked.insert(entry, at: slot)
                        if ranked.count > k { ranked.removeLast() }
                    }
                    if let sourceIDs {
                        for source in sourceIDs { for index in sourceIndices[source] ?? [] { consider(index) } }
                    } else {
                        for index in passages.indices { consider(index) }
                    }
                }
            }
        }

        return ranked.map { entry in
            let record = passages[entry.index]
            return GroundingPassage(
                text: record.text,
                title: record.title,
                sourceID: record.sourceId,
                distance: entry.distance,
                chunkIndex: record.chunkIndex,
                corpusIndex: entry.index
            )
        }
    }
}

enum OnDeviceGroundingStoreError: LocalizedError {
    case corpusMismatch

    var errorDescription: String? {
        "The bundled grounding corpus's embeddings and passage metadata are out of sync."
    }
}
