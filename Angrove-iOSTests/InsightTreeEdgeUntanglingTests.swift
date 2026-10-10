import CoreGraphics
import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Insight Tree connector untangling")
struct InsightTreeEdgeUntanglingTests {
    private let root = UUID(), branch = UUID(), leaf = UUID(), crossingLeaf = UUID()

    /// root→branch→crossingLeaf runs straight through the root→leaf connector.
    private var crossed: [UUID: CGPoint] {
        [root: .zero, branch: CGPoint(x: 400, y: 0), leaf: CGPoint(x: 0, y: 400),
         crossingLeaf: CGPoint(x: -100, y: 300)]
    }
    private var edges: [(UUID, UUID)] { [(root, branch), (root, leaf), (branch, crossingLeaf)] }
    private var bonds: [InsightTreeEdgeUntangling.Bond] {
        edges.map { $0.0.uuidString < $0.1.uuidString ? .init(a: $0.0, b: $0.1) : .init(a: $0.1, b: $0.0) }
    }
    private func smallRadii(_ positions: [UUID: CGPoint]) -> [UUID: CGFloat] { positions.mapValues { _ in 10 } }

    @Test("A crossing branch turns clear while every connector keeps its length")
    func removesCrossing() {
        #expect(InsightTreeEdgeUntangling.crossingCount(bonds, crossed) == 1)
        let result = InsightTreeEdgeUntangling.untangle(positions: crossed, edges: edges, pinned: [], radii: smallRadii(crossed))
        #expect(InsightTreeEdgeUntangling.crossingCount(bonds, result) == 0)
        for (a, b) in edges {
            let before = hypot(crossed[a]!.x - crossed[b]!.x, crossed[a]!.y - crossed[b]!.y)
            let after = hypot(result[a]!.x - result[b]!.x, result[a]!.y - result[b]!.y)
            #expect(abs(before - after) < 0.001)
        }
    }

    @Test("A clear layout is left exactly where it is")
    func clearLayoutStill() {
        var clear = crossed
        clear[crossingLeaf] = CGPoint(x: 600, y: -200)
        let result = InsightTreeEdgeUntangling.untangle(positions: clear, edges: edges, pinned: [], radii: smallRadii(clear))
        #expect(result == clear)
    }

    @Test("Pinned Midpoints never move, even to clear a crossing")
    func pinnedStay() {
        let result = InsightTreeEdgeUntangling.untangle(positions: crossed, edges: edges,
            pinned: [crossingLeaf, leaf], radii: smallRadii(crossed))
        #expect(result[crossingLeaf] == crossed[crossingLeaf])
        #expect(result[leaf] == crossed[leaf])
    }

    @Test("A tangled random tree loses crossings without gaining footprint overlaps")
    func randomTree() {
        var seed: UInt64 = 0x5EED
        func next() -> CGFloat {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat(seed >> 33) / CGFloat(UInt64(1) << 31)
        }
        let ids = (0..<24).map { _ in UUID() }
        let positions = Dictionary(uniqueKeysWithValues: ids.map { ($0, CGPoint(x: next() * 3_000, y: next() * 3_000)) })
        let edges = (1..<ids.count).map { (ids[Int(next() * CGFloat($0))], ids[$0]) }
        let bonds = edges.map { $0.0.uuidString < $0.1.uuidString
            ? InsightTreeEdgeUntangling.Bond(a: $0.0, b: $0.1) : .init(a: $0.1, b: $0.0) }
        let radii = positions.mapValues { _ in CGFloat(60) }
        func overlaps(_ p: [UUID: CGPoint]) -> Int {
            var count = 0
            for i in ids.indices { for j in (i + 1)..<ids.count
                where hypot(p[ids[i]]!.x - p[ids[j]]!.x, p[ids[i]]!.y - p[ids[j]]!.y) < 120 * InsightTreeEdgeUntangling.coreClearance { count += 1 } }
            return count
        }
        let before = InsightTreeEdgeUntangling.crossingCount(bonds, positions)
        let result = InsightTreeEdgeUntangling.untangle(positions: positions, edges: edges, pinned: [], radii: radii)
        let after = InsightTreeEdgeUntangling.crossingCount(bonds, result)
        #expect(before > 0)
        #expect(after < before)
        #expect(overlaps(result) <= overlaps(positions))
    }

    @Test("A node on a loop swings alone when no branch can turn")
    func loopNode() {
        // Square loop a-b-c-d with a tail from c that crosses a–b.
        let a = UUID(), b = UUID(), c = UUID(), d = UUID(), tail = UUID()
        let positions: [UUID: CGPoint] = [a: .zero, b: CGPoint(x: 400, y: 0), c: CGPoint(x: 400, y: 400),
                                          d: CGPoint(x: 0, y: 400), tail: CGPoint(x: 200, y: -200)]
        let edges = [(a, b), (b, c), (c, d), (d, a), (c, tail)]
        let bonds = edges.map { $0.0.uuidString < $0.1.uuidString
            ? InsightTreeEdgeUntangling.Bond(a: $0.0, b: $0.1) : .init(a: $0.1, b: $0.0) }
        #expect(InsightTreeEdgeUntangling.crossingCount(bonds, positions) > 0)
        let result = InsightTreeEdgeUntangling.untangle(positions: positions, edges: edges,
            pinned: [tail, c], radii: positions.mapValues { _ in 10 })
        #expect(InsightTreeEdgeUntangling.crossingCount(bonds, result) == 0)
    }

    @Test("A far-flung branch slides back to its semantic length, keeping its shape")
    func tightensStretchedBond() {
        // The hub's side is larger, so the far branch is the one that moves.
        let hub = UUID(), far = UUID(), farChild = UUID(), near = UUID(), nearTwo = UUID()
        let positions: [UUID: CGPoint] = [hub: .zero, near: CGPoint(x: -400, y: 0), nearTwo: CGPoint(x: 0, y: -400),
            far: CGPoint(x: 2_000, y: 0), farChild: CGPoint(x: 2_000, y: 400)]
        let edges = [(hub, near), (hub, nearTwo), (hub, far), (far, farChild)]
        let lengths: [InsightTreeEdgeUntangling.Bond: CGFloat] = [.between(hub, near): 400,
            .between(hub, nearTwo): 400, .between(hub, far): 500, .between(far, farChild): 400]
        let result = InsightTreeEdgeUntangling.untangle(positions: positions, edges: edges, pinned: [],
            radii: positions.mapValues { _ in 10 }, lengths: lengths)
        #expect(abs(hypot(result[far]!.x - result[hub]!.x, result[far]!.y - result[hub]!.y) - 500) < 0.001)
        #expect(result[farChild]!.x - result[far]!.x == 0 && result[farChild]!.y - result[far]!.y == 400)
        #expect(result[near] == positions[near])
    }
}
