import CoreGraphics
import Foundation

nonisolated struct SemanticOverlapRelaxation: Sendable {
    let placedMidpointNodeIDs: Set<UUID>
    let showsAllClusterInsights: Bool
    func footprintRadius(of node: NodeModel) -> CGFloat { nodeFootprintRadius(node) }

    private func nodeFootprintRadius(_ node: NodeModel) -> CGFloat {
        if placedMidpointNodeIDs.contains(node.id) { return 70 }   // bare single-chip midpoint
        let visibleInsights = canvasInsights(for: node)
        let longest = visibleInsights.map { $0.title.count }.max() ?? 0
        return insightOrbitRadius(longestTitleChars: longest,
                                  count: visibleInsights.count,
                                  isSuggested: node.isSuggested) + 64   // ring + chip extent
    }

    private func canvasInsights(for node: NodeModel) -> [InsightModel] {
        let members = canvasInsightMembers(
            nodeLabel: node.conceptLabel,
            insights: node.insights,
            preservesMatchingTitle: placedMidpointNodeIDs.contains(node.id)
        )
        return showsAllClusterInsights ? members : Array(members.prefix(6))
    }

    /// Separates footprints, then turns branches so Node-to-Node connectors stop crossing.
    /// `untangledIDs` are the nodes a branch turn moved, whose anchors must follow them.
    func solve(nodes: [NodeModel], edges: [EdgeModel]) -> (nodes: [NodeModel], untangledIDs: Set<UUID>) {
        var working = solve(nodes: nodes)
        let positions = Dictionary(working.map { ($0.id, $0.position) }, uniquingKeysWith: { _, latest in latest })
        // Completed Midpoints grow from a parent like any concept, so they may turn too; only
        // legacy Insight-style Midpoints keep their placed spot.
        let pinned = placedMidpointNodeIDs
        let radii = Dictionary(working.map { ($0.id, nodeFootprintRadius($0)) }, uniquingKeysWith: { _, latest in latest })
        // Semantic bond length per connector; a duplicate pair keeps its shortest.
        let lengths = edges.reduce(into: [InsightTreeEdgeUntangling.Bond: CGFloat]()) { result, edge in
            let bond = InsightTreeEdgeUntangling.Bond.between(edge.fromNodeID, edge.toNodeID)
            result[bond] = min(result[bond] ?? .infinity, mapDistanceToLength(edge.distance))
        }
        let untangled = InsightTreeEdgeUntangling.untangle(positions: positions,
            edges: edges.map { ($0.fromNodeID, $0.toNodeID) }, pinned: pinned, radii: radii, lengths: lengths)
        var untangledIDs: Set<UUID> = []
        for index in working.indices {
            guard let point = untangled[working[index].id], point != working[index].position else { continue }
            working[index].position = point
            untangledIDs.insert(working[index].id)
        }
        return (working, untangledIDs)
    }

    func solve(nodes: [NodeModel]) -> [NodeModel] {
        var working = nodes
        let iterations = 16
        let padding: CGFloat = 72
        let maxStep: CGFloat = 12
        for _ in 0..<iterations {
            var moved = false
            for i in working.indices {
                for j in (i + 1)..<working.count {
                    let aPinned = placedMidpointNodeIDs.contains(working[i].id)
                    let bPinned = placedMidpointNodeIDs.contains(working[j].id)
                    if aPinned && bPinned { continue }

                    var dx = working[j].position.x - working[i].position.x
                    var dy = working[j].position.y - working[i].position.y
                    var dist = hypot(dx, dy)
                    if dist < 0.5 {
                        dx = .random(in: -1...1); dy = .random(in: -1...1); dist = 1
                    }
                    let minDist = nodeFootprintRadius(working[i]) + nodeFootprintRadius(working[j]) + padding
                    guard dist < minDist else { continue }

                    let overlap = minDist - dist
                    let ux = dx / dist, uy = dy / dist
                    func push(_ idx: Int, _ amount: CGFloat) {
                        let s = min(abs(amount), maxStep) * (amount < 0 ? -1 : 1)
                        working[idx].position.x += ux * s
                        working[idx].position.y += uy * s
                    }
                    if aPinned {
                        push(j, overlap)            // only j moves, away from i
                    } else if bPinned {
                        push(i, -overlap)           // only i moves, away from j
                    } else {
                        push(j, overlap / 2)
                        push(i, -overlap / 2)
                    }
                    moved = true
                }
            }
            if !moved { break }   // converged / nothing overlaps
        }
        return working
    }

}
