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
