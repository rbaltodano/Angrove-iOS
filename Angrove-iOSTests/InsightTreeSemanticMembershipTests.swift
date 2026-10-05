import Foundation
import Testing
@testable import Angrove_iOS

@MainActor
@Suite("Insight Tree semantic membership", .serialized)
struct InsightTreeSemanticMembershipTests {
    private func concept() -> ConceptDefinition {
        ConceptDefinition(id: UUID(), word: "Virtue", partOfSpeech: "", pronunciation: "",
                          meaning: "Habits that perfect moral action.", example: "")
    }

    @Test("MiniLM-space membership waits for embeddings and uses the seeded Node")
    func waitsForMatchingVectors() async throws {
        let insight = concept()
        let seed = LocalInsightTreeSeed(id: UUID(), label: "Moral Virtues", summary: "Moral habits",
                                        embedding: [1, 0], embeddingVersion: "test.semantic.v1", createdAt: Date())
        let scope = UUID()
        let tree = InsightTreeViewModel(insights: [insight], embeddingProvider: MembershipEmbeddingProvider(),
                                       localSeedAnchors: [seed], midpointStoreScope: scope)
        #expect(tree.nodes.map(\.id) == [seed.id])
        #expect(tree.nodes.flatMap(\.insights).isEmpty)
        await tree.prepareSemanticTree()
        #expect(tree.nodes.map(\.id) == [seed.id])
        #expect(tree.nodes.first?.insights.map(\.id) == [insight.id])
        let reopened = InsightTreeViewModel(insights: [insight], embeddingProvider: MembershipEmbeddingProvider(),
                                           localSeedAnchors: [seed], midpointStoreScope: scope)
        await reopened.prepareSemanticTree()
        #expect(reopened.nodes.map(\.id) == [seed.id])
    }

    @Test("Global membership cannot override a conversation seed")
    func scopesMembership() async {
        let insight = concept()
        let provider = MembershipEmbeddingProvider()
        let global = InsightTreeViewModel(insights: [insight], embeddingProvider: provider)
        await global.prepareSemanticTree()
        let seed = LocalInsightTreeSeed(id: UUID(), label: "Moral Virtues", summary: "Moral habits",
                                        embedding: [1, 0], embeddingVersion: provider.version, createdAt: Date())
        let scope = UUID()
        let conversation = InsightTreeViewModel(insights: [insight], embeddingProvider: provider,
                                               localSeedAnchors: [seed], midpointStoreScope: scope)
        await conversation.prepareSemanticTree()
        #expect(conversation.nodes.map(\.id) == [seed.id])
        let reopened = InsightTreeViewModel(insights: [insight], embeddingProvider: provider,
                                           localSeedAnchors: [seed], midpointStoreScope: scope)
        await reopened.prepareSemanticTree()
        #expect(reopened.nodes.map(\.id) == [seed.id])
        #expect(global.nodes.first?.id != seed.id)
    }

    @Test("The seed remains a membership anchor after related peripheral Insights join")
    func retainsSeedSubject() async {
        let first = ConceptDefinition(id: UUID(), word: "First dimension", partOfSpeech: "",
                                      pronunciation: "", meaning: "First", example: "")
        let second = ConceptDefinition(id: UUID(), word: "Second dimension", partOfSpeech: "",
                                       pronunciation: "", meaning: "Second", example: "")
        let unrelated = ConceptDefinition(id: UUID(), word: "Unrelated", partOfSpeech: "",
                                          pronunciation: "", meaning: "Other subject", example: "")
        let provider = PeripheralEmbeddingProvider()
        let seed = LocalInsightTreeSeed(id: UUID(), label: "Seed subject", summary: "Shared subject",
                                        embedding: [1, 0], embeddingVersion: provider.version, createdAt: Date())
        let tree = InsightTreeViewModel(insights: [first], embeddingProvider: provider,
                                       localSeedAnchors: [seed], midpointStoreScope: UUID())
        await tree.prepareSemanticTree()
        tree.updateInsights([first, second, unrelated])
        await tree.prepareSemanticTree()
        #expect(tree.nodes.count == 2)
        #expect(Set(tree.nodes.first(where: { $0.id == seed.id })?.insights.map(\.id) ?? [])
                == Set([first.id, second.id]))
        #expect(tree.nodes.first(where: { $0.id != seed.id })?.insights.map(\.id) == [unrelated.id])
    }

    @Test("Near-duplicate Nodes fold into one, and stay folded on reopen")
    func mergesNearDuplicateNodes() async {
        let provider = MembershipEmbeddingProvider()
        func seed(_ label: String, _ embedding: [Double]) -> LocalInsightTreeSeed {
            LocalInsightTreeSeed(id: UUID(), label: label, summary: label, embedding: embedding,
                                 embeddingVersion: provider.version, createdAt: Date())
        }
        let politics = seed("Ancient Greek Politics", [1, 0])
        let cityStates = seed("Ancient Greek City-States", [0.8, 0.6])
        let law = seed("Divine Law", [0, -1])
        let insight = concept()
        let scope = UUID()
        let tree = InsightTreeViewModel(insights: [insight], embeddingProvider: provider,
                                       localSeedAnchors: [politics, cityStates, law], midpointStoreScope: scope)
        await tree.prepareSemanticTree()
        #expect(Set(tree.nodes.map(\.id)) == [politics.id, law.id])
        #expect(tree.nodes.first(where: { $0.id == politics.id })?.insights.map(\.id) == [insight.id])

        let reopened = InsightTreeViewModel(insights: [insight], embeddingProvider: provider,
                                           localSeedAnchors: [politics, cityStates, law], midpointStoreScope: scope)
        await reopened.prepareSemanticTree()
        #expect(Set(reopened.nodes.map(\.id)) == [politics.id, law.id])
    }

    @Test("Nodes about the same subject fold together even when their members differ")
    func mergesBySubject() async {
        let thucydides = ConceptDefinition(id: UUID(), word: "Thucydides", partOfSpeech: "",
                                           pronunciation: "", meaning: "Historian", example: "")
        let polis = ConceptDefinition(id: UUID(), word: "Polis", partOfSpeech: "",
                                      pronunciation: "", meaning: "City-state", example: "")
        let trinity = ConceptDefinition(id: UUID(), word: "Trinity", partOfSpeech: "",
                                        pronunciation: "", meaning: "One God", example: "")
        let scope = UUID()
        let politics = UUID(), cityStates = UUID(), theology = UUID()
        // Membership already settled each Insight into its own Node, as on the Library canvas.
        InsightTreeLocalStateStore.save(
            [thucydides.id.uuidString: politics.uuidString, polis.id.uuidString: cityStates.uuidString,
             trinity.id.uuidString: theology.uuidString],
            key: "aquinas.insight-tree.insight-cluster-assignments.v2:\(scope.uuidString)"
        )
        var labels = InsightTreeLocalStateStore.load([String: String].self, key: "aquinas.insight-tree.cluster-labels.v1") ?? [:]
        var definitions = InsightTreeLocalStateStore.load([String: String].self, key: "aquinas.insight-tree.cluster-definitions.v1") ?? [:]
        for (id, label) in [(politics, "Greek Politics"), (cityStates, "Greek City-States"), (theology, "Theology")] {
            labels[id.uuidString] = label
            definitions[id.uuidString] = "Definition"
        }
        InsightTreeLocalStateStore.save(labels, key: "aquinas.insight-tree.cluster-labels.v1")
        InsightTreeLocalStateStore.save(definitions, key: "aquinas.insight-tree.cluster-definitions.v1")

        let tree = InsightTreeViewModel(insights: [thucydides, polis, trinity],
                                       embeddingProvider: SubjectEmbeddingProvider(), midpointStoreScope: scope)
        await tree.prepareSemanticTree()
        await tree.prepareSemanticTree()
        #expect(tree.nodes.count == 2)
        let greek = tree.nodes.first { $0.insights.contains { $0.id == thucydides.id } }
        #expect(Set(greek?.insights.map(\.id) ?? []) == [thucydides.id, polis.id])
        #expect(tree.nodes.first { $0.insights.contains { $0.id == trinity.id } }?.id == theology)
    }

    @Test("Stale seed vectors are refreshed before membership")
    func refreshesSeeds() async {
        let insight = concept()
        let seed = LocalInsightTreeSeed(id: UUID(), label: "Moral Virtues", summary: "Moral habits",
                                        embedding: [0, 1, 0], embeddingVersion: "old.space", createdAt: Date())
        let tree = InsightTreeViewModel(insights: [insight], embeddingProvider: MembershipEmbeddingProvider(),
                                       localSeedAnchors: [seed], midpointStoreScope: UUID())
        await tree.prepareSemanticTree()
        #expect(tree.nodes.map(\.id) == [seed.id])
        #expect(tree.nodes.first?.insights.map(\.id) == [insight.id])
    }
}

private struct MembershipEmbeddingProvider: EmbeddingProvider {
    var version: String { "test.semantic.v1" }
    func embed(_ text: String) async -> [Double]? { [1, 0] }
}

private struct PeripheralEmbeddingProvider: EmbeddingProvider {
    var version: String { "test.peripheral.v1" }
    func embed(_ text: String) async -> [Double]? {
        if text.hasPrefix("First") { return [0.5, sqrt(0.75)] }
        if text.hasPrefix("Second") { return [0.5, -sqrt(0.75)] }
        return [-1, 0]
    }
}

/// Members point in unrelated directions; only the two Greek subjects are close.
private struct SubjectEmbeddingProvider: EmbeddingProvider {
    var version: String { "test.subject.v1" }
    func embed(_ text: String) async -> [Double]? {
        if text.hasPrefix("Thucydides") { return [1, 0, 0, 0] }
        if text.hasPrefix("Polis") { return [0, 1, 0, 0] }
        if text.hasPrefix("Trinity") { return [0, 0, 1, 0] }
        if text.hasPrefix("Greek Politics") { return [0, 0, 0.3, 1] }
        if text.hasPrefix("Greek City-States") { return [0, 0, 0, 1] }
        return [0, 0, 1, 0.2]
    }
}
