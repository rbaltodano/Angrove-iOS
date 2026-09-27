import Foundation
import Testing
@testable import Aquinas_iOS

@Suite("Global Insight Tree reconciliation")
struct GlobalInsightReconciliationTests {
    /// Every text embeds identically — the worst case of an unavailable sentence model.
    private let identicalEmbedding: (String) -> [Double]? = { _ in [1, 0, 0] }

    @Test("A new Insight with an unrelated term is added even when embeddings look identical")
    func unrelatedTermIsAdded() {
        let charity = concept("Charity", "Love of God and neighbor.")
        let photosynthesis = concept("Photosynthesis", "How plants turn sunlight into energy.")

        let result = GlobalInsightReconciliation.reconcile(
            existing: [charity],
            incoming: [charity, photosynthesis],
            embed: identicalEmbedding
        )

        #expect(result.map(\.id) == [charity.id, photosynthesis.id])
        #expect(result.first?.meaning == charity.meaning)
    }

    @Test("A near-identical Insight with an overlapping term merges into the existing one")
    func overlappingTermMerges() {
        let grace = concept("Grace", "A gift.")
        let divineGrace = concept("Divine Grace", "The free and undeserved gift of God's favor.")

        let result = GlobalInsightReconciliation.reconcile(
            existing: [grace],
            incoming: [divineGrace],
            embed: identicalEmbedding
        )

        #expect(result.map(\.id) == [grace.id])
        #expect(result.first?.word == "Grace")
        #expect(result.first?.meaning == divineGrace.meaning)
    }

    @Test("Term overlap ignores case, punctuation, and filler words")
    func termOverlap() {
        #expect(GlobalInsightReconciliation.termsOverlap("Grace", "divine grace"))
        #expect(GlobalInsightReconciliation.termsOverlap("The Good", "good"))
        #expect(!GlobalInsightReconciliation.termsOverlap("Charity", "Photosynthesis"))
        #expect(!GlobalInsightReconciliation.termsOverlap("Natural Law", "Divine Law of Grace"))
    }

    private func concept(_ word: String, _ meaning: String) -> ConceptDefinition {
        ConceptDefinition(word: word, partOfSpeech: "noun", pronunciation: "", meaning: meaning, example: "")
    }
}
