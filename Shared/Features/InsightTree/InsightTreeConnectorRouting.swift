import CoreGraphics
import Foundation

/// Presentation-only routing: relationship endpoints and semantic lengths never change.
nonisolated enum InsightTreeConnectorRouting {
    struct Connector: Equatable {
        let id: String
        let start: CGPoint
        let end: CGPoint
        let fromNodeID: UUID
        let toNodeID: UUID
    }
    struct Obstacle {
        let ownerID: UUID
        let rect: CGRect
    }
    struct Route: Equatable {
        let connector: Connector
        var bend: CGFloat = 0
        var gaps: [ClosedRange<CGFloat>] = []
        var control: CGPoint {
            let dx = connector.end.x - connector.start.x
            let dy = connector.end.y - connector.start.y
            let length = max(hypot(dx, dy), 1)
            return CGPoint(x: (connector.start.x + connector.end.x) / 2 - dy / length * bend,
                           y: (connector.start.y + connector.end.y) / 2 + dx / length * bend)
        }
        func point(at t: CGFloat) -> CGPoint {
            let a = connector.start, b = connector.end, c = control, u = 1 - t
            return CGPoint(x: u * u * a.x + 2 * u * t * c.x + t * t * b.x,
                           y: u * u * a.y + 2 * u * t * c.y + t * t * b.y)
        }
        /// A straight connector is one segment; a curve is approximated by 16.
        var segmentCount: Int { bend == 0 ? 1 : 16 }
        var samples: [CGPoint] { (0...segmentCount).map { point(at: CGFloat($0) / CGFloat(segmentCount)) } }
    }

    static func routes(connectors: [Connector], obstacles: [Obstacle], viewport: CGRect? = nil) -> [Route] {
        routes(connectors: connectors, bends: bends(connectors: connectors, obstacles: obstacles), viewport: viewport)
    }

    /// Chooses each connector's bend around unrelated labels. Run in world space, the choice
    /// depends only on the layout, so panning and zooming never flip a line between curves.
    static func bends(connectors: [Connector], obstacles: [Obstacle]) -> [String: CGFloat] {
        var result: [String: CGFloat] = [:]
        for connector in connectors {
            let relevant = obstacles.filter { $0.ownerID != connector.fromNodeID && $0.ownerID != connector.toNodeID }
            var chosen: CGFloat = 0
            var bestScore = score(Route(connector: connector), obstacles: relevant)
            if bestScore > 0 {
                let distance = hypot(connector.end.x - connector.start.x, connector.end.y - connector.start.y)
                let offset = min(128, max(48, distance * 0.18))
                for bend in [offset, -offset, offset * 2, -offset * 2] {
                    let value = score(Route(connector: connector, bend: bend), obstacles: relevant)
                    if value < bestScore { chosen = bend; bestScore = value }
                }
            }
            result[connector.id] = chosen
        }
        return result
    }

    /// Screen routes from already-chosen bends (in these connectors' units), plus crossing gaps
    /// sized in these units.
    static func routes(connectors: [Connector], bends: [String: CGFloat], viewport: CGRect? = nil) -> [Route] {
        let result = connectors.sorted(by: { $0.id < $1.id }).map {
            Route(connector: $0, bend: bends[$0.id] ?? 0)
        }
        return withGaps(result, viewport: viewport)
    }

    private static func withGaps(_ routes: [Route], viewport: CGRect?) -> [Route] {
        var result = routes
        // Only nearby segment bounds enter the exact crossing check, including while panning.
        struct Segment { let route: Int; let index: Int; let a: CGPoint; let b: CGPoint; let rect: CGRect }
        var segments: [Segment] = []
        for i in result.indices {
            let points = result[i].samples
            for index in 0..<result[i].segmentCount {
                let rect = bounds(of: [points[index], points[index + 1]]).insetBy(dx: -0.1, dy: -0.1)
                if let viewport, !rect.intersects(viewport) { continue }
                segments.append(Segment(route: i, index: index, a: points[index], b: points[index + 1], rect: rect))
            }
        }
        var gaps: [Int: [ClosedRange<CGFloat>]] = [:]
        for pair in SpatialCollisionIndex.pairs(for: segments.map(\.rect), cellSize: 48) {
            let first = segments[pair.first], second = segments[pair.second]
            guard first.route != second.route, first.rect.intersects(second.rect) else { continue }
            let earlier = first.route < second.route ? first : second
            let later = first.route < second.route ? second : first
            let a = result[earlier.route].connector, b = result[later.route].connector
            guard let fraction = intersectionFraction(later.a, later.b, earlier.a, earlier.b) else { continue }
            let point = CGPoint(x: later.a.x + (later.b.x - later.a.x) * fraction,
                                y: later.a.y + (later.b.y - later.a.y) * fraction)
            // Actual shared endpoints remain joined. A crossing further along still gets a gap.
            let shared = [(a.fromNodeID, a.start), (a.toNodeID, a.end)].filter {
                $0.0 == b.fromNodeID || $0.0 == b.toNodeID
            }
            if shared.contains(where: { hypot($0.1.x - point.x, $0.1.y - point.y) < 12 }) { continue }
            let count = CGFloat(result[later.route].segmentCount)
            let t = (CGFloat(later.index) + fraction) / count
            let speed = max(hypot(later.b.x - later.a.x, later.b.y - later.a.y) * count, 1)
            let halfGap = min(0.08, 5 / speed)
            gaps[later.route, default: []].append(max(0, t - halfGap)...min(1, t + halfGap))
        }
        for index in result.indices { result[index].gaps = merged(gaps[index] ?? []) }
        return result
    }

    private static func score(_ route: Route, obstacles: [Obstacle]) -> CGFloat {
        let points = route.samples
        let bounds = bounds(of: points)
        let contacts = obstacles.filter { obstacle in
            bounds.intersects(obstacle.rect) && (0..<route.segmentCount).contains { segmentIntersectsRect(points[$0], points[$0 + 1], obstacle.rect) }
        }.count
        return CGFloat(contacts) * 1_000_000 + abs(route.bend)
    }

    static func bounds(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points { minX = min(minX, point.x); maxX = max(maxX, point.x); minY = min(minY, point.y); maxY = max(maxY, point.y) }
        return CGRect(x: minX, y: minY, width: max(0.01, maxX - minX), height: max(0.01, maxY - minY))
    }

    static func segmentIntersectsRect(_ a: CGPoint, _ b: CGPoint, _ rect: CGRect) -> Bool {
        if rect.contains(a) || rect.contains(b) { return true }
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
        return (0..<4).contains { intersectionFraction(a, b, corners[$0], corners[($0 + 1) % 4]) != nil }
    }

    static func intersectionFraction(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> CGFloat? {
        let rx = b.x - a.x, ry = b.y - a.y, sx = d.x - c.x, sy = d.y - c.y
        let denominator = rx * sy - ry * sx
        guard abs(denominator) > 0.00001 else { return nil }
        let t = ((c.x - a.x) * sy - (c.y - a.y) * sx) / denominator
        let u = ((c.x - a.x) * ry - (c.y - a.y) * rx) / denominator
        return t >= 0 && t <= 1 && u >= 0 && u <= 1 ? t : nil
    }

    static func visibleRanges(gaps: [ClosedRange<CGFloat>], drawn: CGFloat) -> [ClosedRange<CGFloat>] {
        let end = min(1, max(0, drawn))
        var cursor: CGFloat = 0
        var ranges: [ClosedRange<CGFloat>] = []
        for gap in merged(gaps) {
            if gap.lowerBound > cursor { ranges.append(cursor...min(end, gap.lowerBound)) }
            cursor = max(cursor, gap.upperBound)
            if cursor >= end { return ranges.filter { $0.upperBound > $0.lowerBound } }
        }
        if cursor < end { ranges.append(cursor...end) }
        return ranges.filter { $0.upperBound > $0.lowerBound }
    }

    private static func merged(_ ranges: [ClosedRange<CGFloat>]) -> [ClosedRange<CGFloat>] {
        var result: [ClosedRange<CGFloat>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = result.last, range.lowerBound <= last.upperBound {
                result[result.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else { result.append(range) }
        }
        return result
    }
}

/// World-space bends depend only on the layout, so panning and zooming reuse the last choice
/// instead of rescoring every connector against every label on each frame.
final class InsightTreeConnectorBendCache {
    private var key: Int?
    private var bends: [String: CGFloat] = [:]

    func bends(connectors: [InsightTreeConnectorRouting.Connector],
               obstacles: [InsightTreeConnectorRouting.Obstacle]) -> [String: CGFloat] {
        var hasher = Hasher()
        func combine(_ point: CGPoint) { hasher.combine(Int((point.x * 2).rounded())); hasher.combine(Int((point.y * 2).rounded())) }
        for connector in connectors {
            hasher.combine(connector.id); combine(connector.start); combine(connector.end)
        }
        for obstacle in obstacles {
            hasher.combine(obstacle.ownerID); combine(obstacle.rect.origin)
            combine(CGPoint(x: obstacle.rect.width, y: obstacle.rect.height))
        }
        let next = hasher.finalize()
        if next != key {
            key = next
            bends = InsightTreeConnectorRouting.bends(connectors: connectors, obstacles: obstacles)
        }
        return bends
    }
}
