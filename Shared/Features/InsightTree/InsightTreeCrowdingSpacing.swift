import CoreGraphics
import Foundation

/// Uniformly expands concept anchors; Insight bond lengths and graph membership are untouched.
nonisolated struct InsightTreeCrowdingSpacing {
    static let collisionDwell: TimeInterval = 0.75
    static let expansionStep: CGFloat = 1.06
    static let maximumScale: CGFloat = 2
    private(set) var scale: CGFloat = 1
    private var collisionTime: TimeInterval = 0
    private var sourceTargets: [UUID: CGPoint] = [:]
    private var baseTargets: [UUID: CGPoint] = [:]
    private var origin: CGPoint = .zero

    mutating func synchronize(targets: [UUID: CGPoint]) {
        guard targets != sourceTargets else { return }
        if targets.isEmpty {
            self = Self()
            return
        }
        if !sourceTargets.isEmpty, Set(sourceTargets.keys).isDisjoint(with: targets.keys) {
            // A reused canvas can switch from the global tree to another conversation scope.
            self = Self()
        }
        if sourceTargets.isEmpty {
            origin = CGPoint(x: targets.values.reduce(0) { $0 + $1.x } / CGFloat(targets.count),
                             y: targets.values.reduce(0) { $0 + $1.y } / CGFloat(targets.count))
        }
        baseTargets = baseTargets.filter { targets[$0.key] != nil }
        for (id, point) in targets where sourceTargets[id] != point {
            // Updated/restored coordinates already represent the person's current placement.
            // Rebase them instead of applying the accumulated expansion a second time.
            baseTargets[id] = CGPoint(x: origin.x + (point.x - origin.x) / scale,
                                      y: origin.y + (point.y - origin.y) / scale)
        }
        collisionTime = 0
        sourceTargets = targets
    }

    func target(for id: UUID) -> CGPoint? {
        guard let point = baseTargets[id] else { return nil }
        return CGPoint(x: origin.x + (point.x - origin.x) * scale,
                       y: origin.y + (point.y - origin.y) * scale)
    }

    mutating func advance(colliding: Bool, canExpand: Bool, elapsed: TimeInterval) -> Bool {
        guard colliding, canExpand, scale < Self.maximumScale else {
            collisionTime = 0
            return false
        }
        collisionTime += min(max(elapsed, 0), 1.0 / 30)
        guard collisionTime >= Self.collisionDwell else { return false }
        collisionTime = 0
        scale = min(scale * Self.expansionStep, Self.maximumScale)
        return true
    }

    struct Footprint {
        let nodeID: UUID
        let rectangle: CGRect
    }

    static func hasCrossClusterCollision(_ footprints: [Footprint]) -> Bool {
        let rectangles = footprints.map(\.rectangle)
        return SpatialCollisionIndex.pairs(for: rectangles).contains { pair in
            footprints[pair.first].nodeID != footprints[pair.second].nodeID
                && rectangles[pair.first].intersects(rectangles[pair.second])
        }
    }
}
