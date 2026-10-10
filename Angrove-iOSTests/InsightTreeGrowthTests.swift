import CoreGraphics
import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Insight Tree growth")
struct InsightTreeGrowthTests {
    /// A unit vector in `dimension` dimensions, `weight` along `axis` and the rest along axis 0.
    private func vector(_ axis: Int, _ weight: Double, dimension: Int = 8) -> [Double] {
        var values = [Double](repeating: 0, count: dimension)
        values[0] = (1 - weight * weight).squareRoot()
        values[axis] += weight
        return values
    }

    @Test("A cohesive group of loose members buds; tight members stay")
    func budsCohesiveLooseGroup() throws {
        let anchor = vector(0, 0)
        let tight = (0..<3).map { _ in InsightTreeGrowth.Member(id: UUID(), vector: vector(1, 0.3)) }
        let loose = (0..<3).map { index in
            InsightTreeGrowth.Member(id: UUID(), vector: vector(2, 0.95 + Double(index) * 0.01))
        }
        let group = try #require(InsightTreeGrowth.budGroup(members: tight + loose, anchor: anchor))
        #expect(Set(group) == Set(loose.map(\.id)))
    }

    @Test("Loose members that are unrelated to each other do not bud")
    func scatteredLooseMembersStay() {
        let anchor = vector(0, 0)
        let loose = (2..<5).map { InsightTreeGrowth.Member(id: UUID(), vector: vector($0, 0.95)) }
        #expect(InsightTreeGrowth.budGroup(members: loose, anchor: anchor) == nil)
    }

    @Test("Fewer than the minimum loose members never bud")
    func tooFewToBud() {
        let anchor = vector(0, 0)
        let loose = (0..<2).map { _ in InsightTreeGrowth.Member(id: UUID(), vector: vector(2, 0.95)) }
        #expect(InsightTreeGrowth.budGroup(members: loose, anchor: anchor) == nil)
    }

    private func node(_ id: UUID, _ vector: [Double], parents: [UUID] = [], at point: CGPoint? = nil) -> InsightTreeGrowth.Node {
        .init(id: id, vector: vector, fixedParents: parents, restoredPosition: point, radius: 100, leansToward: [])
    }

    @Test("Each concept joins its most similar subject, and lines never cross")
    func parentsBySubject() {
        let ethics = UUID(), aristotle = UUID(), sacraments = UUID(), eucharist = UUID()
        let nodes = [node(ethics, vector(1, 0.9)), node(aristotle, vector(1, 0.8)),
                     node(sacraments, vector(2, 0.9)), node(eucharist, vector(2, 0.85))]
        let grown = InsightTreeGrowth.grow(nodes, relayout: true)
        #expect(grown.parents.count == 3)
        let pairs = Set(grown.parents.map { Set([$0.key, $0.value]) })
        #expect(pairs.contains([ethics, aristotle]))
        #expect(pairs.contains([sacraments, eucharist]))
        let bonds = grown.parents.map { InsightTreeEdgeUntangling.Bond.between($0.key, $0.value) }
        #expect(InsightTreeEdgeUntangling.crossingCount(bonds, grown.positions) == 0)
    }

    @Test("Saved parents are kept even when another concept is now more similar")
    func savedParentsStick() {
        let root = UUID(), child = UUID(), lookalike = UUID()
        let nodes = [node(root, vector(1, 0.2)), node(lookalike, vector(3, 0.99), parents: [root]),
                     node(child, vector(3, 0.98), parents: [root])]
        let grown = InsightTreeGrowth.grow(nodes, relayout: false)
        #expect(grown.parents[child] == root)
    }

    @Test("Existing positions stay put; only a new concept is placed, off its parent")
    func placesOnlyNewConcepts() throws {
        let root = UUID(), old = UUID(), new = UUID()
        let nodes = [node(root, vector(1, 0.5), at: .zero), node(old, vector(1, 0.6), parents: [root], at: CGPoint(x: 700, y: 0)),
                     node(new, vector(1, 0.55))]
        let grown = InsightTreeGrowth.grow(nodes, relayout: false)
        #expect(grown.positions[root] == .zero)
        #expect(grown.positions[old] == CGPoint(x: 700, y: 0))
        #expect(grown.placed == [new])
        let parentID = try #require(grown.parents[new])
        let parent = try #require(grown.positions[parentID])
        let point = try #require(grown.positions[new])
        #expect(hypot(point.x - parent.x, point.y - parent.y) >= nodeNodeMinLength)
    }

    @Test("A concept without a vector yet never saves a parent")
    func noVectorNoSavedParent() {
        let root = UUID(), pending = UUID()
        let grown = InsightTreeGrowth.grow([node(root, vector(1, 0.5)), node(pending, [])], relayout: false)
        #expect(grown.parents[pending] == root)
        #expect(grown.persistableParents[pending] == nil)
    }

    @Test("Stored parent cycles are broken rather than looping")
    func storedCycleBreaks() {
        let a = UUID(), b = UUID()
        let grown = InsightTreeGrowth.grow([node(a, vector(1, 0.5), parents: [b]), node(b, vector(1, 0.6), parents: [a])],
                                           relayout: true)
        #expect(grown.parents.count == 1)
        #expect(grown.positions.count == 2)
    }

    @Test("A Midpoint's line to its second source, in another branch, crosses nothing")
    func midpointSecondaryLineClear() {
        let root = UUID(), a = UUID(), b = UUID(), a1 = UUID(), a2 = UUID(), b1 = UUID(), b2 = UUID(), midpoint = UUID()
        let nodes = [
            node(root, vector(1, 0.1)), node(a, vector(2, 0.6)), node(b, vector(3, 0.6)),
            node(a1, vector(2, 0.8)), node(a2, vector(2, 0.85)), node(b1, vector(3, 0.8)), node(b2, vector(3, 0.85)),
            InsightTreeGrowth.Node(id: midpoint, vector: vector(4, 0.5), fixedParents: [a1, b1], restoredPosition: nil,
                                   radius: 100, leansToward: [a1, b1]),
        ]
        let grown = InsightTreeGrowth.grow(nodes, relayout: true)
        var bonds = grown.parents.map { InsightTreeEdgeUntangling.Bond.between($0.key, $0.value) }
        let treeParent = grown.parents[midpoint]
        for source in [a1, b1] where source != treeParent { bonds.append(.between(midpoint, source)) }
        #expect(InsightTreeEdgeUntangling.crossingCount(bonds, grown.positions) == 0)
    }
}
