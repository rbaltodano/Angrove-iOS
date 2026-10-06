//
//  AngroveModel.swift
//  Angrove-iOS
//

import Foundation
import SwiftUI

// MARK: - Model Boundary

/// The single boundary between the app and "the model" — whatever text-generation engine is
/// answering conversations, defining terms, labeling subjects, blending concepts, and generating
/// Make Node children. Every generative call in the app funnels through here.
/// `LiteRTAngroveModel` is the live on-device model, composed by `AngroveApplicationRuntime`;
/// `UnavailableAngroveModel` stands in when no verified model is installed. `MockAngroveModel`
/// remains available for previews and tests only. See `MODEL-INTEGRATION.md` for the structured
/// output contract and `INSIGHT-TREE.md` §10 for the Insight Tree-specific seam inventory.
protocol AngroveModel {
    /// The response to the running conversation: plain prose plus the terms worth defining within
    /// it (see `ModelResponse`). This complete-response operation remains available as the
    /// compatibility and validation-repair fallback for the streaming overload below.
    func respond(to context: ConversationContext) async -> ModelResponse

    /// Streams user-facing progress while a response is generated, including the model's own
    /// native thought channel when `thinkingEnabled`.
    func respond(
        to context: ConversationContext,
        thinkingEnabled: Bool,
        onUpdate: @escaping (ModelResponseUpdate) -> Void
    ) async -> ModelResponse

    /// Names a conversation from its initial question after answer and tree processing finish.
    func conversationTitle(for initialQuestion: String) async throws -> String

    /// Produces hidden, durable context that can replace older turns in future requests.
    func compact(_ context: ConversationContext) async -> String

    /// A definition for a tapped highlighted term, generated as it relates to this conversation
    /// (not a dictionary lookup).
    func defineTerm(
        _ term: String,
        in context: ConversationContext
    ) async throws -> ConceptDefinition

    /// A dynamic definition scoped to one persisted conversation. Implementations can use the
    /// conversation id to reuse definitions already generated for the same response context.
    func defineTerm(
        _ term: String,
        in context: ConversationContext,
        conversationID: UUID?
    ) async throws -> ConceptDefinition

    /// Returns an already-generated contextual definition without asking the model to do work.
    /// A `nil` result means this conversation/source combination has not been defined yet.
    func cachedDefinition(
        for term: String,
        in context: ConversationContext,
        conversationID: UUID?
    ) async -> ConceptDefinition?

    /// The nearest useful broader 1–5 word concept organizing contextual Insight
    /// descriptions — used to name a Node Concept.
    func labelSubject(forTitles titles: [String]) async throws -> String

    /// Exact member titles are separate from descriptions so punctuation in either is harmless.
    func labelSubject(forTitles titles: [String], excludingInsightTitles: [String]) async throws -> String

    /// Extracts this turn's main subject (label + summary) to seed the on-device Insight Tree.
    /// `nil` means
    /// extraction genuinely failed. This always returns a candidate for every turn — whether it
    /// actually becomes a new Node Concept or attaches to an existing one is decided by the
    /// caller via embedding similarity against the Nodes already on the tree, not by this call;
    /// see `enqueueLocalInsightTreeSeedingTask`'s doc comment for why that judgment moved out of
    /// the model.
    func insightTreeSeedCandidate(
        question: String,
        response: String
    ) async throws -> (label: String, summary: String)?

    /// Candidate syntheses for mathematical vector-space selection by the Midpoint tool.
    func blendConceptCandidates(
        _ concepts: [ConceptDefinition],
        weights: [Double]
    ) async throws -> [ConceptDefinition]

    /// The 3 child Insights generated when `concept` is promoted into a Node Concept (Make Node).
    func generateChildren(for concept: ConceptDefinition) async throws -> [ConceptDefinition]

    /// Branch decomposes an Insight into exactly 2–6 fundamental subordinate Insights.
    func generateChildren(for concept: ConceptDefinition, count: Int) async throws -> [ConceptDefinition]

    /// Creates a once-daily home prompt from one recent conversation.
    func generateQuestionOfTheDay(
        from context: ConversationContext,
        conversationTitle: String,
        insights: [ConceptDefinition]
    ) async throws -> DailyQuestionDraft

    /// Judges whether a user's own message reads as an original synthesis, insight, or judgment
    /// worth resurfacing on Home as "Your Quote". The model never rewrites the message.
    func assessQuoteNotability(_ message: String) async throws -> QuoteNotability
}

struct QuoteNotability: Equatable {
    let isNotable: Bool
    /// One short reason when notable; `nil` otherwise.
    let reason: String?
}

enum AngroveModelActionError: Error {
    case unavailable
    case invalidRequest
    case invalidResponse
}

extension AngroveModel {
    func generateChildren(for concept: ConceptDefinition, count: Int) async throws -> [ConceptDefinition] {
        guard (2...6).contains(count) else { throw AngroveModelActionError.invalidRequest }
        guard count == 3 else { throw AngroveModelActionError.unavailable }
        return try await generateChildren(for: concept)
    }

    func conversationTitle(for initialQuestion: String) async throws -> String {
        throw AngroveModelActionError.unavailable
    }

    func labelSubject(forTitles titles: [String], excludingInsightTitles: [String]) async throws -> String {
        let label = try await labelSubject(forTitles: titles)
        try Task.checkCancellation()
        guard NodeConceptLabelPolicy.isValid(label, insightTitles: excludingInsightTitles) else {
            throw AngroveModelActionError.invalidResponse
        }
        return label
    }

    /// Only `LiteRTAngroveModel` implements this; every other model boundary (unavailable, mock)
    /// has no use for it, so this default keeps them at zero extra surface area.
    func insightTreeSeedCandidate(
        question: String,
        response: String
    ) async throws -> (label: String, summary: String)? {
        nil
    }

    func respond(
        to context: ConversationContext,
        thinkingEnabled: Bool,
        onUpdate: @escaping (ModelResponseUpdate) -> Void
    ) async -> ModelResponse {
        onUpdate(.generationStarted)
        let response = await respond(to: context)
        if thinkingEnabled && !response.thinkingSummary.isEmpty {
            onUpdate(.thinkingSummary(response.thinkingSummary))
        }
        onUpdate(.responseText(response.text))
        guard !thinkingEnabled else {
            return response
        }
        return ModelResponse(
            text: response.text,
            thinkingSummary: [],
            keyTerms: response.keyTerms,
            insight: response.insight,
            evidenceBasis: response.evidenceBasis
        )
    }

    func defineTerm(
        _ term: String,
        in context: ConversationContext,
        conversationID: UUID?
    ) async throws -> ConceptDefinition {
        try await defineTerm(term, in: context)
    }

    func cachedDefinition(
        for term: String,
        in context: ConversationContext,
        conversationID: UUID?
    ) async -> ConceptDefinition? {
        nil
    }

    /// Only `LiteRTAngroveModel` performs this check; other boundaries fail explicitly so no
    /// quote is ever flagged from preview or placeholder behavior.
    func assessQuoteNotability(_ message: String) async throws -> QuoteNotability {
        throw AngroveModelActionError.unavailable
    }

    func generateQuestionOfTheDay(
        from context: ConversationContext,
        conversationTitle: String,
        insights: [ConceptDefinition]
    ) async throws -> DailyQuestionDraft {
        let citedInsight = insights.first
        let subject = citedInsight?.word ?? conversationTitle
        return DailyQuestionDraft(
            question: "What implication of \(subject) would be most fruitful to explore next?",
            reasonForAsking: "It seemed like this was the next place your recent inquiry could open up.",
            citedInsightTitle: citedInsight?.word
        )
    }
}

enum ConversationPersonality: String, CaseIterable, Identifiable, Codable {
    case balanced
    case scholarly
    case socratic
    case fun

    var id: Self { self }

    /// The voice Angrove uses unless the person picks another. Scholarly since 2026-09-30: the
    /// fine-tuning dataset (Aquinas_Backend docs/Angrove-Voice-Dataset.md) is written in this
    /// voice and trained under this personality's instruction.
    static let `default`: ConversationPersonality = .scholarly

    var displayName: String {
        switch self {
        case .balanced:
            return "Balanced"
        case .scholarly:
            return "Scholarly"
        case .socratic:
            return "Socratic"
        case .fun:
            return "Fun Mode"
        }
    }

    var shortDescription: String {
        switch self {
        case .balanced:
            return "Warm, friendly, and ready for deeper dialogue."
        case .scholarly:
            return "Formal, rigorous, and grounded in the Thomistic tradition."
        case .socratic:
            return "Guides understanding through questions and careful dialogue."
        case .fun:
            return "Your personable, casual, slightly eccentric best friend."
        }
    }
}

/// The running conversation, passed to the model for any call that needs it as context.
struct ConversationContext {
    let compactedContext: String?
    let transcript: [ChatBlock]
    let personality: ConversationPersonality

    init(
        compactedContext: String? = nil,
        transcript: [ChatBlock] = [],
        personality: ConversationPersonality = .default
    ) {
        self.compactedContext = compactedContext
        self.transcript = transcript
        self.personality = personality
    }
}

/// The on-device LiteRT engine has one 4,096-token KV cache shared by the system prompt,
/// retrieved references, conversation history, the latest question, and the answer. Keep a
/// conservative reserve for everything except the visible conversation so a fluent answer does
/// not come at the cost of silently losing earlier turns.
enum AngroveContextBudget {
    static let totalTokenLimit = 4_096
    static let nonConversationReserve = 1_400
    static let automaticCompactionThreshold = 3_200

    static func estimatedTokenCount(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        // Four UTF-8 bytes per token is a deliberately conservative English-language estimate.
        // It also behaves more sensibly than word count for punctuation, markup, and long names.
        return Int(ceil(Double(text.utf8.count) / 4.0))
    }

    static func estimatedRequestTokenCount(for context: ConversationContext) -> Int {
        nonConversationReserve
            + estimatedTokenCount(in: context.compactedContext ?? "")
            + context.transcript.reduce(into: 0) { count, block in
                count += estimatedTokenCount(in: plainText(for: block))
            }
    }

    static func shouldCompact(_ context: ConversationContext) -> Bool {
        estimatedRequestTokenCount(for: context) >= automaticCompactionThreshold
            && historyAndLatestTurn(in: context) != nil
    }

    /// Separates the latest user request from the history that may be summarized. The latest
    /// request must remain verbatim; asking the model to answer a summary of it can change names,
    /// negation, or the actual question being asked.
    static func historyAndLatestTurn(
        in context: ConversationContext
    ) -> (history: ConversationContext, latestTurn: [ChatBlock])? {
        guard let latestUserIndex = context.transcript.lastIndex(where: { block in
            if case .user = block { return true }
            return false
        }), latestUserIndex > context.transcript.startIndex else {
            return nil
        }
        let historyBlocks = Array(context.transcript[..<latestUserIndex])
        guard !historyBlocks.isEmpty else { return nil }
        return (
            ConversationContext(
                compactedContext: context.compactedContext,
                transcript: historyBlocks,
                personality: context.personality
            ),
            Array(context.transcript[latestUserIndex...])
        )
    }

    private static func plainText(for block: ChatBlock) -> String {
        switch block {
        case .text(let text):
            InlineInsightMarkup.plainText(from: text)
        case .user(let text, let concept, _):
            [text, concept?.word, concept?.semanticDefinition]
                .compactMap { $0 }
                .joined(separator: " ")
        }
    }
}

/// Model-only markup for a user turn. Quoted Insights stay separate from the visible question in
/// application state, then become explicit context immediately before that question at generation.
enum ConversationPromptMarkup {
    static func userPrompt(
        question: String,
        quotedInsight: ConceptDefinition?
    ) -> String {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let quotedInsight else { return question }

        return """
        <insight_quote>
        <title>\(xmlEscaped(quotedInsight.word))</title>
        <definition>\(xmlEscaped(quotedInsight.semanticDefinition))</definition>
        </insight_quote>

        User question:
        \(question)
        """
    }

    private static func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

/// A term the model flagged as worth defining, with enough context to place its highlight
/// precisely. Mirrors the structured-output `key_terms` shape (MODEL-INTEGRATION.md §3) — the model
/// returns plain prose plus this structured list; application code, not the model, turns
/// validated terms into `aq://` highlight markup, since the model isn't trusted to produce
/// correct application URLs itself.
struct KeyTerm {
    let displayText: String
    let canonicalTerm: String
    let contextExcerpt: String

    init(displayText: String, canonicalTerm: String? = nil, contextExcerpt: String = "") {
        self.displayText = displayText
        self.canonicalTerm = canonicalTerm ?? displayText
        self.contextExcerpt = contextExcerpt
    }
}

/// One retrieved grounding passage, surfaced while generation is still running as a tappable
/// "Source" row. `passage` is the retrieved text itself, never a generated summary of it.
nonisolated struct GroundingSourceSummary: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let sourceName: String
    let passage: String
    /// The Library work this passage came from, so the row can show that work's genre icon.
    /// `nil` for curated notes and for answers saved before this was recorded.
    var sourceID: String? = nil

    /// The retrieved passage's position within the work. Optional for older saved answers
    /// and curated notes that do not refer to a corpus passage.
    var chunkIndex: Int? = nil

    /// Identifies the narrated retrieval lines that accompany these sources in a thinking
    /// summary, so the live loading UI can replace them with the expandable Source rows rather
    /// than reporting the same retrieval twice.
    static func isNarratedSourceLine(_ line: String) -> Bool {
        line.hasPrefix("Consulting ") || line.hasPrefix("Cross-checking against ")
    }
}

nonisolated extension GroundingSourceSummary {
    init(reference: AngroveGroundingReference) {
        self.init(
            id: reference.id,
            title: reference.title,
            sourceName: reference.sourceName,
            passage: reference.facts.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceID: reference.sourceID,
            chunkIndex: reference.chunkIndex
        )
    }
}

struct LibraryNavigationRequest: Equatable {
    let sourceTitle: String
    let sourceName: String
    /// Identifies the work directly when known, instead of by title.
    var sourceID: String? = nil
    /// Opens the reader at this passage when set; otherwise at the work's start.
    var chunkIndex: Int? = nil
    /// Distinguishes repeated taps on the same source, so each one still navigates.
    var id = UUID()
    /// Allows older saved sources without a chunk index to locate their original excerpt.
    var passage: String? = nil

    func resolvedChunkIndex(in passages: [LibraryPassage]) -> Int? {
        if let chunkIndex { return chunkIndex }
        guard let passage else { return nil }
        let excerpt = passage.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard excerpt.count >= 40 else { return nil }
        let matches = passages.filter { candidate in
            let text = candidate.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return text.count >= 40 && (text.hasPrefix(excerpt) || excerpt.hasPrefix(text))
        }
        // Repeated text must not send the reader to a guessed location.
        return matches.count == 1 ? matches.first?.chunkIndex : nil
    }
}

extension LibraryNavigationRequest {
    init(source: GroundingSourceSummary) {
        self.init(
            sourceTitle: source.title,
            sourceName: source.sourceName,
            sourceID: source.sourceID,
            chunkIndex: source.chunkIndex,
            passage: source.passage
        )
    }
}

enum ModelResponseUpdate {
    case generationStarted
    case thinkingSummary([String])
    /// The model's own reasoning so far (Gemma 4's native `thought` channel), accumulated.
    case thought(String)
    case groundingSources([GroundingSourceSummary])
    case responseText(String)
}

/// Explains the evidence basis for a response. `nil` is reserved for older saved answers and
/// recovery paths that do not report a basis.
nonisolated enum ResponseEvidenceBasis: String, Codable, Equatable {
    case corpusGrounded
    case generalKnowledge
    case sourceRequired

    var disclosureTitle: String {
        switch self {
        case .corpusGrounded:
            "Corpus Grounded"
        case .generalKnowledge:
            "General Knowledge"
        case .sourceRequired:
            "Source Required"
        }
    }

    var disclosureDescription: String {
        switch self {
        case .corpusGrounded:
            "This answer uses passages retrieved from the texts on this device."
        case .generalKnowledge:
            "This answer uses the model’s general knowledge because no relevant passage was retrieved."
        case .sourceRequired:
            "This question needs a reliable passage from the texts on this device."
        }
    }
}

/// The model's answer to a conversation turn: plain prose plus the terms worth defining within
/// it. `annotatedText` is what the UI actually renders — see `KeyTerm`'s doc comment for why the
/// splice happens here instead of trusting the model to emit `aq://` links directly.
struct ModelResponse {
    let text: String
    let thinkingSummary: [String]
    let keyTerms: [KeyTerm]
    let insight: ConceptDefinition?
    let evidenceBasis: ResponseEvidenceBasis?
    /// Source chips for sentences that quote a retrieved corpus passage.
    let citations: [ResponseCitation]

    init(
        text: String,
        thinkingSummary: [String] = [],
        keyTerms: [KeyTerm] = [],
        insight: ConceptDefinition? = nil,
        evidenceBasis: ResponseEvidenceBasis? = nil,
        citations: [ResponseCitation] = []
    ) {
        self.text = text
        self.thinkingSummary = thinkingSummary
        self.keyTerms = keyTerms
        self.insight = insight
        self.evidenceBasis = evidenceBasis
        self.citations = citations
    }

    /// `text` with each key term wrapped as `[term](aq://slug)` — the markup
    /// `StreamingMessageView`'s existing link parser (`CachedRegex.insightLink`) expects. Matches
    /// each term within its `contextExcerpt` when one is given (to disambiguate a repeated word),
    /// else the first occurrence in the full text.
    var annotatedText: String {
        let source = text as NSString
        var replacements: [(range: NSRange, markup: String)] = []

        // Resolve every range against the untouched prose. Mutating while searching can make a
        // later short term match inside an earlier aq:// URL and leak literal markdown.
        for term in keyTerms.sorted(by: {
            $0.displayText.count > $1.displayText.count
        }) {
            let termRange: NSRange
            if !term.contextExcerpt.isEmpty {
                let excerptRange = source.range(of: term.contextExcerpt)
                termRange = excerptRange.location == NSNotFound
                    ? Self.matchingRange(
                        of: term.displayText,
                        in: text
                    )
                    : Self.matchingRange(
                        of: term.displayText,
                        in: text,
                        searchRange: excerptRange
                    )
            } else {
                termRange = Self.matchingRange(
                    of: term.displayText,
                    in: text
                )
            }
            guard termRange.location != NSNotFound,
                  !replacements.contains(where: {
                      NSIntersectionRange($0.range, termRange).length > 0
                  }) else {
                continue
            }
            replacements.append((
                termRange,
                "[\(term.displayText)](aq://\(Self.slugify(term.canonicalTerm)))"
            ))
        }

        for citation in citations where citation.insertionOffset <= source.length {
            replacements.append((
                NSRange(location: citation.insertionOffset, length: 0),
                " " + ResponseCitationMarkup.markup(for: citation)
            ))
        }

        let mutable = NSMutableString(string: text)
        for replacement in replacements.sorted(by: {
            $0.range.location > $1.range.location
        }) {
            mutable.replaceCharacters(
                in: replacement.range,
                with: replacement.markup
            )
        }
        var result = mutable as String
        if let insight {
            // The generation adapter populates `insight` only after its
            // deterministic direct-definition intent gate requires and validates one. The model
            // supplies definition content; it does not decide whether a card should appear.
            result = "\(InlineInsightMarkup.marker(for: insight))\n\n\(result)"
        }
        return result
    }

    private static func slugify(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    private static func matchingRange(
        of term: String,
        in text: String,
        searchRange: NSRange? = nil
    ) -> NSRange {
        let escaped = NSRegularExpression.escapedPattern(for: term)
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<![\p{L}\p{N}])\#(escaped)(?![\p{L}\p{N}])"#,
            options: [.caseInsensitive]
        ) else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return regex.firstMatch(
            in: text,
            range: searchRange ?? NSRange(text.startIndex..., in: text)
        )?.range ?? NSRange(location: NSNotFound, length: 0)
    }

    func withEvidenceBasis(_ evidenceBasis: ResponseEvidenceBasis) -> ModelResponse {
        ModelResponse(
            text: text,
            thinkingSummary: thinkingSummary,
            keyTerms: keyTerms,
            insight: insight,
            evidenceBasis: evidenceBasis,
            citations: citations
        )
    }
}

/// Encodes generated Insight cards inside the existing persisted response string. Keeping this
/// metadata on its own line lets old conversations remain decodable while the response renderer
/// can restore the complete interactive card after relaunch.
enum InlineInsightMarkup {
    private static let prefix = "<!--aq-inline-insight:"
    private static let suffix = "-->"

    static func marker(for insight: ConceptDefinition) -> String {
        guard let data = try? JSONEncoder().encode(insight) else { return "" }
        return "\(prefix)\(data.base64EncodedString())\(suffix)"
    }

    static func insight(from line: String) -> ConceptDefinition? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix), trimmed.hasSuffix(suffix) else {
            return nil
        }
        let payload = trimmed
            .dropFirst(prefix.count)
            .dropLast(suffix.count)
        guard let data = Data(base64Encoded: String(payload)),
              let decoded = try? JSONDecoder().decode(
                ConceptDefinition.self,
                from: data
              ) else {
            return nil
        }
        return decoded
    }

    static func insights(in text: String) -> [ConceptDefinition] {
        var result: [ConceptDefinition] = []
        for line in text.components(separatedBy: "\n") {
            if let decoded = insight(from: line) {
                result.append(decoded)
            }
        }
        return result
    }

    static func plainText(from text: String) -> String {
        ResponseCitationMarkup.removing(from: text).components(separatedBy: "\n")
            .map { line in
                guard let insight = insight(from: line) else { return line }
                return "\(insight.word)\n\(insight.meaning)"
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Environment

private let defaultAngroveModel: AngroveModel = UnavailableAngroveModel()

extension EnvironmentValues {
    @Entry var angroveModel: AngroveModel = defaultAngroveModel
    @Entry var embeddingProvider: EmbeddingProvider = NLEmbeddingProvider()
}
