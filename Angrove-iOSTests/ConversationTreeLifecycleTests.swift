import Foundation
import Testing
@testable import Angrove_iOS

@MainActor
@Suite("Conversation tree lifecycle", .serialized)
struct ConversationTreeLifecycleTests {
    @Test("Three detached turns retain their own mapping jobs while another mapping is running")
    func detachedTurnsAreNotSuppressed() async throws {
        let queue = ModelTaskQueue()
        let conversations = [UUID(), UUID(), UUID()]
        var completed: [UUID] = []
        var releaseFirst = false
        for id in conversations {
            ConversationTreeAnalysisScheduling.enqueue(on: queue, conversationID: id) {
                if id == conversations[0] {
                    while !releaseFirst { try? await Task.sleep(for: .milliseconds(5)) }
                }
                completed.append(id)
            }
        }
        #expect(queue.upcomingTasks.map(\.conversationID) == Array(conversations.dropFirst()).map(Optional.some))
        releaseFirst = true
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while queue.isBusy, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(!queue.isBusy)
        #expect(completed == conversations)
    }

    @Test("Restored response mentions use the bookmarked definition and stable saved identity")
    func savedContentWins() {
        let old = ConceptDefinition(word: "Virtue", partOfSpeech: "", pronunciation: "", meaning: "Old answer's definition", example: "")
        let saved = ConceptDefinition(word: "Virtue", partOfSpeech: "", pronunciation: "", meaning: "The user's saved contextual definition", example: "")
        var branch = ChatBranch(startingConcept: old)
        branch.attachedConcept = old
        let resolved = ChatBranch.resolvedConversationInsights(in: [branch], savedInsights: [saved], manuallySavedIDs: [saved.id])
        #expect(resolved == [saved])
    }

    @Test("A separately bookmarked Insight remains visible after returning to a seeded conversation")
    func returningTreeKeepsSavedChip() async throws {
        let saved = ConceptDefinition(word: "Virtue", partOfSpeech: "", pronunciation: "", meaning: "A settled moral habit", example: "")
        let provider = TreeLifecycleEmbeddingProvider()
        let seed = LocalInsightTreeSeed(id: UUID(), label: "Virtue", summary: "Moral habits", embedding: [1, 0], embeddingVersion: provider.version, createdAt: Date())
        let tree = InsightTreeViewModel(insights: [], modelTasks: ModelTaskQueue(), embeddingProvider: provider, localSeedAnchors: [seed], midpointStoreScope: UUID())
        await tree.prepareSemanticTree()
        tree.updateInsights([saved])
        await tree.prepareSemanticTree()
        let node = try #require(tree.nodes.first { $0.insights.contains { $0.id == saved.id } })
        #expect(node.insights.first?.definition == saved.semanticDefinition)
        #expect(canvasInsightMembers(nodeLabel: seed.label, insights: node.insights, preservesMatchingTitle: false).map(\.id) == [saved.id])
        // Vectors now match; a second refresh must still wait for its asynchronous graph result.
        tree.updateInsights([saved])
        await tree.prepareSemanticTree()
        #expect(tree.nodes.flatMap(\.insights).map(\.id) == [saved.id])
    }
}

private struct TreeLifecycleEmbeddingProvider: EmbeddingProvider {
    var version: String { "test.tree-lifecycle.v1" }
    func embed(_ text: String) async -> [Double]? { [1, 0] }
}
