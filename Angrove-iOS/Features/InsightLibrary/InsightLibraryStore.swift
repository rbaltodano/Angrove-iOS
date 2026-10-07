//
//  InsightLibraryStore.swift
//  Angrove-iOS
//

import Foundation

// MARK: - Saved Insight Library

/// Lightweight persistence for saved insights until the production SwiftData layer owns them.
enum InsightLibraryStore {
    private static let savedInsightsKey = "aquinas.saved.insights.v1"

    static func load() -> [ConceptDefinition] {
        InsightTreeLocalStateStore.load([ConceptDefinition].self, key: savedInsightsKey) ?? []
    }

    static func save(_ insights: [ConceptDefinition]) {
        let uniqueInsights = insights.uniquedByWord()

        InsightTreeLocalStateStore.save(uniqueInsights, key: savedInsightsKey)
    }
}

/// Persisted library excerpts saved from passage quote cards.
enum ClippedPassageStore {
    private static let storeKey = "aquinas.library.clipped-passages.v1"

    static func load() -> [ConceptDefinition] {
        (InsightTreeLocalStateStore.load([ConceptDefinition].self, key: storeKey) ?? [])
            .filter(\.isLibraryQuote)
    }

    static func save(_ passages: [ConceptDefinition]) {
        var seen = Set<String>()
        let unique = passages.filter { passage in
            let key = "\(passage.word.lowercased())\u{1f}\(passage.semanticDefinition.lowercased())"
            return passage.isLibraryQuote && seen.insert(key).inserted
        }
        InsightTreeLocalStateStore.save(unique, key: storeKey)
    }
}

/// The last bookmark collection the user explicitly accepted for the Global Insight Tree.
///
/// Keeping this separate from `InsightLibraryStore` lets saving remain immediate while the
/// potentially disruptive canvas regrouping waits for confirmation when Global Insights opens.
enum GlobalInsightTreeStore {
    private static let snapshotKey = "aquinas.global-insight-tree.snapshot.v1"

    static func load() -> [ConceptDefinition] {
        (InsightTreeLocalStateStore.load([ConceptDefinition].self, key: snapshotKey) ?? [])
            .uniquedByWord()
    }

    static func save(_ insights: [ConceptDefinition]) {
        InsightTreeLocalStateStore.save(insights.uniquedByWord(), key: snapshotKey)
    }
}

/// Decides when Global Insights offers to update its tree.
///
/// The tree's snapshot can differ from the bookmark library indefinitely (reconciliation merges
/// near-duplicates and keeps the tree's own copies), so comparing the two alone asked on every
/// open even when accepting would change nothing. The offer is instead tied to the library
/// itself: it is made only when the saved Insights differ from the ones the user last answered
/// the prompt for.
enum GlobalInsightTreeUpdatePrompt {
    private static let storeKey = "aquinas.global-insight-tree.acknowledged-library-ids.v1"

    /// `acknowledgedLibraryIDs` is nil until the prompt has been answered once.
    nonisolated static func shouldOffer(
        libraryIDs: Set<UUID>,
        acknowledgedLibraryIDs: Set<UUID>?,
        treeNeedsUpdate: Bool
    ) -> Bool {
        treeNeedsUpdate && acknowledgedLibraryIDs != libraryIDs
    }

    static func loadAcknowledgedLibraryIDs() -> Set<UUID>? {
        InsightTreeLocalStateStore.load(Set<UUID>.self, key: storeKey)
    }

    static func saveAcknowledgedLibraryIDs(_ ids: Set<UUID>) {
        InsightTreeLocalStateStore.save(ids, key: storeKey)
    }
}

/// Which Insights the Global Insight Tree has promoted into their own Node Concept via Make Node.
/// A per-conversation tree gets this for free through its own conversation snapshot
/// (`InquiryConversation.promotedInsightIDs`); the Global tree has no equivalent owning snapshot,
/// so without this a Make Node promotion reverted the moment the tree view was recreated (e.g.
/// navigating away and back) even though the promoted Insight's saved bookmark itself persisted.
enum GlobalInsightPromotedIDsStore {
    private static let storeKey = "aquinas.global-insight-tree.promoted-ids.v1"

    static func load() -> [UUID] {
        InsightTreeLocalStateStore.load([UUID].self, key: storeKey) ?? []
    }

    static func save(_ ids: [UUID]) {
        InsightTreeLocalStateStore.save(ids, key: storeKey)
    }
}

/// Folds newly bookmarked Insights into the Global Insight Tree snapshot when "Update" is accepted.
///
/// Only the nearest existing Insight is considered, and it is treated as the same Insight only
/// when it is both very similar AND its term overlaps the new one's (e.g. "Grace" and "Divine
/// Grace"). Similarity alone is not enough: when Apple's sentence embedding is unavailable the
/// fallback vectors score almost any two English definitions above the threshold, which silently
/// merged unrelated new Insights into existing ones (and overwrote their definitions).
enum GlobalInsightReconciliation {
    static let similarityThreshold = 0.86

    nonisolated static func reconcile(
        existing: [ConceptDefinition],
        incoming: [ConceptDefinition],
        embed: (String) -> [Double]? = computeEmbedding(for:)
    ) -> [ConceptDefinition] {
        var result: [ConceptDefinition] = []
        var resultIDs = Set<UUID>()
        for insight in existing where resultIDs.insert(insight.id).inserted {
            result.append(insight)
        }
        var embeddingsByID: [UUID: [Double]] = [:]
        for insight in result {
            embeddingsByID[insight.id] = embed("\(insight.word). \(insight.semanticDefinition)")
        }

        for candidate in incoming.uniquedByWord() {
            let candidateEmbedding = embed("\(candidate.word). \(candidate.semanticDefinition)")

            let nearest = candidateEmbedding.flatMap { candidateEmbedding in
                result.compactMap { saved -> (ConceptDefinition, Double)? in
                    guard termsOverlap(saved.word, candidate.word),
                          let savedEmbedding = embeddingsByID[saved.id] else { return nil }
                    return (saved, cosineSimilarity(candidateEmbedding, savedEmbedding))
                }.max { $0.1 < $1.1 }
            }

            guard let (saved, similarity) = nearest, similarity >= similarityThreshold else {
                if resultIDs.insert(candidate.id).inserted {
                    result.append(candidate)
                    embeddingsByID[candidate.id] = candidateEmbedding
                }
                continue
            }

            // Keep the shorter title as the canonical display name. Prefer the more informative
            // definition when one is clearly longer, retaining the existing Insight's identity.
            let canonicalTitle = candidate.word.split(separator: " ").count < saved.word.split(separator: " ").count
                ? candidate.word : saved.word
            let canonicalDefinitions = candidate.semanticDefinition.count > saved.semanticDefinition.count
                ? candidate.contextualDefinitions : saved.contextualDefinitions
            let merged = ConceptDefinition(
                id: saved.id,
                word: canonicalTitle,
                partOfSpeech: saved.partOfSpeech,
                pronunciation: saved.pronunciation,
                meaning: canonicalDefinitions.first?.meaning ?? saved.meaning,
                example: saved.example,
                definitions: canonicalDefinitions
            )
            if let index = result.firstIndex(where: { $0.id == saved.id }) {
                result[index] = merged
                embeddingsByID[saved.id] = embed("\(merged.word). \(merged.semanticDefinition)")
            }
        }
        return result
    }

    /// True when every significant word of the shorter term appears in the longer one.
    nonisolated static func termsOverlap(_ first: String, _ second: String) -> Bool {
        let a = significantWords(first), b = significantWords(second)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a.count <= b.count ? a.isSubset(of: b) : b.isSubset(of: a)
    }

    private nonisolated static func significantWords(_ term: String) -> Set<String> {
        let stopWords: Set<String> = ["the", "and", "of", "a", "an", "in", "on", "to", "for"]
        return Set(
            term.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty && !stopWords.contains($0) }
        )
    }
}

extension Array where Element == ConceptDefinition {
    func uniquedByWord() -> [ConceptDefinition] {
        var indexByWord: [String: Int] = [:]
        var uniqueInsights: [ConceptDefinition] = []

        for insight in self {
            let key = insight.word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }
            if let existingIndex = indexByWord[key] {
                uniqueInsights[existingIndex] = uniqueInsights[
                    existingIndex
                ].mergingDefinitions(from: insight)
            } else {
                indexByWord[key] = uniqueInsights.count
                uniqueInsights.append(insight)
            }
        }

        return uniqueInsights
    }
}
