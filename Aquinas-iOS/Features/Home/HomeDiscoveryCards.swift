//
//  HomeDiscoveryCards.swift
//  Aquinas-iOS
//

import Foundation

struct LooseThreadCard: Equatable {
    let conversationID: UUID
    let nodeID: UUID
    let nodeLabel: String
    let insightCount: Int
}

struct GlossedTermCard: Equatable {
    let concept: ConceptDefinition

    var title: String { concept.word }
    var definition: String { concept.meaning }
}

struct TodayInHistoryCard: Equatable {
    let title: String
    let description: String

    /// Hidden context prepended to the first conversation started from the "Tell me more..."
    /// button, mirroring `HomeQuestionOfTheDay.taggedPromptContext`.
    var taggedPromptContext: String {
        """
        <today in history>
        <title>\(title.xmlEscaped)</title>
        <description>\(description.xmlEscaped)</description>
        <response_guidance>The user's next message is a question inspired by this historical \
        note. Answer it in light of the note above when relevant, without assuming the user has \
        already read it.</response_guidance>
        </today in history>
        """
    }
}

struct YourQuoteCard: Equatable {
    let quoteText: String
}

/// Tracks whether the user has already started a conversation from today's Today in History
/// card, mirroring `HomeQuestionOfTheDayStore`'s answered-state pattern -- once asked, the card
/// disappears from Home until the calendar day rolls over.
enum HomeTodayInHistoryStore {
    private static let key = "aquinas.home.todayInHistory.answeredDayKey.v1"

    static func markAnswered(at date: Date = Date()) {
        UserDefaults.standard.set(dayKey(for: date), forKey: key)
    }

    static func isAnswered(at date: Date = Date()) -> Bool {
        UserDefaults.standard.string(forKey: key) == dayKey(for: date)
    }

    private static func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

/// Selects Home's four optional discovery cards entirely on device. Every selector is fail-quiet:
/// `nil` means the section is omitted, never replaced by placeholder content.
enum HomeDiscovery {
    /// Two Node Concepts at or above this MiniLM similarity count as strongly connected.
    static let strongConnectionSimilarity = 0.70
    /// A lookup must be at least this old before it reads as glossed over rather than mid-lookup.
    static let glossedTermStaleness: TimeInterval = 24 * 60 * 60

    static func todayInHistory(on date: Date = Date()) -> TodayInHistoryCard? {
        guard !HomeTodayInHistoryStore.isAnswered(at: date),
              let entry = TodayInHistoryCatalog.entry(for: date) else {
            return nil
        }
        return TodayInHistoryCard(title: entry.title, description: entry.description)
    }

    /// The oldest stale lookup in the conversation that the user never saved as an Insight.
    static func glossedTerm(
        in records: [GlossedTermRecord],
        savedInsightIDs: Set<UUID>,
        now: Date = Date()
    ) -> GlossedTermCard? {
        records
            .filter {
                !savedInsightIDs.contains($0.definition.id)
                    && now.timeIntervalSince($0.lookedUpAt) >= glossedTermStaleness
            }
            .min { $0.lookedUpAt < $1.lookedUpAt }
            .map { GlossedTermCard(concept: $0.definition) }
    }

    static let quoteCandidateMinimumLength = 40
    private static let quoteFillerPhrases: Set<String> = [
        "ok", "okay", "thanks", "thank you", "got it", "continue", "go on",
        "sure", "sounds good", "makes sense", "cool", "nice", "great",
    ]

    /// Cheap, no-model pre-filter for "Your Quote": long enough to be an original synthesis, not
    /// phrased as a question, and not filler. Passing only makes the message a candidate for the
    /// model's notability check; it does not decide notability by itself.
    static func isQuoteCandidate(_ message: String) -> Bool {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= quoteCandidateMinimumLength, !text.hasSuffix("?") else { return false }
        let normalized = text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .!"))
        return !quoteFillerPhrases.contains(normalized)
    }

    static func yourQuote(in conversationID: UUID) -> YourQuoteCard? {
        FlaggedQuoteStore.surfaceableQuote(for: conversationID)
            .map { YourQuoteCard(quoteText: $0.quoteText) }
    }

    /// A Node Concept with no strong connection to any other Node Concept in the conversation.
    /// Ties prefer the Node with more attached Insights (more invested-in but still unconnected),
    /// then the oldest. A conversation needs at least two Node Concepts for "unconnected" to mean
    /// anything.
    static func looseThread(
        conversationID: UUID,
        seeds: [LocalInsightTreeSeed],
        insightEmbeddings: [[Double]]
    ) -> LooseThreadCard? {
        let embedded = seeds.compactMap { seed -> (seed: LocalInsightTreeSeed, embedding: [Double])? in
            guard let embedding = seed.embedding, !embedding.isEmpty else { return nil }
            return (seed, embedding)
        }
        guard embedded.count >= 2 else { return nil }

        var insightCounts: [UUID: Int] = [:]
        for insightEmbedding in insightEmbeddings {
            let best = embedded
                .map { ($0.seed.id, cosineSimilarity(insightEmbedding, $0.embedding)) }
                .max { $0.1 < $1.1 }
            guard let best,
                  best.1 >= InsightTreeSemanticPolicy.membershipSimilarity else { continue }
            insightCounts[best.0, default: 0] += 1
        }

        let loose = embedded.filter { candidate in
            !embedded.contains { other in
                other.seed.id != candidate.seed.id
                    && cosineSimilarity(candidate.embedding, other.embedding)
                        >= strongConnectionSimilarity
            }
        }
        guard let chosen = loose.min(by: { left, right in
            let leftCount = insightCounts[left.seed.id, default: 0]
            let rightCount = insightCounts[right.seed.id, default: 0]
            if leftCount != rightCount { return leftCount > rightCount }
            return left.seed.createdAt < right.seed.createdAt
        }) else {
            return nil
        }
        return LooseThreadCard(
            conversationID: conversationID,
            nodeID: chosen.seed.id,
            nodeLabel: chosen.seed.label,
            insightCount: insightCounts[chosen.seed.id, default: 0]
        )
    }

    /// Loads the conversation's seeds and saved Insights, embedding the Insights in the same
    /// space the seeds were embedded in. Seeds from an older embedding version are skipped rather
    /// than compared across vector spaces.
    static func looseThread(
        in conversationID: UUID,
        savedInsights: [ConceptDefinition],
        embeddingProvider: EmbeddingProvider
    ) async -> LooseThreadCard? {
        let seeds = LocalInsightTreeSeedStore.seeds(for: conversationID)
            .filter { $0.embeddingVersion == embeddingProvider.version }
        guard seeds.count >= 2 else { return nil }
        let memberIDs = ConversationInsightMembershipStore.insightIDs(for: conversationID)
        var insightEmbeddings: [[Double]] = []
        for insight in savedInsights where memberIDs.contains(insight.id) {
            if let embedding = await embeddingProvider.embed(
                "\(insight.word). \(insight.semanticDefinition)"
            ) {
                insightEmbeddings.append(embedding)
            }
        }
        return looseThread(
            conversationID: conversationID,
            seeds: seeds,
            insightEmbeddings: insightEmbeddings
        )
    }
}
