import CoreGraphics
import Foundation

nonisolated struct SemanticOverlapRelaxation: Sendable {
    let placedMidpointNodeIDs: Set<UUID>
    let showsAllClusterInsights: Bool
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

    func solve(nodes: [NodeModel]) -> [NodeModel] {
        var working = nodes
        let iterations = 8
        let padding: CGFloat = 24
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
