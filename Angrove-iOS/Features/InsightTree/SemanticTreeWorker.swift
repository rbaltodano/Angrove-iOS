import CoreGraphics
import Foundation

nonisolated struct SemanticClusterSubjectEmbedding: Equatable, Sendable {
    let text: String
    let version: String
    let vector: [Double]
}

/// Immutable input values and private mutable computation state; no UI, file I/O or model calls.
nonisolated struct SemanticTreeComputation: Equatable, Sendable {
    var allInsights: [InsightModel]
    var localSeedAnchors: [LocalInsightTreeSeed]
    var insightClusterAssignments: [UUID: UUID]
    var clusterMergeTargets: [UUID: UUID]
    var clusterSubjectEmbeddings: [UUID: SemanticClusterSubjectEmbedding]
    var generatedClusterLabels: [UUID: String]
    var generatedClusterDefinitions: [UUID: String]
    var positions: [UUID: CGPoint]
    var providerVersion: String
    var localMembershipThreshold: Double

    private func restoredPosition(for id: UUID) -> CGPoint? { positions[id] }

    mutating func build(
        from insights: [InsightModel]
    ) -> (nodes: [NodeModel], edges: [EdgeModel]) {
        struct Cluster {
            let id: UUID
            var insights: [InsightModel]
            var embedding: [Double]
            var seedLabel: String?
            var seedSummary: String?
        }

        // Follow merges to the Node that finally absorbed a given id.
        func mergeSurvivor(of id: UUID) -> UUID {
            var current = id
            var visited: Set<UUID> = [id]
            while let next = clusterMergeTargets[current], visited.insert(next).inserted {
                current = next
            }
            return current
        }
        insightClusterAssignments = insightClusterAssignments.mapValues(mergeSurvivor(of:))
        let seedIDs = Set(localSeedAnchors.map(\.id))
        let assignedClusterIDs = Set(insightClusterAssignments.values)
        // An absorbed seed stays folded while the Node that absorbed it still exists.
        let foldedSeedIDs = Set(localSeedAnchors.map(\.id).filter { id in
            let survivor = mergeSurvivor(of: id)
            return survivor != id && (seedIDs.contains(survivor) || assignedClusterIDs.contains(survivor))
        })

        var clusters: [Cluster] = localSeedAnchors.filter { !foldedSeedIDs.contains($0.id) }.map { seed in
            Cluster(
                id: seed.id,
                insights: [],
                embedding: (seed.embeddingVersion ?? NLEmbeddingProvider.version) == providerVersion
                    ? (seed.embedding ?? []) : [],
                seedLabel: seed.label,
                seedSummary: seed.summary
            )
        }
        for insight in insights {
            let embedding = insight.embedding ?? []

            // An Insight that already belongs to a Node keeps that Node's identity regardless of
            // what else was added or removed — no re-matching against current cluster centroids.
            let targetClusterID: UUID
            if let assigned = insightClusterAssignments[insight.id] {
                targetClusterID = assigned
            } else {
                let best = clusters.indices
                    .map { index in
                        let memberSimilarity = cosineSimilarity(embedding, clusters[index].embedding)
                        let seedSimilarity = localSeedAnchors.first { $0.id == clusters[index].id }
                            .map { seed in
                                guard (seed.embeddingVersion ?? NLEmbeddingProvider.version) == providerVersion else { return -1.0 }
                                return cosineSimilarity(embedding, seed.embedding ?? [])
                            } ?? -1
                        return (index, max(memberSimilarity, seedSimilarity))
                    }
                    .max { $0.1 < $1.1 }
                if let best, best.1 >= localMembershipThreshold {
                    targetClusterID = clusters[best.0].id
                } else {
                    targetClusterID = UUID()
                }
                insightClusterAssignments[insight.id] = targetClusterID
            }

            if let index = clusters.firstIndex(where: { $0.id == targetClusterID }) {
                clusters[index].insights.append(insight)
                clusters[index].embedding = centroid(
                    clusters[index].insights.compactMap(\.embedding)
                        + (localSeedAnchors.first(where: { $0.id == targetClusterID })
                            .flatMap { seed -> [Double]? in
                                guard (seed.embeddingVersion ?? NLEmbeddingProvider.version) == providerVersion else { return nil }
                                return seed.embedding
                            }.map { [$0] } ?? [])
                )
            } else {
                clusters.append(
                    Cluster(
                        id: targetClusterID,
                        insights: [insight],
                        embedding: embedding
                    )
                )
            }
        }
        // Related Nodes found separately — by different turns, or by Insights saved before the
        // Node they belong under existed — fold together, so one subject never splits into
        // several near-identical Nodes. Membership is greedy and sticky, so without this pass an
        // early split would last forever. The larger Node survives (a seeded subject wins ties)
        // and keeps its id, label, and position.
        // Two signals, each with its own bar: the members' centroid, and the Node's own subject
        // (seed or generated label with its definition).
        let memberThreshold = InsightTreeSemanticPolicy.nodeMergeSimilarity
        let subjectThreshold = InsightTreeSemanticPolicy.nodeSubjectMergeSimilarity
        func subjectVector(of cluster: Cluster) -> [Double]? {
            if let seed = localSeedAnchors.first(where: { $0.id == cluster.id }) {
                guard (seed.embeddingVersion ?? NLEmbeddingProvider.version) == providerVersion else { return nil }
                return seed.embedding
            }
            guard let subject = clusterSubjectEmbeddings[cluster.id],
                  subject.version == providerVersion else { return nil }
            return subject.vector
        }
        var pairMargins: [Set<UUID>: Double] = [:]
        while true {
            if Task.isCancelled { return ([], []) }
            // The pair that clears its bar by the widest margin merges first.
            var best: (survivor: Int, absorbed: Int, margin: Double)?
            for left in clusters.indices {
                for right in clusters.indices where right > left {
                    let pair = Set([clusters[left].id, clusters[right].id])
                    var margin = pairMargins[pair] ?? -Double.infinity
                    if pairMargins[pair] == nil {
                    if !clusters[left].embedding.isEmpty, !clusters[right].embedding.isEmpty {
                        margin = cosineSimilarity(clusters[left].embedding, clusters[right].embedding) - memberThreshold
                    }
                    if let leftSubject = subjectVector(of: clusters[left]),
                       let rightSubject = subjectVector(of: clusters[right]) {
                        margin = max(margin, cosineSimilarity(leftSubject, rightSubject) - subjectThreshold)
                    }
                    pairMargins[pair] = margin
                    }
                    guard margin >= 0, margin > (best?.margin ?? -1) else { continue }
                    let leftWins = clusters[left].insights.count != clusters[right].insights.count
                        ? clusters[left].insights.count > clusters[right].insights.count
                        : (clusters[left].seedLabel != nil || clusters[right].seedLabel == nil)
                    best = leftWins ? (left, right, margin) : (right, left, margin)
                }
            }
            guard let best else { break }
            let absorbed = clusters[best.absorbed]
            let survivorID = clusters[best.survivor].id
            clusters[best.survivor].insights += absorbed.insights
            clusters[best.survivor].embedding = centroid(
                clusters[best.survivor].insights.compactMap(\.embedding)
                    + [absorbed, clusters[best.survivor]].compactMap { cluster -> [Double]? in
                        guard let seed = localSeedAnchors.first(where: { $0.id == cluster.id }),
                              (seed.embeddingVersion ?? NLEmbeddingProvider.version) == providerVersion
                        else { return nil }
                        return seed.embedding
                    }
            )
            for insight in absorbed.insights {
                insightClusterAssignments[insight.id] = survivorID
            }
            clusterMergeTargets[absorbed.id] = survivorID
            pairMargins = pairMargins.filter { !$0.key.contains(survivorID) && !$0.key.contains(absorbed.id) }
            clusters.remove(at: best.absorbed)
        }
        let liveInsightIDs = Set(allInsights.map(\.id))
        insightClusterAssignments = insightClusterAssignments.filter { liveInsightIDs.contains($0.key) }

        // Bare nodes first — position filled in below by the same pass that decides edges, so
        // the two can never disagree (see the comment on that loop for why that matters).
        var builtNodes: [NodeModel] = clusters.map { cluster in
            let label = generatedClusterLabels[cluster.id] ?? cluster.seedLabel
            let repeatsMember = label.map {
                NodeConceptLabelPolicy.repeatsInsightTitle($0, insightTitles: cluster.insights.map(\.title))
            } ?? false
            let definition = generatedClusterLabels[cluster.id] != nil
                ? (generatedClusterDefinitions[cluster.id] ?? "")
                : (cluster.seedSummary ?? "")
            return NodeModel(
                id: cluster.id,
                conceptLabel: repeatsMember ? provisionalClusterLabel(for: cluster.insights)
                    : (label ?? provisionalClusterLabel(for: cluster.insights)),
                definition: repeatsMember ? "" : definition,
                insights: cluster.insights,
                embedding: cluster.embedding,
                position: .zero,
                isSuggested: false,
                suggestedInsights: nil
            )
        }

        var builtEdges: [EdgeModel] = []
        guard !builtNodes.isEmpty else { return (builtNodes, builtEdges) }

        // Grow a nearest-neighbor spanning tree (Prim's) and position each node AS it attaches,
        // directly off the edge that attaches it — one pass, not two. This used to be two
        // independent nearest-neighbor searches: one decided where to *draw* a node (nearest
        // among already-built nodes, in cluster-creation order) and a separate one decided what
        // to *connect* it to (a proper MST over every node). Those don't necessarily agree, so a
        // node could be drawn next to one node while its edge actually connected to a different,
        // farther one — exactly what produces confusing, criss-crossing lines. A tree can always
        // be drawn with zero crossings; computing both from the same edge is what makes that hold.
        var connected: Set<Int> = [0]
        var bestDistances = [Double](repeating: .infinity, count: builtNodes.count)
        var parents = [Int](repeating: 0, count: builtNodes.count)
        builtNodes[0].position = restoredPosition(for: builtNodes[0].id) ?? .zero
        var latest = 0
        while connected.count < builtNodes.count {
            if Task.isCancelled { return ([], []) }
            for target in builtNodes.indices where !connected.contains(target) {
                let distance = semanticDistance(builtNodes[latest].embedding, builtNodes[target].embedding)
                if distance < bestDistances[target] || (distance == bestDistances[target] && latest < parents[target]) {
                    bestDistances[target] = distance
                    parents[target] = latest
                }
            }
            guard let childIndex = builtNodes.indices.filter({ !connected.contains($0) }).min(by: {
                bestDistances[$0] == bestDistances[$1] ? $0 < $1 : bestDistances[$0] < bestDistances[$1]
            }) else { break }
            let parentIndex = parents[childIndex]
            let distance = bestDistances[childIndex]
            let parentNode = builtNodes[parentIndex]
            let childID = builtNodes[childIndex].id
            // maximizedGapAngle (inside chainExtensionPosition) also spreads this node away from
            // any siblings already attached to the same parent, rather than a random angle.
            builtNodes[childIndex].position = restoredPosition(for: childID) ?? chainExtensionPosition(
                from: parentNode,
                nodes: builtNodes,
                edges: builtEdges,
                bondLength: mapDistanceToLength(distance)
            )
            builtEdges.append(
                EdgeModel(
                    id: stableUUID(from: "global-cluster-edge:\(parentNode.id):\(childID)"),
                    fromNodeID: parentNode.id,
                    toNodeID: childID,
                    distance: distance,
                    isSuggested: false,
                    // Suggest Connection (generates a suggested midpoint node between two Nodes)
                    // is disabled for now.
                    showSuggestButton: false
                )
            )
            connected.insert(childIndex)
            latest = childIndex
        }
        return (builtNodes, builtEdges)
    }

    private func provisionalClusterLabel(for insights: [InsightModel]) -> String {
        guard let first = insights.first else { return "New Subject" }
        return insights.count > 1 ? "Related Insights" : "Exploring \(first.title)"
    }

    private func chainExtensionPosition(
        from sourceNode: NodeModel,
        nodes: [NodeModel],
        edges: [EdgeModel],
        bondLength: CGFloat = mapDistanceToLength(0.18)   // matches the promoted-node edge's target length
    ) -> CGPoint {
        let occupiedAngles: [CGFloat] = edges.compactMap { edge in
            let neighborID: UUID
            if edge.toNodeID == sourceNode.id { neighborID = edge.fromNodeID }
            else if edge.fromNodeID == sourceNode.id { neighborID = edge.toNodeID }
            else { return nil }
            guard let neighbor = nodes.first(where: { $0.id == neighborID }) else { return nil }
            return atan2(neighbor.position.y - sourceNode.position.y, neighbor.position.x - sourceNode.position.x)
        }

        let angle: CGFloat
        if occupiedAngles.isEmpty {
            angle = -.pi / 2
        } else if occupiedAngles.count == 1 {
            let bendDegrees: CGFloat = 32
            angle = normalizedAngle(occupiedAngles[0] + .pi + chainBendDirection(for: sourceNode.id) * bendDegrees * .pi / 180)
        } else {
            angle = maximizedGapAngle(among: occupiedAngles)
        }

        return CGPoint(
            x: sourceNode.position.x + cos(angle) * bondLength,
            y: sourceNode.position.y + sin(angle) * bondLength
        )
    }

    /// Deterministic left/right alternation for `chainExtensionPosition`'s single-bond bend,
    /// keyed off the growing node's own id (stable across relaunches, unlike an index into
    /// whatever order the current rebuild happens to process nodes in) so the same chain always
    /// curves the same way instead of jittering between rebuilds.
    private func chainBendDirection(for nodeID: UUID) -> CGFloat {
        stableUUID(from: "chain-bend:\(nodeID)").uuid.0 % 2 == 0 ? 1 : -1
    }

    /// The angle that maximizes angular separation from every angle in `angles`: the bisector of
    /// the largest gap between them going around the circle. With one existing angle this is
    /// exactly its opposite (180°); with several, it's the widest open gap — the same "maximum
    /// separation" rule VSEPR uses to spread bonds around an atom.
    private func maximizedGapAngle(among angles: [CGFloat]) -> CGFloat {
        let twoPi = CGFloat.pi * 2
        let sorted = angles.map { normalizedAngle($0) }.sorted()
        guard sorted.count > 1 else { return normalizedAngle(sorted[0] + .pi) }

        var bestGapStart = sorted[0]
        var bestGapSize: CGFloat = 0
        for i in sorted.indices {
            let start = sorted[i]
            let end = (i + 1 < sorted.count ? sorted[i + 1] : sorted[0] + twoPi)
            let gap = end - start
            if gap > bestGapSize {
                bestGapSize = gap
                bestGapStart = start
            }
        }
        return normalizedAngle(bestGapStart + bestGapSize / 2)
    }

    /// Wraps an angle to [0, 2π).
    private func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        let twoPi = CGFloat.pi * 2
        var a = angle.truncatingRemainder(dividingBy: twoPi)
        if a < 0 { a += twoPi }
        return a
    }

}

nonisolated struct SemanticTreeResult: Sendable {
    let nodes: [NodeModel]
    let edges: [EdgeModel]
    let assignments: [UUID: UUID]
    let merges: [UUID: UUID]
}

actor SemanticTreeWorker {
    private var previousInput: SemanticTreeComputation?
    private var previousMembers: [InsightModel] = []
    private var previousResult: SemanticTreeResult?

    func relax(_ nodes: [NodeModel], using relaxation: SemanticOverlapRelaxation) -> [NodeModel] {
        PerformanceTrace.measure("Graph Overlap Relaxation") { relaxation.solve(nodes: nodes) }
    }

    func compute(_ input: SemanticTreeComputation, members: [InsightModel]) -> SemanticTreeResult {
        if input == previousInput, members == previousMembers, let previousResult { return previousResult }
        var state = input
        let graph = PerformanceTrace.measure("Semantic Graph Build") { state.build(from: members) }
        let result = SemanticTreeResult(nodes: graph.nodes, edges: graph.edges,
                                        assignments: state.insightClusterAssignments, merges: state.clusterMergeTargets)
        if !Task.isCancelled { previousInput = input; previousMembers = members; previousResult = result }
        return result
    }
}
