import CoreGraphics
import Foundation
import Testing
@testable import Angrove_iOS

/// Covers the canvas-local persistence stores added for Make Node / Midpoint / cluster state:
/// each one exists specifically so that recreating the view (navigating away and back, or
/// switching conversations) doesn't silently drop state that looks committed to the user. These
/// tests simulate that recreation by constructing a second, independent store/view model against
/// the same UserDefaults-backed scope and asserting the state carried over.
@Suite("Insight Tree canvas persistence")
struct InsightTreeCanvasPersistenceTests {
    private func makeConcept(word: String = "Essence") -> ConceptDefinition {
        ConceptDefinition(
            word: word,
            partOfSpeech: "",
            pronunciation: "",
            meaning: "What a thing is, apart from the act by which it exists.",
            example: ""
        )
    }


    @MainActor
    @Test("All ordinary concepts bookmark as anchors without extra chips")
    func ordinaryConceptBookmarks() async throws {
        let scope = UUID()
        let source = makeConcept(word: "First")
        let tree = InsightTreeViewModel(insights: [source], model: MockAngroveModel(),
            embeddingProvider: MidpointTestEmbeddingProvider(), midpointStoreScope: scope)
        await tree.prepareSemanticTree()
        let bookmarks = tree.automaticNodeBookmarks()
        #expect(Set(bookmarks.map(\.id)) == Set(tree.nodes.map(\.id)))
        let reopened = InsightTreeViewModel(insights: [source] + bookmarks, model: MockAngroveModel(),
            embeddingProvider: MidpointTestEmbeddingProvider(), midpointStoreScope: scope)
        await reopened.prepareSemanticTree()
        #expect(Set(reopened.nodes.map(\.id)) == Set(tree.nodes.map(\.id)))
        #expect(reopened.nodes.flatMap(\.insights).map(\.id) == [source.id])
    }

    @MainActor
    @Test("Removing an ordinary concept either deletes or reparents its members across reload", arguments: [false, true])
    func removeOrdinaryConcept(deleting: Bool) async throws {
        let scope = UUID()
        let source = makeConcept(word: "First")
        let seeds = [
            LocalInsightTreeSeed(id: UUID(), label: "Owner", summary: "", embedding: [1, 0], embeddingVersion: "midpoint-test.v1", createdAt: Date()),
            LocalInsightTreeSeed(id: UUID(), label: "Neighbor", summary: "", embedding: [0, 1], embeddingVersion: "midpoint-test.v1", createdAt: Date())
        ]
        let tree = InsightTreeViewModel(insights: [source], model: MockAngroveModel(),
            embeddingProvider: MidpointTestEmbeddingProvider(), localSeedAnchors: seeds, midpointStoreScope: scope)
        await tree.prepareSemanticTree()
        let owner = try #require(tree.nodes.first { $0.insights.contains { $0.id == source.id } })
        let neighbor = try #require(tree.nodes.first { $0.id != owner.id })
        let bookmarks = tree.automaticNodeBookmarks()
        let removed = tree.removeBookmarkedNode(id: owner.id, deletingInsights: deleting)
        #expect(Set(removed.map(\.id)) == Set([owner.id] + (deleting ? [source.id] : [])))
        #expect(!tree.nodes.contains { $0.id == owner.id })
        if deleting { #expect(tree.nodes.flatMap(\.insights).isEmpty) }
        else { #expect(tree.nodes.first { $0.id == neighbor.id }?.insights.map(\.id) == [source.id]) }
        // Even an outdated seed/input snapshot cannot revive an explicit removal.
        let reopened = InsightTreeViewModel(insights: [source] + bookmarks, model: MockAngroveModel(),
            embeddingProvider: MidpointTestEmbeddingProvider(), localSeedAnchors: seeds, midpointStoreScope: scope)
        await reopened.prepareSemanticTree()
        #expect(!reopened.nodes.contains { $0.id == owner.id })
        #expect(reopened.nodes.flatMap(\.insights).map(\.id) == (deleting ? [] : [source.id]))
        if !deleting { #expect(reopened.nodes.first { $0.id == neighbor.id }?.insights.map(\.id) == [source.id]) }
    }

    @MainActor
    @Test("Midpoint bookmarks and both removal choices survive reload", arguments: [false, true])
    func removeMidpointConcept(deleting: Bool) async throws {
        let scope = UUID()
        let sources = [makeConcept(word: "First"), makeConcept(word: "Second")]
        let provider = MidpointTestEmbeddingProvider()
        let tree = InsightTreeViewModel(insights: sources, model: MockAngroveModel(),
            embeddingProvider: provider, midpointStoreScope: scope)
        await tree.prepareSemanticTree()
        _ = tree.automaticNodeBookmarks()
        let loading = makeConcept(word: "")
        tree.addPlacedMidpoint(concept: loading, at: .zero,
            sources: sources.map { MidpointSource(insightID: $0.id, isNode: false) })
        try await tree.replacePlacedMidpoint(id: loading.id, with: makeConcept(word: "Combined"))
        let bookmarks = tree.automaticNodeBookmarks()
        #expect(bookmarks.contains { $0.id == loading.id })
        let removed = tree.removeBookmarkedNode(id: loading.id, deletingInsights: deleting)
        #expect(removed.count == (deleting ? 3 : 1))
        let reopened = InsightTreeViewModel(insights: sources + bookmarks, model: MockAngroveModel(),
            embeddingProvider: provider, midpointStoreScope: scope)
        await reopened.prepareSemanticTree()
        #expect(!reopened.nodes.contains { $0.id == loading.id })
        let ids = reopened.nodes.flatMap(\.insights).map(\.id)
        #expect(Set(ids) == (deleting ? [] : Set(sources.map(\.id))))
        #expect(ids.count == (deleting ? 0 : 2))
    }

    @MainActor
    @Test("Keeping the last concept's Insights creates a new home without resurrecting the old concept")
    func removeLastConcept() async throws {
        let scope = UUID()
        let source = makeConcept(word: "First")
        let tree = InsightTreeViewModel(insights: [source], model: MockAngroveModel(),
            embeddingProvider: MidpointTestEmbeddingProvider(), midpointStoreScope: scope)
        await tree.prepareSemanticTree()
        let owner = try #require(tree.nodes.first)
        _ = tree.automaticNodeBookmarks()
        _ = tree.removeBookmarkedNode(id: owner.id, deletingInsights: false)
        #expect(!tree.nodes.contains { $0.id == owner.id })
        #expect(tree.nodes.flatMap(\.insights).map(\.id) == [source.id])
    }

    @MainActor
    @Test("A concept bookmarked in a conversation becomes an anchor in another tree")
    func conceptBookmarkCrossScope() async throws {
        let source = makeConcept(word: "First")
        let provider = MidpointTestEmbeddingProvider()
        let first = InsightTreeViewModel(insights: [source], model: MockAngroveModel(),
            embeddingProvider: provider, midpointStoreScope: UUID())
        await first.prepareSemanticTree()
        let bookmark = try #require(first.automaticNodeBookmarks().first)
        let otherScope = UUID()
        let other = InsightTreeViewModel(insights: [bookmark], model: MockAngroveModel(),
            embeddingProvider: provider, midpointStoreScope: otherScope)
        await other.prepareSemanticTree()
        #expect(other.nodes.first?.id == bookmark.id)
        #expect(other.nodes.flatMap(\.insights).isEmpty)
        _ = other.automaticNodeBookmarks()
        _ = first.removeBookmarkedNode(id: bookmark.id, deletingInsights: false)
        other.updateInsights([])
        await other.prepareSemanticTree()
        #expect(!other.nodes.contains { $0.id == bookmark.id })
    }

    @MainActor
    @Test("Keeping generated Make Node children removes the promotion and preserves one owner", arguments: [false, true])
    func removePromotedConcept(deleting: Bool) async throws {
        let scope = UUID()
        let source = makeConcept(word: "First")
        let tree = InsightTreeViewModel(insights: [source], promotedInsightIDs: [source.id], model: MockAngroveModel(),
            embeddingProvider: MidpointTestEmbeddingProvider(), midpointStoreScope: scope)
        tree.reserveMakeNodeGeneration(for: source.id)
        try await tree.generateReservedMakeNodeChildren(for: InsightModel(concept: source))
        await tree.prepareSemanticTree()
        let node = try #require(tree.nodes.first { tree.promotedSourceInsightID(forNodeID: $0.id) == source.id })
        let children = tree.attachedInsights(for: node)
        #expect(children.count == 3)
        let bookmarks = tree.makeNodeBookmarkConcepts(for: source.id)
        _ = tree.automaticNodeBookmarks()
        let removed = tree.removeBookmarkedNode(id: node.id, deletingInsights: deleting)
        #expect(removed.count == (deleting ? 4 : 1))
        let reopened = InsightTreeViewModel(insights: bookmarks, promotedInsightIDs: [source.id], model: MockAngroveModel(),
            embeddingProvider: MidpointTestEmbeddingProvider(), midpointStoreScope: scope)
        await reopened.prepareSemanticTree()
        #expect(!reopened.nodes.contains { $0.id == node.id })
        let members = reopened.nodes.flatMap(\.insights).map(\.id)
        #expect(Set(members) == (deleting ? [] : Set(children.map(\.id))))
        #expect(members.count == (deleting ? 0 : 3))
    }

    @MainActor
    @Test("Response seeds bookmark before the tree opens and stay removed")
    func responseSeedBookmark() async throws {
        let scope = UUID()
        let seed = LocalInsightTreeSeed(id: UUID(), label: "A Subject", summary: "A subject definition.",
            embedding: [1, 0], embeddingVersion: "midpoint-test.v1", createdAt: Date())
        let bookmark = try #require(InsightTreeViewModel.bookmarkSeed(seed, scope: scope))
        #expect(InsightTreeViewModel.nodeBookmarkReference(for: bookmark.id, preferredScope: scope)?.nodeID == seed.id)
        let tree = InsightTreeViewModel(insights: [bookmark], model: MockAngroveModel(),
            embeddingProvider: MidpointTestEmbeddingProvider(), localSeedAnchors: [seed], midpointStoreScope: scope)
        await tree.prepareSemanticTree()
        #expect(tree.nodes.first?.id == seed.id)
        #expect(tree.nodes.flatMap(\.insights).isEmpty)
        _ = tree.removeBookmarkedNode(id: seed.id, deletingInsights: false)
        #expect(InsightTreeViewModel.bookmarkSeed(seed, scope: scope) == nil)
    }

    @MainActor
    @Test("Retained Insights choose relevance among nearby concepts rather than the closest label")
    func relevantNearbyReattachment() async throws {
        let source = makeConcept(word: "First")
        let vectors: [[Double]] = [[1, 0, 0], [0, 1, 0], [0.5, 0, 0.8660254], [-1, 0, 0], [0.62, 0, -0.7846018]]
        let seeds = vectors.enumerated().map { index, vector in
            LocalInsightTreeSeed(id: UUID(), label: "Subject \(index)", summary: "", embedding: vector,
                embeddingVersion: "reattachment-test.v1", createdAt: Date())
        }
        let scope = UUID()
        let tree = InsightTreeViewModel(insights: [source], model: MockAngroveModel(),
            embeddingProvider: ReattachmentEmbeddingProvider(), localSeedAnchors: seeds, midpointStoreScope: scope)
        await tree.prepareSemanticTree()
        #expect(tree.nodes.count == 5)
        tree.commitLivePositions(Dictionary(uniqueKeysWithValues: seeds.enumerated().map {
            ($0.element.id, CGPoint(x: $0.offset * 100, y: 0))
        }))
        _ = tree.automaticNodeBookmarks()
        _ = tree.removeBookmarkedNode(id: seeds[0].id, deletingInsights: false)
        #expect(tree.nodes.first { $0.id == seeds[2].id }?.insights.map(\.id) == [source.id])
        #expect(tree.nodes.first { $0.id == seeds[1].id }?.insights.isEmpty == true)
        #expect(tree.nodes.first { $0.id == seeds[4].id }?.insights.isEmpty == true)
        #expect(tree.nodes.flatMap(\.insights).count == 1)
    }

    @MainActor
    @Test("Midpoint becomes a Node Concept and transfers each Insight exactly once across reloads")
    func midpointTransfersOwnership() async throws {
        let scope = UUID()
        let sources = [makeConcept(word: "First"), makeConcept(word: "Second")]
        let provider = MidpointTestEmbeddingProvider()
        let tree = InsightTreeViewModel(insights: sources, model: MockAngroveModel(),
            embeddingProvider: provider, midpointStoreScope: scope)
        await tree.prepareSemanticTree()
        let originalParents = tree.nodes.map(\.id)
        let loading = makeConcept(word: "")
        tree.addPlacedMidpoint(concept: loading, at: .zero,
            sources: sources.map { MidpointSource(insightID: $0.id, isNode: false) })
        try await tree.replacePlacedMidpoint(id: loading.id, with: makeConcept(word: "Combined"))
        let node = try #require(tree.nodes.first { $0.id == loading.id })
        #expect(node.isMidpointConcept)
        #expect(node.definition == makeConcept().semanticDefinition)
        #expect(Set(node.insights.map(\.id)) == Set(sources.map(\.id)))
        #expect(!node.insights.contains { $0.id == loading.id })
        for insight in node.insights {
            #expect(tree.nodes.filter { $0.insights.contains { $0.id == insight.id } }.count == 1)
            #expect(insight.distanceToNode == semanticDistance(insight.embedding!, node.embedding))
            #expect(tree.insightBondLengths[insight.id] != nil)
        }
        #expect(!originalParents.contains(node.id))
        #expect(Set(originalParents).isSubset(of: Set(tree.nodes.map(\.id))))
        for parentID in originalParents {
            #expect(tree.edges.filter {
                ($0.fromNodeID == parentID && $0.toNodeID == node.id)
                    || ($0.fromNodeID == node.id && $0.toNodeID == parentID)
            }.count == 1)
        }
        let reopened = InsightTreeViewModel(insights: sources, model: MockAngroveModel(),
            embeddingProvider: provider, midpointStoreScope: scope)
        await reopened.prepareSemanticTree()
        #expect(reopened.nodes.first { $0.id == node.id }?.insights.map(\.id) == node.insights.map(\.id))

        for parentID in originalParents {
            #expect(reopened.edges.contains {
                ($0.fromNodeID == parentID && $0.toNodeID == node.id)
                    || ($0.fromNodeID == node.id && $0.toNodeID == parentID)
            })
        }

        // Reusing one source in another blend transfers it out of the first concept too.
        let next = makeConcept(word: "")
        reopened.addPlacedMidpoint(concept: next, at: .zero,
            sources: [MidpointSource(insightID: sources[0].id, isNode: false)])
        try await reopened.replacePlacedMidpoint(id: next.id, with: makeConcept(word: "Combined"))
        #expect(reopened.nodes.first { $0.id == node.id }?.insights.map(\.id) == [sources[1].id])
        #expect(reopened.nodes.first { $0.id == next.id }?.insights.map(\.id) == [sources[0].id])
        #expect(reopened.edges.contains {
            ($0.fromNodeID == node.id && $0.toNodeID == next.id)
                || ($0.fromNodeID == next.id && $0.toNodeID == node.id)
        })
        reopened.removePlacedMidpoint(id: next.id)
        #expect(reopened.nodes.first { $0.id == node.id }?.insights.count == 2)
    }

    @MainActor
    @Test("Embedding failure does not commit source transfers")
    func midpointEmbeddingFailure() async {
        let source = makeConcept(word: "First")
        let tree = InsightTreeViewModel(insights: [source], model: MockAngroveModel(),
            embeddingProvider: MidpointTestEmbeddingProvider(), midpointStoreScope: UUID())
        await tree.prepareSemanticTree()
        let owner = tree.nodes.first { $0.insights.contains { $0.id == source.id } }?.id
        let loading = makeConcept(word: "")
        tree.addPlacedMidpoint(concept: loading, at: .zero,
            sources: [MidpointSource(insightID: source.id, isNode: false)])
        do {
            try await tree.replacePlacedMidpoint(id: loading.id, with: makeConcept(word: "Unavailable"))
            Issue.record("Missing embedding should reject the Midpoint")
        } catch {
            tree.removePlacedMidpoint(id: loading.id)
        }
        #expect(tree.nodes.first { $0.insights.contains { $0.id == source.id } }?.id == owner)
        #expect(!tree.nodes.contains { $0.id == loading.id })
    }


    @MainActor
    @Test("Midpoint transfer works in global and conversation scopes", arguments: [false, true])
    func midpointScopesAndNodeSources(conversation: Bool) async throws {
        let scope: UUID? = conversation ? UUID() : nil
        let sources = (0..<7).map { makeConcept(word: "Source \($0)") }
        let provider = MidpointTestEmbeddingProvider()
        let tree = InsightTreeViewModel(insights: sources, model: MockAngroveModel(),
            embeddingProvider: provider, midpointStoreScope: scope)
        await tree.prepareSemanticTree()
        let parent = try #require(tree.nodes.first)
        let loading = makeConcept(word: "")
        defer { tree.removePlacedMidpoint(id: loading.id) }
        tree.addPlacedMidpoint(concept: loading, at: .zero,
            sources: sources.map { MidpointSource(insightID: $0.id, isNode: false) }
                + [MidpointSource(insightID: parent.id, isNode: true)])
        try await tree.replacePlacedMidpoint(id: loading.id, with: makeConcept(word: "Combined"))
        #expect(tree.nodes.first { $0.id == loading.id }?.insights.count == 7)
        #expect(tree.edges.contains { $0.fromNodeID == parent.id && $0.toNodeID == loading.id })
        let restored = InsightTreeViewModel(insights: sources, model: MockAngroveModel(),
            embeddingProvider: provider, midpointStoreScope: scope)
        await restored.prepareSemanticTree()
        #expect(restored.nodes.first { $0.id == loading.id }?.insights.count == 7)
        #expect(restored.nodes.filter { $0.id != loading.id }.allSatisfy { $0.insights.isEmpty })
    }

    // MARK: - GlobalInsightPromotedIDsStore

    @Test("A Make Node promotion on the Global tree survives being reloaded")
    func globalPromotedIDsRoundTrip() {
        let original = GlobalInsightPromotedIDsStore.load()
        defer { GlobalInsightPromotedIDsStore.save(original) }

        let promoted = [UUID(), UUID()]
        GlobalInsightPromotedIDsStore.save(promoted)

        #expect(GlobalInsightPromotedIDsStore.load() == promoted)
    }

    @Test("With nothing ever saved, the store reads back empty rather than crashing")
    func globalPromotedIDsDefaultsToEmpty() {
        let original = GlobalInsightPromotedIDsStore.load()
        defer { GlobalInsightPromotedIDsStore.save(original) }

        GlobalInsightPromotedIDsStore.save([])

        #expect(GlobalInsightPromotedIDsStore.load().isEmpty)
    }

    // MARK: - Placed Midpoints (InsightTreeViewModel)

    @MainActor
    @Test("A placed Midpoint survives the view model being torn down and recreated")
    func placedMidpointSurvivesRecreation() {
        let scope = UUID()
        let midpoint = makeConcept(word: "Being")
        let source = MidpointSource(insightID: UUID(), isNode: false)

        let firstLoad = InsightTreeViewModel(
            insights: [],
            model: MockAngroveModel(),
            midpointStoreScope: scope
        )
        firstLoad.addPlacedMidpoint(concept: midpoint, at: CGPoint(x: 40, y: 20), sources: [source])

        // Simulates navigating away and back: a brand-new instance, same conversation scope.
        let secondLoad = InsightTreeViewModel(
            insights: [],
            model: MockAngroveModel(),
            midpointStoreScope: scope
        )

        #expect(secondLoad.placedMidpointNodeIDs.contains(midpoint.id))
        #expect(secondLoad.placedMidpointConcept(for: midpoint.id)?.word == "Being")
    }

    @MainActor
    @Test("Removing a placed Midpoint persists, rather than reappearing on the next load")
    func removedPlacedMidpointStaysRemoved() {
        let scope = UUID()
        let midpoint = makeConcept(word: "Act")
        let source = MidpointSource(insightID: UUID(), isNode: false)

        let firstLoad = InsightTreeViewModel(
            insights: [],
            model: MockAngroveModel(),
            midpointStoreScope: scope
        )
        firstLoad.addPlacedMidpoint(concept: midpoint, at: .zero, sources: [source])
        firstLoad.removePlacedMidpoint(id: midpoint.id)

        let secondLoad = InsightTreeViewModel(
            insights: [],
            model: MockAngroveModel(),
            midpointStoreScope: scope
        )

        #expect(!secondLoad.placedMidpointNodeIDs.contains(midpoint.id))
    }

    @MainActor
    @Test("A Midpoint placed in one conversation's tree does not leak into another's")
    func placedMidpointsAreScopedPerConversation() {
        let scopeA = UUID()
        let scopeB = UUID()
        let midpoint = makeConcept(word: "Potency")
        let source = MidpointSource(insightID: UUID(), isNode: false)

        let treeA = InsightTreeViewModel(
            insights: [],
            model: MockAngroveModel(),
            midpointStoreScope: scopeA
        )
        treeA.addPlacedMidpoint(concept: midpoint, at: .zero, sources: [source])

        let treeB = InsightTreeViewModel(
            insights: [],
            model: MockAngroveModel(),
            midpointStoreScope: scopeB
        )

        #expect(!treeB.placedMidpointNodeIDs.contains(midpoint.id))
    }

    // MARK: - Make Node bookmarks

    @MainActor
    @Test("Make Node exposes bookmark records and removes an unbookmarked child")
    func makeNodeBookmarkLifecycle() async throws {
        let source = makeConcept(word: "Prudence")
        let tree = InsightTreeViewModel(
            insights: [source],
            model: MockAngroveModel(),
            midpointStoreScope: UUID()
        )

        tree.reserveMakeNodeGeneration(for: source.id)
        let sourceInsight = InsightModel(concept: source)
        try await tree.generateReservedMakeNodeChildren(for: sourceInsight)

        let bookmarks = tree.makeNodeBookmarkConcepts(for: source.id)
        #expect(bookmarks.count == 4)
        #expect(bookmarks.first?.id == source.id)
        #expect(Set(bookmarks.dropFirst().map(\.id)).isSubset(of: tree.generatedMakeNodeChildIDs))

        let removedChildID = try #require(bookmarks.dropFirst().first?.id)
        tree.removeMakeNodeChild(id: removedChildID)

        #expect(!tree.generatedMakeNodeChildIDs.contains(removedChildID))
        #expect(!tree.nodes.flatMap(\.insights).contains(where: { $0.id == removedChildID }))
    }

    @MainActor
    @Test("Keeping attached Insights rehomes them under remaining Nodes")
    func keptMakeNodeInsightsAreRehomed() async throws {
        let source = makeConcept(word: "Prudence")
        let neighbor = makeConcept(word: "Moral Judgment")
        let tree = InsightTreeViewModel(
            insights: [source, neighbor],
            model: MockAngroveModel(),
            midpointStoreScope: UUID()
        )

        tree.reserveMakeNodeGeneration(for: source.id)
        try try await tree.generateReservedMakeNodeChildren(for: InsightModel(concept: source))
        let childBookmarks = Array(tree.makeNodeBookmarkConcepts(for: source.id).dropFirst())
        tree.updateInsights(
            [source, neighbor] + childBookmarks,
            promotedInsightIDs: [source.id]
        )
        let remainingNodeIDs = Set(tree.nodes.compactMap { node in
            tree.promotedSourceInsightID(forNodeID: node.id) == nil && !node.insights.isEmpty
                ? node.id
                : nil
        })

        tree.removeMakeNode(for: source.id, keepingChildren: true)
        tree.updateInsights(
            [neighbor] + childBookmarks,
            promotedInsightIDs: []
        )

        for child in childBookmarks {
            let ownerID = tree.nodes.first(where: {
                $0.insights.contains(where: { $0.id == child.id })
            })?.id
            #expect(ownerID.map(remainingNodeIDs.contains) == true)
        }
    }
}

private struct MidpointTestEmbeddingProvider: EmbeddingProvider {
    var version: String { "midpoint-test.v1" }
    func embed(_ text: String) async -> [Double]? {
        if text.hasPrefix("Unavailable.") { return nil }
        if text.hasPrefix("Combined.") { return [0.6, 0.8] }
        if text.hasPrefix("Second.") { return [0.8, 0.6] }
        return [1, 0]
    }
}

private struct ReattachmentEmbeddingProvider: EmbeddingProvider {
    var version: String { "reattachment-test.v1" }
    func embed(_ text: String) async -> [Double]? { [1, 0, 0] }
}
