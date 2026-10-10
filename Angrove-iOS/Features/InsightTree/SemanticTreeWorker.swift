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
    /// Output: each concept budded this pass, keyed to the concept it grew from.
    var budParents: [UUID: UUID] = [:]

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
        // Budding: a cohesive group of an existing concept's loose members becomes a child
        // concept. A group that fits another concept better moves there instead. Clusters are
        // visited in order; a new bud is appended and checked in turn.
        var budIndex = 0
        while budIndex < clusters.count {
            if Task.isCancelled { return ([], []) }
            let cluster = clusters[budIndex]
            budIndex += 1
            let anchor = subjectVector(of: cluster) ?? cluster.embedding
            let members = cluster.insights.compactMap { insight in
                insight.embedding.map { InsightTreeGrowth.Member(id: insight.id, vector: $0) }
            }
            guard members.count > InsightTreeGrowth.budMinimumCount,
                  let groupIDs = InsightTreeGrowth.budGroup(members: members, anchor: anchor) else { continue }
            let moving = cluster.insights.filter { groupIDs.contains($0.id) }
            let center = centroid(moving.compactMap(\.embedding))
            let ownFit = cosineSimilarity(center, anchor)
            let better = clusters.indices.filter { $0 != budIndex - 1 }.map { index -> (Int, Double) in
                let other = subjectVector(of: clusters[index]) ?? clusters[index].embedding
                return (index, other.count == center.count ? cosineSimilarity(center, other) : -1)
            }.max { $0.1 < $1.1 }
            clusters[budIndex - 1].insights.removeAll { groupIDs.contains($0.id) }
            clusters[budIndex - 1].embedding = centroid(clusters[budIndex - 1].insights.compactMap(\.embedding)
                + (localSeedAnchors.first { $0.id == cluster.id }?.embedding.map { [$0] } ?? []))
            if let better, better.1 >= InsightTreeGrowth.tightSimilarity, better.1 > ownFit {
                clusters[better.0].insights += moving
                for insight in moving { insightClusterAssignments[insight.id] = clusters[better.0].id }
            } else {
                let budID = stableUUID(from: "bud:\(cluster.id):\(groupIDs.map(\.uuidString).joined(separator: ","))")
                clusters.append(Cluster(id: budID, insights: moving, embedding: center))
                for insight in moving { insightClusterAssignments[insight.id] = budID }
                budParents[budID] = cluster.id
            }
        }

        let liveInsightIDs = Set(allInsights.map(\.id))
        insightClusterAssignments = insightClusterAssignments.filter { liveInsightIDs.contains($0.key) }

        // Bare nodes; `InsightTreeGrowth` chooses parents and places them after Make Node and
        // Midpoint concepts join, so every kind of concept grows by the same rule.
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

        for index in builtNodes.indices {
            builtNodes[index].position = restoredPosition(for: builtNodes[index].id) ?? .zero
        }
        let builtEdges: [EdgeModel] = []
        return (builtNodes, builtEdges)
    }

    private func provisionalClusterLabel(for insights: [InsightModel]) -> String {
        guard let first = insights.first else { return "New Subject" }
        return insights.count > 1 ? "Related Insights" : "Exploring \(first.title)"
    }

}

nonisolated struct SemanticTreeResult: Sendable {
    let nodes: [NodeModel]
    let edges: [EdgeModel]
    let assignments: [UUID: UUID]
    let merges: [UUID: UUID]
    var budParents: [UUID: UUID] = [:]
}

actor SemanticTreeWorker {
    private var previousInput: SemanticTreeComputation?
    private var previousMembers: [InsightModel] = []
    private var previousResult: SemanticTreeResult?

    func relax(_ nodes: [NodeModel], edges: [EdgeModel], using relaxation: SemanticOverlapRelaxation) -> (nodes: [NodeModel], untangledIDs: Set<UUID>) {
        PerformanceTrace.measure("Graph Overlap Relaxation") { relaxation.solve(nodes: nodes, edges: edges) }
    }

    func compute(_ input: SemanticTreeComputation, members: [InsightModel]) -> SemanticTreeResult {
        if input == previousInput, members == previousMembers, let previousResult { return previousResult }
        var state = input
        let graph = PerformanceTrace.measure("Semantic Graph Build") { state.build(from: members) }
        let result = SemanticTreeResult(nodes: graph.nodes, edges: graph.edges,
                                        assignments: state.insightClusterAssignments, merges: state.clusterMergeTargets,
                                        budParents: state.budParents)
        if !Task.isCancelled { previousInput = input; previousMembers = members; previousResult = result }
        return result
    }
}
