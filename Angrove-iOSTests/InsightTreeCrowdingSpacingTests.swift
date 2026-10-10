import CoreGraphics
import Foundation
import Testing
@testable import Angrove_iOS

struct InsightTreeCrowdingSpacingTests {
    @Test func transientAndInteractionCollisionsDoNotExpand() {
        var spacing = InsightTreeCrowdingSpacing()
        for _ in 0..<30 { let expanded = spacing.advance(colliding: true, canExpand: true, elapsed: 1.0 / 60); #expect(!expanded) }
        let expanded = spacing.advance(colliding: false, canExpand: true, elapsed: 1.0 / 60); #expect(!expanded)
        for _ in 0..<30 { let expanded = spacing.advance(colliding: true, canExpand: true, elapsed: 1.0 / 60); #expect(!expanded) }
        for _ in 0..<100 { let expanded = spacing.advance(colliding: true, canExpand: false, elapsed: 1.0 / 60); #expect(!expanded) }
        #expect(spacing.scale == 1)
    }

    @Test func persistentCrowdingExpandsGraduallyAndStopsAtCap() {
        var spacing = InsightTreeCrowdingSpacing()
        var changes = 0
        for _ in 0..<1800 {
            let old = spacing.scale
            if spacing.advance(colliding: true, canExpand: true, elapsed: 1.0 / 60) {
                changes += 1
                #expect(spacing.scale <= old * InsightTreeCrowdingSpacing.expansionStep)
            }
        }
        #expect(changes > 1)
        #expect(spacing.scale == InsightTreeCrowdingSpacing.maximumScale)
        for _ in 0..<100 { let expanded = spacing.advance(colliding: true, canExpand: true, elapsed: 1.0 / 60); #expect(!expanded) }
        for _ in 0..<100 { _ = spacing.advance(colliding: false, canExpand: true, elapsed: 1.0 / 60) }
        #expect(spacing.scale == InsightTreeCrowdingSpacing.maximumScale)
    }

    @Test func everyConceptDistanceUsesOneScaleAndUpdatedPositionsDoNotDoubleExpand() throws {
        let ids = [UUID(), UUID(), UUID()]
        let points = [CGPoint(x: -100, y: 0), CGPoint(x: 0, y: 30), CGPoint(x: 200, y: -40)]
        let targets = Dictionary(uniqueKeysWithValues: zip(ids, points))
        var spacing = InsightTreeCrowdingSpacing()
        spacing.synchronize(targets: targets)
        for _ in 0..<100 { _ = spacing.advance(colliding: true, canExpand: true, elapsed: 1.0 / 60) }
        let expanded = try ids.map { try #require(spacing.target(for: $0)) }
        for i in 0..<points.count {
            for j in (i + 1)..<points.count {
                let before = hypot(points[i].x - points[j].x, points[i].y - points[j].y)
                let after = hypot(expanded[i].x - expanded[j].x, expanded[i].y - expanded[j].y)
                #expect(abs(after / before - spacing.scale) < 0.000001)
            }
        }
        let scale = spacing.scale
        spacing.synchronize(targets: Dictionary(uniqueKeysWithValues: zip(ids, expanded)))
        for (id, point) in zip(ids, expanded) {
            let target = try #require(spacing.target(for: id))
            #expect(hypot(target.x - point.x, target.y - point.y) < 0.000001)
        }
        #expect(spacing.scale == scale)
    }

    @Test func onlyDifferentClustersCountAsCrowding() {
        let first = UUID(), second = UUID()
        let rectangle = CGRect(x: 0, y: 0, width: 100, height: 30)
        let a = InsightTreeCrowdingSpacing.Footprint(nodeID: first, rectangle: rectangle)
        #expect(!InsightTreeCrowdingSpacing.hasCrossClusterCollision([a, a]))
        #expect(InsightTreeCrowdingSpacing.hasCrossClusterCollision([a, .init(nodeID: second, rectangle: rectangle)]))
        #expect(!InsightTreeCrowdingSpacing.hasCrossClusterCollision([a,
            .init(nodeID: second, rectangle: rectangle.offsetBy(dx: 200, dy: 0))]))
    }

    @Test func switchingTreeScopesStartsWithItsOwnSavedPlacement() throws {
        var spacing = InsightTreeCrowdingSpacing()
        spacing.synchronize(targets: [UUID(): CGPoint(x: -100, y: 0), UUID(): CGPoint(x: 100, y: 0)])
        for _ in 0..<100 { _ = spacing.advance(colliding: true, canExpand: true, elapsed: 1.0 / 60) }
        #expect(spacing.scale > 1)
        let id = UUID(), point = CGPoint(x: 700, y: 200)
        spacing.synchronize(targets: [id: point])
        #expect(spacing.scale == 1)
        #expect(spacing.target(for: id) == point)
    }

}
