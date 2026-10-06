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

    @Test("Long node titles leave every child unobstructed on a narrow phone", arguments: 2...6)
    func nonoverlappingLayout(count: Int) {
        let size = CGSize(width: 320, height: 420)
        let nodeHeight: CGFloat = 160
        let childHeight: CGFloat = 120
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let node = CGRect(x: center.x - 130, y: center.y - nodeHeight / 2, width: 260, height: nodeHeight)
        let childWidth: CGFloat = 260
        let columns = StudyBranchAnimation.columns(count: count, width: size.width, childWidth: childWidth)
        #expect(columns == 1)
        let frames = (0..<count).map { index in
            let point = StudyBranchAnimation.destination(index: index, count: count, size: size,
                                                         nodeHeight: nodeHeight, childHeight: childHeight, columns: columns)
            return CGRect(x: point.x - childWidth / 2, y: point.y - childHeight / 2,
                          width: childWidth, height: childHeight)
        }
        for (index, frame) in frames.enumerated() {
            #expect(!frame.intersects(node))
            for other in frames.dropFirst(index + 1) { #expect(!frame.intersects(other)) }
        }
    }

}
