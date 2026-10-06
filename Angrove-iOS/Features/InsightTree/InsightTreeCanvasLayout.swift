import SwiftUI
import UIKit
import simd

// Layout behavior for the shared global and conversation canvas.
extension InsightTreeCanvasView {
    func insightFocusTarget(for insightID: UUID) -> CGPoint? {
        for node in displayNodes {
            if placedMidpointNodeIDs.contains(node.id), node.insights.contains(where: { $0.id == insightID }) {
                return node.position   // pinned chip sits on the node itself
            }
            let visibleInsights = canvasInsights(for: node)
            if let index = visibleInsights.firstIndex(where: { $0.id == insightID }) {
                return insightWorldPosition(for: node, index: index, count: visibleInsights.count)
            }

            if node.insights.contains(where: { $0.id == insightID }) {
                return node.position
            }
        }

        return nil
    }

    func displayGraphEdges() -> [RenderedGraphEdge] {
        if !edges.isEmpty {
            return edges.map {
                RenderedGraphEdge(
                    id: $0.id.uuidString,
                    fromNodeID: $0.fromNodeID,
                    toNodeID: $0.toNodeID,
                    isSuggested: $0.isSuggested
                )
            }
        }

        // Placed midpoints only connect via their own source connectors — never the generic
        // 2-node / ring fallback, which would add a stray line to a neighbor node.
        let graphNodes = nodes.filter { !placedMidpointNodeIDs.contains($0.id) }
        guard graphNodes.count > 1 else {
            return []
        }

        if graphNodes.count == 2 {
            return [
                RenderedGraphEdge(
                    id: "\(graphNodes[0].id.uuidString)-\(graphNodes[1].id.uuidString)",
                    fromNodeID: graphNodes[0].id,
                    toNodeID: graphNodes[1].id,
                    isSuggested: false
                )
            ]
        }

        return graphNodes.indices.map { index in
            let nextIndex = (index + 1) % graphNodes.count
            return EdgeModel(
                id: UUID(),
                fromNodeID: graphNodes[index].id,
                toNodeID: graphNodes[nextIndex].id,
                distance: 0.5,
                isSuggested: false,
                showSuggestButton: false
            )
        }.map {
            RenderedGraphEdge(
                id: "\($0.fromNodeID.uuidString)-\($0.toNodeID.uuidString)",
                fromNodeID: $0.fromNodeID,
                toNodeID: $0.toNodeID,
                isSuggested: $0.isSuggested
            )
        }
    }

    /// Bond length (connector radius) for an insight chip — its relatedness to the parent node.
    func bondLength(forInsightID id: UUID) -> CGFloat {
        insightBondLengths[id] ?? 190
    }

    /// Even starting angle for an insight before VSEPR repulsion spreads it.
    func baseChipAngle(index: Int, count: Int) -> Double {
        Double(index) / Double(max(count, 1)) * (.pi * 2) + .pi / 8
    }

    /// Midpoint of the largest unoccupied arc. New Insight bonds use this instead of an
    /// index-based angle so additions preserve the widest possible bond angles around a node.
    func maximizedChipGapAngle(among angles: [Double]) -> Double {
        guard !angles.isEmpty else { return .pi / 8 }
        let fullTurn = Double.pi * 2
        let sorted = angles.map { angle in
            var normalized = angle.truncatingRemainder(dividingBy: fullTurn)
            if normalized < 0 { normalized += fullTurn }
            return normalized
        }.sorted()

        var largestGap = -Double.infinity
        var largestGapStart = sorted[0]
        for index in sorted.indices {
            let start = sorted[index]
            let end = index + 1 < sorted.count ? sorted[index + 1] : sorted[0] + fullTurn
            let gap = end - start
            if gap > largestGap {
                largestGap = gap
                largestGapStart = start
            }
        }
        return (largestGapStart + largestGap / 2).truncatingRemainder(dividingBy: fullTurn)
    }

    /// Directions of every visible node-to-node line connected to `nodeID`. These fixed bonds
    /// participate in the same angular domain as the Node Concept's Insight bonds.
    func connectedNodeBondAngles(for nodeID: UUID) -> [Double] {
        displayGraphEdges().compactMap { edge in
            let neighborID: UUID
            if edge.fromNodeID == nodeID {
                neighborID = edge.toNodeID
            } else if edge.toNodeID == nodeID {
                neighborID = edge.fromNodeID
            } else {
                return nil
            }
            guard let parentPosition = bodies[nodeID]?.pos,
                  let neighborPosition = bodies[neighborID]?.pos else {
                return nil
            }
            return Double(
                atan2(
                    neighborPosition.y - parentPosition.y,
                    neighborPosition.x - parentPosition.x
                )
            )
        }
    }

    /// Matches the rendered Insight chip's fixed horizontal layout closely enough for the
    /// cleanup simulation to keep even long titles from overlapping chips in another node.
    func insightCollisionSize(for insight: InsightModel) -> CGSize {
        if let cached = collisionSizeCache.sizes[insight.title] { return cached }
        let titleWidth = ceil(
            (insight.title as NSString).size(
                withAttributes: [.font: Self.insightCollisionFont]
            ).width
        )
        let size = CGSize(
            width: 20 + 14 + 10 + titleWidth + 20,
            height: 16 + Self.insightCollisionFont.lineHeight + 16
        )
        collisionSizeCache.sizes[insight.title] = size
        return size
    }

    /// Wraps an angle difference to [-π, π].
    func wrapAngle(_ a: Double) -> Double {
        var x = a.truncatingRemainder(dividingBy: 2 * .pi)
        if x > .pi { x -= 2 * .pi }
        if x < -.pi { x += 2 * .pi }
        return x
    }

    func insightWorldPosition(for node: NodeModel, index: Int, count: Int) -> CGPoint {
        let visibleInsights = canvasInsights(for: node)
        guard index < visibleInsights.count else { return node.position }
        return insightSpatialPosition(visibleInsights[index], node: node, index: index, count: count).world
    }

    /// The single source of an orbiting Insight's projected world position and local depth.
    /// While this exact chip is being press-dragged, it follows the finger anywhere — the
    /// connector line stretches to match — rather than the fixed (angle, bond length) orbit.
    private func insightSpatialPosition(
        _ insight: InsightModel,
        node: NodeModel,
        index: Int,
        count: Int
    ) -> (world: CGPoint, elevation: CGFloat, localDepth: CGFloat) {
        let radius = bondLength(forInsightID: insight.id)
        let elevationAngle = Self.depthCuesEnabled ? insightElevationAngle(insight.id) : 0
        let localDepth = InsightClusterSpatialLayout.normalizedDepth(angle: elevationAngle)
        if draggingChipID == insight.id, let live = draggingChipWorldPosition {
            // Same angle at the live distance: a chip dragged inward sinks toward the plane
            // rather than climbing past 45° over its Node Concept.
            let liveZ = InsightClusterSpatialLayout.elevation(
                angle: elevationAngle,
                horizontalDistance: hypot(live.x - node.position.x, live.y - node.position.y)
            )
            return (live, liveZ, localDepth)
        }
        let z = InsightClusterSpatialLayout.elevation(angle: elevationAngle, horizontalDistance: radius)
        // Free VSEPR bond angle (falls back to the even base angle until the sim seeds it).
        let angle = chipAngles[insight.id]?.angle ?? baseChipAngle(index: index, count: count)
        let world = CGPoint(
            x: node.position.x + cos(angle) * radius,
            y: node.position.y + sin(angle) * radius
        )
        return (world, z, localDepth)
    }

    private func insightElevationAngle(_ id: UUID) -> CGFloat {
        chipElevationAngles[id] ?? 0
    }

    /// Orbit height of an Insight: its elevation angle at its bond length.
    func insightElevation(_ insight: InsightModel) -> CGFloat {
        InsightClusterSpatialLayout.elevation(
            angle: insightElevationAngle(insight.id),
            horizontalDistance: bondLength(forInsightID: insight.id)
        )
    }

    /// The plane point under the finger for a dragged chip. Its height depends on its distance
    /// from the Node Concept, which depends on the point, so refine from the orbit height.
    func draggedChipFootprint(
        under location: CGPoint,
        insight: InsightModel,
        node: NodeModel,
        camera: InsightTreeCamera,
        size: CGSize
    ) -> CGPoint {
        let angle = Self.depthCuesEnabled ? insightElevationAngle(insight.id) : 0
        var world = camera.screenToWorld(location, elevation: insightElevation(insight), in: size)
        for _ in 0..<3 {
            let z = InsightClusterSpatialLayout.elevation(
                angle: angle,
                horizontalDistance: hypot(world.x - node.position.x, world.y - node.position.y)
            )
            world = camera.screenToWorld(location, elevation: z, in: size)
        }
        return world
    }

    /// Resolves every visible Insight once per render. Chips, connectors, pulses, midpoint
    /// connectors, and selection lines all read these placements, so they cannot disagree about
    /// where a chip is, and no render path rescans nodes or re-filters members per chip.
    func makeInsightLayout() -> CanvasInsightLayout {
        var layout = CanvasInsightLayout(nodes: displayNodes)
        for node in layout.nodes {
            let visibleInsights = canvasInsights(for: node)
            layout.insightsByNode[node.id] = visibleInsights
            let isPinnedAtNode = placedMidpointNodeIDs.contains(node.id)
            for (index, insight) in visibleInsights.enumerated() {
                var spatial: (world: CGPoint, elevation: CGFloat, localDepth: CGFloat) = isPinnedAtNode
                    ? (node.position, 0, 0)
                    : insightSpatialPosition(insight, node: node, index: index, count: visibleInsights.count)
                if !isPinnedAtNode, let offset = studyOffset(forInsightID: insight.id) {
                    let base = studySelectionCenter ?? node.position
                    spatial = (
                        CGPoint(x: base.x + CGFloat(offset.x), y: base.y + CGFloat(offset.y)),
                        CGFloat(offset.z),
                        spatial.localDepth * CGFloat(1 - studyProgress)
                    )
                }
                layout.placements[insight.id] = InsightPlacement(
                    insight: insight,
                    nodeID: node.id,
                    index: index,
                    count: visibleInsights.count,
                    isPinnedAtNode: isPinnedAtNode,
                    world: spatial.world,
                    elevation: spatial.elevation,
                    localDepth: spatial.localDepth
                )
            }
        }
        return layout
    }

    // MARK: - 2.5D Depth Cues

    /// Depth multiplier for a node in [depthMin…, 1]: 1 = nearest (full size/opacity, no
    /// parallax). Always 1 when the depth layer is disabled or the node has no depth entry.
    func depthFactor(_ nodeID: UUID) -> CGFloat {
        guard Self.depthCuesEnabled else { return 1 }
        return CGFloat(nodeDepths[nodeID] ?? 1)
    }

    func depthScale(_ nodeID: UUID) -> CGFloat {
        Self.depthMinScale + (1 - Self.depthMinScale) * depthFactor(nodeID)
    }

    func depthOpacity(_ nodeID: UUID) -> Double {
        Self.depthMinOpacity + (1 - Self.depthMinOpacity) * Double(depthFactor(nodeID))
    }

    /// Every chip goes through the same perspective camera as the plane beneath it, so a raised
    /// chip sits higher and nearer than its footprint and moves faster than the plane while
    /// panning. The hovered chip needs no special case: focus solves for its elevation.
    func insightProjection(
        _ placement: InsightPlacement,
        camera: InsightTreeCamera,
        size: CGSize
    ) -> PerspectivePlaneProjection.Point {
        camera.project(placement.world, elevation: placement.elevation, in: size)
    }

    func insightScreenPosition(
        _ placement: InsightPlacement,
        camera: InsightTreeCamera,
        size: CGSize
    ) -> CGPoint {
        insightProjection(placement, camera: camera, size: size).position
    }

    /// Combines the global semantic MDS depth of a Node Concept with an Insight's local
    /// elevation for opacity. Pinned midpoint Insights stay at their Node depth.
    private func insightDepthFactor(_ placement: InsightPlacement) -> CGFloat {
        insightTreeCanvasClamp(depthFactor(placement.nodeID) + placement.localDepth * 0.12, lower: 0, upper: 1)
    }

    func insightDepthOpacity(_ placement: InsightPlacement) -> Double {
        Self.depthMinOpacity + (1 - Self.depthMinOpacity) * Double(insightDepthFactor(placement))
    }

    /// World elevation of a visible Insight by id (0 for pinned midpoints and hidden members).
    func insightElevation(forInsightID id: UUID) -> CGFloat {
        guard Self.depthCuesEnabled,
              let node = nodes.first(where: { node in
                  !placedMidpointNodeIDs.contains(node.id) && node.insights.contains { $0.id == id }
              }),
              let insight = canvasInsights(for: node).first(where: { $0.id == id }) else { return 0 }
        return insightElevation(insight)
    }

    /// The node whose orbit an insight chip belongs to (for depth lookups by insight id).
    private func owningNodeID(forInsightID id: UUID) -> UUID? {
        nodes.first(where: { $0.insights.contains { $0.id == id } })?.id
    }

}
