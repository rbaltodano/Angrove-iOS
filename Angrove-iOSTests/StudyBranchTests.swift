import CoreGraphics
import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Study Branch")
struct StudyBranchTests {
    private func concept() -> ConceptDefinition {
        ConceptDefinition(word: "Prudence", partOfSpeech: "", pronunciation: "",
                          meaning: "Reason applied to practical judgment.", example: "")
    }

    @MainActor
    @Test("Every Branch count retains the old parent and persists the complete batch", arguments: 2...6)
    func branchCountsAndPersistence(count: Int) async throws {
        let source = concept()
        let scope = UUID()
        let tree = InsightTreeViewModel(insights: [source], model: MockAngroveModel(), midpointStoreScope: scope)
        let parent = try #require(tree.nodes.first { $0.insights.contains { $0.id == source.id } })
        tree.reserveMakeNodeGeneration(for: source.id, branchCount: count)
        let promotedID = tree.promotedNodeID(for: source.id)
        let loadingNode = try #require(tree.nodes.first { $0.id == promotedID })
        #expect(loadingNode.conceptLabel == source.word)
        #expect(loadingNode.insights.count == count)
        #expect(loadingNode.insights.allSatisfy { $0.title.isEmpty })
        #expect(tree.generatedMakeNodeChildIDs.isEmpty)
        #expect(tree.edges.contains {
            Set([$0.fromNodeID, $0.toNodeID]) == Set([parent.id, promotedID])
        })

        try await tree.generateReservedMakeNodeChildren(for: InsightModel(concept: source))
        let bookmarks = tree.makeNodeBookmarkConcepts(for: source.id)
        #expect(bookmarks.count == count + 1)
        // The promoted Node keeps the source bookmark identity instead of becoming unsaved.
        #expect(bookmarks.first?.id == source.id)
        #expect(tree.promotedSourceInsightID(forNodeID: promotedID) == source.id)
        #expect(Set(bookmarks.dropFirst().map(\.id)).count == count)
        #expect(Set(bookmarks.dropFirst().map(\.id)) == tree.generatedMakeNodeChildIDs)

        tree.updateInsights([source] + Array(bookmarks.dropFirst()), promotedInsightIDs: [source.id])
        #expect(tree.makeNodeChildIDs.count == count)
        let restored = InsightTreeViewModel(insights: [source] + Array(bookmarks.dropFirst()),
            promotedInsightIDs: [source.id], model: MockAngroveModel(), midpointStoreScope: scope)
        let node = try #require(restored.nodes.first { $0.id == promotedID })
        #expect(node.conceptLabel == source.word)
        #expect(node.insights.map(\.id) == bookmarks.dropFirst().map(\.id))
        #expect(restored.generatedMakeNodeChildIDs.count == count)
        #expect(restored.edges.contains {
            Set([$0.fromNodeID, $0.toNodeID]) == Set([parent.id, promotedID])
        })
    }

    @MainActor
    @Test("Rollback restores the original Insight and removes all six placeholders")
    func rollback() {
        let source = concept()
        let tree = InsightTreeViewModel(insights: [source], model: MockAngroveModel(), midpointStoreScope: UUID())
        tree.reserveMakeNodeGeneration(for: source.id, branchCount: 6)
        tree.cancelMakeNodeGeneration(for: source.id)
        #expect(!tree.nodes.contains { $0.id == tree.promotedNodeID(for: source.id) })
        #expect(tree.nodes.flatMap(\.insights).contains { $0.id == source.id })
        #expect(tree.makeNodeChildIDs.isEmpty)
        #expect(tree.generatedMakeNodeChildIDs.isEmpty)
    }

    @MainActor
    @Test("Out-of-range counts do not promote the Insight", arguments: [1, 7])
    func invalidCount(count: Int) {
        let source = concept()
        let tree = InsightTreeViewModel(insights: [source], model: MockAngroveModel(), midpointStoreScope: UUID())
        tree.reserveMakeNodeGeneration(for: source.id, branchCount: count)
        #expect(tree.makeNodeChildIDs.isEmpty)
        #expect(tree.nodes.flatMap(\.insights).contains { $0.id == source.id })
    }
    @MainActor
    @Test("A placed midpoint can Branch while retaining its source parent")
    func midpointBranch() async throws {
        let source = concept()
        let midpoint = ConceptDefinition(word: "Practical Reason", partOfSpeech: "", pronunciation: "",
                                          meaning: "Reason directing action.", example: "")
        let scope = UUID()
        let tree = InsightTreeViewModel(insights: [source], model: MockAngroveModel(), midpointStoreScope: scope)
        let parentID = try #require(tree.nodes.first?.id)
        tree.addPlacedMidpoint(concept: midpoint, at: .zero,
                              sources: [MidpointSource(insightID: source.id, isNode: false)])
        tree.reserveMakeNodeGeneration(for: midpoint.id, branchCount: 6)
        try await tree.generateReservedMakeNodeChildren(for: InsightModel(concept: midpoint))
        let promotedID = tree.promotedNodeID(for: midpoint.id)
        #expect(tree.makeNodeBookmarkConcepts(for: midpoint.id).count == 7)
        #expect(!tree.nodes.contains { $0.id == midpoint.id })
        #expect(tree.edges.contains { Set([$0.fromNodeID, $0.toNodeID]) == Set([parentID, promotedID]) })
        let restored = InsightTreeViewModel(insights: [source], promotedInsightIDs: [midpoint.id],
                                           model: MockAngroveModel(), midpointStoreScope: scope)
        #expect(restored.nodes.first { $0.id == promotedID }?.insights.count == 6)
        tree.cancelMakeNodeGeneration(for: midpoint.id)
        #expect(tree.nodes.contains { $0.id == midpoint.id })
    }

    @MainActor
    @Test("Unavailable generation does not commit partial Branch output")
    func unavailableGeneration() async throws {
        let source = concept()
        let tree = InsightTreeViewModel(insights: [source], model: UnavailableAngroveModel(), midpointStoreScope: UUID())
        tree.reserveMakeNodeGeneration(for: source.id, branchCount: 6)
        await #expect(throws: AngroveModelActionError.self) {
            try await tree.generateReservedMakeNodeChildren(for: InsightModel(concept: source))
        }
        #expect(tree.generatedMakeNodeChildIDs.isEmpty)
        tree.cancelMakeNodeGeneration(for: source.id)
        #expect(tree.nodes.flatMap(\.insights).contains { $0.id == source.id })
    }

    @MainActor
    @Test("Branch hands children, their connectors, and the parent edge to the normal renderer")
    func finishedConnectors() {
        let state = InsightTreeRevealState()
        let childIDs: Set<UUID> = [UUID(), UUID()]
        let nodeIDs: Set<UUID> = [UUID(), UUID()]
        state.completeBranch(childIDs: childIDs, nodeIDs: nodeIDs, graphEdgeIDs: ["parent-to-branch"])
        #expect(state.revealedInsightIDs == childIDs)
        #expect(state.revealedInsightConnectorIDs == childIDs)
        #expect(state.revealedNodeIDs == nodeIDs)
        #expect(state.revealedGraphEdgeIDs.contains("parent-to-branch"))
    }

    @MainActor
    @Test("Generated children have measured semantic bonds before readiness, including after reopening")
    func semanticChildBonds() async throws {
        let source = concept(), scope = UUID()
        let provider = BranchEmbeddingProvider()
        let tree = InsightTreeViewModel(insights: [source], model: MockAngroveModel(),
            embeddingProvider: provider, midpointStoreScope: scope)
        await tree.prepareSemanticTree()
        tree.reserveMakeNodeGeneration(for: source.id, branchCount: 3)
        try await tree.generateReservedMakeNodeChildren(for: InsightModel(concept: source))
        let nodeID = tree.promotedNodeID(for: source.id)
        let children = try #require(tree.nodes.first { $0.id == nodeID }?.insights)
        #expect(children.allSatisfy { $0.embeddingVersion == provider.version && $0.distanceToNode != nil })
        let lengths = try children.map { try #require(tree.insightBondLengths[$0.id]) }
        #expect(lengths[0] < lengths[1] && lengths[1] < lengths[2])
        let parentEdges = Set(tree.edges.map(\.id))
        let restored = InsightTreeViewModel(insights: [source], promotedInsightIDs: [source.id],
            model: MockAngroveModel(), embeddingProvider: provider, midpointStoreScope: scope)
        await restored.prepareSemanticTree()
        #expect(restored.insightBondLengths == tree.insightBondLengths)
        #expect(Set(restored.edges.map(\.id)) == parentEdges)
    }

    @Test("The burst uses the actual semantic bond radius rather than row spacing", arguments: 2...6)
    func semanticBurstLayout(count: Int) {
        for index in 0..<count {
            let radius = CGFloat(150 + index * 30)
            let point = StudyBranchAnimation.offset(index: index, count: count, bondLength: radius)
            #expect(abs(hypot(point.x, point.y) - radius) < 0.00001)
        }
        let extent = StudyBranchAnimation.extent(offsets: [CGPoint(x: 150, y: -300)],
            nodeHeight: 160, childSize: CGSize(width: 260, height: 60))
        #expect(extent.width >= 560 && extent.height >= 660)
    }
}

private struct BranchEmbeddingProvider: EmbeddingProvider {
    var version: String { "test.branch.relatedness.v1" }
    func embed(_ text: String) async -> [Double]? {
        if text.hasPrefix("Fundamental point 1") { return [0.99, 0.1] }
        if text.hasPrefix("Fundamental point 2") { return [0.8, 0.6] }
        if text.hasPrefix("Fundamental point 3") { return [0.4, 0.9] }
        return [1, 0]
    }
}
