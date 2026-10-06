import Foundation
import Testing
@testable import Angrove_iOS

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

@Suite("Global Insight Tree update prompt")
struct GlobalInsightTreeUpdatePromptTests {
    private let first = UUID()
    private let second = UUID()

    @Test("Reopening with the same saved Insights does not ask again")
    func unchangedLibraryIsNotOffered() {
        #expect(!GlobalInsightTreeUpdatePrompt.shouldOffer(
            libraryIDs: [first, second],
            acknowledgedLibraryIDs: [first, second],
            treeNeedsUpdate: true
        ))
    }

    @Test("Saving or removing an Insight since the last answer asks again")
    func changedLibraryIsOffered() {
        #expect(GlobalInsightTreeUpdatePrompt.shouldOffer(
            libraryIDs: [first, second],
            acknowledgedLibraryIDs: [first],
            treeNeedsUpdate: true
        ))
        #expect(GlobalInsightTreeUpdatePrompt.shouldOffer(
            libraryIDs: [first],
            acknowledgedLibraryIDs: [first, second],
            treeNeedsUpdate: true
        ))
    }

    @Test("A swap that keeps the count the same still asks")
    func swappedInsightIsOffered() {
        #expect(GlobalInsightTreeUpdatePrompt.shouldOffer(
            libraryIDs: [second],
            acknowledgedLibraryIDs: [first],
            treeNeedsUpdate: true
        ))
    }

    @Test("A never-answered prompt is offered, but not when the tree already matches")
    func unansweredPrompt() {
        #expect(GlobalInsightTreeUpdatePrompt.shouldOffer(
            libraryIDs: [first],
            acknowledgedLibraryIDs: nil,
            treeNeedsUpdate: true
        ))
        #expect(!GlobalInsightTreeUpdatePrompt.shouldOffer(
            libraryIDs: [first],
            acknowledgedLibraryIDs: nil,
            treeNeedsUpdate: false
        ))
    }
}

@Suite("Contextual definition duplicates")
struct ContextualDefinitionDuplicateTests {
    private let original = "Free will is the principle by which a person judges freely, which Aquinas identifies as an appetitive power that allows man to act from free judgment rather than natural instinct. It is the capacity for a rational being to choose between various things, retaining the power to be inclined toward different outcomes."
    private let repeated = "Free will is the principle of the act by which a person judges freely, which Aquinas identifies as an appetitive power that allows man to act from free judgment rather than natural instinct. It is the actual cause of a person's actions in time, enabling a rational being to choose between different outcomes."

    private func concept(_ meaning: String, context: String) -> ConceptDefinition {
        ConceptDefinition(word: "Free Will", partOfSpeech: "", pronunciation: "",
                          meaning: meaning, example: "", context: context)
    }

    @Test("The photographed Free Will restatement does not append a second definition")
    func freeWillRestatement() {
        let first = concept(original, context: "Aquinas")
        let next = concept(repeated, context: "Human action")
        let merged = first.mergingDefinitions(from: next)
        #expect(merged.id == first.id)
        #expect(merged.contextualDefinitions == first.contextualDefinitions)
        #expect(first.containsDefinitions(from: next))
    }

    @Test("Identical meanings with different sources and punctuation appear once")
    func differentSource() {
        let first = concept("The capacity to choose freely.", context: "First conversation")
        let next = concept("THE capacity to choose freely!", context: "Second conversation")
        #expect(first.mergingDefinitions(from: next).contextualDefinitions.count == 1)
    }

    @Test("Library and tree title deduplication use the same definition guard")
    func libraryMerge() {
        let first = concept(original, context: "Aquinas")
        let next = concept(repeated, context: "Human action")
        let result = [first, next].uniquedByWord()
        #expect(result.count == 1)
        #expect(result.first?.contextualDefinitions == first.contextualDefinitions)
    }

    @Test("Short differing meanings are preserved")
    func shortMeanings() {
        let first = concept("The power to choose good.", context: "First")
        let next = concept("The power to choose evil.", context: "Second")
        #expect(first.mergingDefinitions(from: next).contextualDefinitions.count == 2)
    }

    @Test("A substantially different contextual meaning remains available")
    func distinctContext() {
        let first = concept(original, context: "Aquinas")
        let next = concept("In politics, free will describes voluntary participation without coercion by the state.", context: "Politics")
        let merged = first.mergingDefinitions(from: next)
        #expect(merged.contextualDefinitions.count == 2)
        #expect(!first.containsDefinitions(from: next))
    }

    @Test("A negated definition is not treated as a restatement")
    func negatedMeaning() {
        let first = concept(original, context: "Aquinas")
        let next = concept(original.replacingOccurrences(of: "allows man", with: "does not allow man"), context: "Objection")
        #expect(first.mergingDefinitions(from: next).contextualDefinitions.count == 2)
    }

    @Test("Persisted duplicates are repaired on decode without changing the saved identity")
    func persistedDuplicates() throws {
        let id = UUID()
        let first = InsightDefinition(context: "Aquinas", meaning: original)
        let next = InsightDefinition(context: "Human action", meaning: repeated)
        let record: [String: Any] = [
            "id": id.uuidString, "word": "Free Will", "meaning": original,
            "definitions": [
                ["id": first.id.uuidString, "context": first.context, "meaning": first.meaning],
                ["id": next.id.uuidString, "context": next.context, "meaning": next.meaning]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: record)
        let decoded = try JSONDecoder().decode(ConceptDefinition.self, from: data)
        #expect(decoded.id == id)
        #expect(decoded.contextualDefinitions == [first])
        let reopened = try JSONDecoder().decode(ConceptDefinition.self, from: JSONEncoder().encode(decoded))
        #expect(reopened == decoded)
    }
}
