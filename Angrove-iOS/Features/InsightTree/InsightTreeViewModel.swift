//
//  InsightTreeViewModel.swift
//  Angrove-iOS
//

import Combine
import CoreGraphics
import CryptoKit
import Foundation
import NaturalLanguage
import SpriteKit
import SwiftUI

// MARK: - Insight Tree View Model

@MainActor
final class InsightTreeViewModel: ObservableObject {
    @Published private(set) var nodes: [NodeModel] = []
    @Published private(set) var edges: [EdgeModel] = []
    @Published private(set) var makeNodeChildIDs: Set<UUID> = []
    /// Child IDs whose generated title/definition have replaced their stable loading content.
    /// The canvas uses this to begin the three-stop reveal tour only after generation completes.
    @Published private(set) var generatedMakeNodeChildIDs: Set<UUID> = []
    /// Node IDs for user-placed midpoints. These render as a bare insight chip (no
    /// node-concept circle) pinned at their placed position.
    @Published private(set) var placedMidpointNodeIDs: Set<UUID> = []
    /// For each placed-midpoint node, the sources it connects to (insight chips / node concepts).
    @Published private(set) var placedMidpointSources: [UUID: [MidpointSource]] = [:]
    /// Per-insight bond length (connector radius): shorter = more related to its parent node.
    @Published private(set) var insightBondLengths: [UUID: CGFloat] = [:]
    /// Semantic (MDS) target position per node — the canvas anchors each node to its target
    /// with a weak spring so overlap cleanup can't destroy the embedding-driven layout.
    @Published private(set) var layoutTargets: [UUID: CGPoint] = [:]
    /// Normalized [0,1] depth per node from the third MDS component (1 = nearest),
    /// consumed by the canvas's 2.5D depth cues.
    @Published private(set) var nodeDepths: [UUID: Double] = [:]
    @Published var selectedNode: NodeModel?
    @Published var selectedSuggestedNode: NodeModel?

    let scene: InsightTreeScene
    private var insights: [InsightModel]
    private var promotedInsightIDs: [UUID]
    private var renderedNodeIDs: Set<UUID> = []
    private var placedMidpoints: [PlacedMidpoint] = []
    private let positionStoreKey = "aquinas.insight-tree.positions.v1"
    private static let clusterLabelStoreKey = "aquinas.insight-tree.cluster-labels.v1"
    /// The model boundary for every generative call (subject labels, concept blends). See
    /// `AngroveModel`'s doc comment — swapping in the real model is one conforming type.
    private let model: AngroveModel
    private let modelTasks: ModelTaskQueue?
    private var modelWorkStarted = false
    private let modelTaskOriginPage: ModelTaskOriginPage
    /// The source of insight embedding vectors. See `EmbeddingProvider`'s doc comment.
    private let embeddingProvider: EmbeddingProvider
    /// Global Insights graphs every cluster member. Conversation trees retain their intentionally
    /// compact six-member presentation.
    private let showsAllClusterInsights: Bool
    /// Real Make Node children once generated, keyed by the promoted node's id — checked before
    /// the synchronous placeholder in `appendPromotedNodes`. Populated by `requestChildren`, which
    /// requests them once per newly-promoted insight and triggers a rebuild when they arrive.
    /// Child ids stay deterministic (`makeNodeChildID`) either way, so swapping placeholder → real
    /// content in place never re-triggers the reveal animation.
    private var generatedChildInsights: [UUID: [InsightModel]] = [:]
    private var childGenerationInFlight: Set<UUID> = []
    /// Presence distinguishes Branch from legacy Make Node and retains the original parent.
    private var branchInsightCounts: [UUID: Int] = [:]
    private var branchCountsStoreKey: String {
        "aquinas.insight-tree.branch-counts.v1:\(midpointStoreScope?.uuidString ?? "global")"
    }

    private func childCount(for insightID: UUID) -> Int {
        generatedChildInsights[promotedNodeID(for: insightID)]?.count
            ?? branchInsightCounts[insightID] ?? 3
    }

    private func persistBranchCounts() {
        InsightTreeLocalStateStore.save(branchInsightCounts, key: branchCountsStoreKey)
    }

    /// Scoped the same way as `placedMidpointStoreKey` — without this, a Make Node promotion's
    /// generated children reset to empty the moment the view model was recreated (e.g. navigating
    /// away from the Global tree and back), even on the rare paths where the promotion id itself
    /// survived: the tree would show the loading placeholder and regenerate from scratch.
    private static let makeNodeChildrenStoreKeyPrefix = "aquinas.insight-tree.make-node-children.v1"
    private var makeNodeChildrenStoreKey: String {
        "\(Self.makeNodeChildrenStoreKeyPrefix):\(midpointStoreScope?.uuidString ?? "global")"
    }
    private var generatedClusterLabels: [UUID: String] = [:]
    private var clusterLabelGenerationInFlight: Set<UUID> = []
    /// Real generated definitions for auto-clustered Nodes, keyed by cluster id — requested right
    /// after the label (see `requestClusterLabels`). Until it arrives, the Node's docked card
    /// falls back to `DockedNodeTreeCard.summaryText`.
    private var generatedClusterDefinitions: [UUID: String] = [:]
    private static let clusterDefinitionStoreKey = "aquinas.insight-tree.cluster-definitions.v1"
    /// Which auto-cluster (Node) each Insight belongs to, keyed by the Insight's own id rather
    /// than derived from "whichever Insight happened to found the cluster." A cluster used to get
    /// its id from `stableUUID(from: "global-insight-cluster:\(firstInsight.id)")` — so removing
    /// that one founding Insight silently re-founded the whole cluster under a fresh id on the
    /// next rebuild, discarding its position, label, and definition even though every other member
    /// was untouched. Persisting the assignment per-member means an add or remove only changes the
    /// Insight actually added or removed; everyone else's Node stays exactly where it was.
    private var insightClusterAssignments: [UUID: UUID] = [:]
    private static let insightClusterAssignmentStoreKey = "aquinas.insight-tree.insight-cluster-assignments.v1"
    private var scopedClusterAssignmentStoreKey: String {
        Self.clusterAssignmentStoreKey(scope: midpointStoreScope)
    }
    private static func clusterAssignmentStoreKey(scope: UUID?) -> String {
        guard let scope else { return Self.insightClusterAssignmentStoreKey }
        // Legacy assignments mixed Global and conversation ownership, including assignments made
        // before MiniLM was ready. Recompute conversation membership once in a clean scope.
        return "aquinas.insight-tree.insight-cluster-assignments.v2:\(scope.uuidString)"
    }
    /// Nodes folded into a closely related Node (absorbed id → surviving id). Persisted so an
    /// absorbed seeded subject stays folded on the next open instead of reappearing on its own.
    private var clusterMergeTargets: [UUID: UUID] = [:]
    private var scopedClusterMergeStoreKey: String {
        Self.clusterMergeStoreKey(scope: midpointStoreScope)
    }
    private static func clusterMergeStoreKey(scope: UUID?) -> String {
        "aquinas.insight-tree.cluster-merges.v1:\(scope?.uuidString ?? "global")"
    }
    /// Each automatic Node's subject ("label. definition") embedded, so Nodes about the same
    /// subject can merge even when their member Insights are only loosely related to each other
    /// (Thucydides and Polis both sit under "Ancient Greek Politics" but score 0.31).
    private var clusterSubjectEmbeddings: [UUID: SemanticClusterSubjectEmbedding] = [:]
    private var embeddingRefreshGeneration = 0
    private let graphWorker = SemanticTreeWorker()
    private var graphBuildTask: Task<Void, Never>?
    private var graphRevision = 0

    /// Minimum cosine similarity for an Insight to attach to an existing local Node. The bundled
    /// provider is MiniLM, matching the grounding corpus's embedding space. This value is centralized as a
    /// calibration constant so real-conversation evaluation can change it without touching layout.
    private let localMembershipThreshold = InsightTreeSemanticPolicy.membershipSimilarity
    /// On-device Node Concepts seeded from a conversation's questions (see
    /// `LocalInsightTreeSeedStore`). Fed into `makeClusteredTree` as pre-existing anchor clusters,
    /// so a saved Insight that's semantically related attaches under the seeded subject (see
    /// `setLocalSeedAnchors`'s doc comment).
    private var localSeedAnchors: [LocalInsightTreeSeed] = []

    /// A user-placed "midpoint" insight: a permanent node pinned at an explicit world
    /// position, connected by an edge to each of the source insights it was spawned from.
    private struct PlacedMidpoint: Equatable {
        let concept: ConceptDefinition
        let position: CGPoint
        let sources: [MidpointSource]
    }

    /// On-disk form of `PlacedMidpoint` — `ConceptDefinition` and `MidpointSource` are already
    /// Codable; only `CGPoint` needs the usual wrapper.
    private struct CodablePlacedMidpoint: Codable {
        let concept: ConceptDefinition
        let position: CodablePoint
        let sources: [MidpointSource]
    }

    /// Which conversation's tree this instance belongs to (`nil` for the Global tree) — scopes
    /// placed-Midpoint persistence the same way `LocalInsightTreeSeedStore` scopes seeds, so a
    /// Midpoint placed in one tree doesn't leak into another's.
    private let midpointStoreScope: UUID?
    private static let placedMidpointStoreKeyPrefix = "aquinas.insight-tree.placed-midpoints.v1"
    private var placedMidpointStoreKey: String {
        "\(Self.placedMidpointStoreKeyPrefix):\(midpointStoreScope?.uuidString ?? "global")"
    }

    init(
        insights: [ConceptDefinition],
        promotedInsightIDs: [UUID] = [],
        showsAllClusterInsights: Bool = false,
        model: AngroveModel = MockAngroveModel(),
        modelTasks: ModelTaskQueue? = nil,
        modelTaskOriginPage: ModelTaskOriginPage = .insights,
        embeddingProvider: EmbeddingProvider = NLEmbeddingProvider(),
        localSeedAnchors: [LocalInsightTreeSeed] = [],
        midpointStoreScope: UUID? = nil,
        usesBackgroundGraphWorker: Bool = true
    ) {
        self.usesBackgroundGraphWorker = usesBackgroundGraphWorker
        self.insights = Self.deduplicated(insights.map { InsightModel(concept: $0) })
        self.promotedInsightIDs = promotedInsightIDs
        self.showsAllClusterInsights = showsAllClusterInsights
        self.model = model
        self.modelTasks = modelTasks
        self.modelTaskOriginPage = modelTaskOriginPage
        self.embeddingProvider = embeddingProvider
        self.localSeedAnchors = localSeedAnchors
        self.midpointStoreScope = midpointStoreScope
        generatedClusterLabels = Self.loadClusterLabels(
            storageKey: Self.clusterLabelStoreKey
        )
        generatedClusterDefinitions = Self.loadClusterLabels(
            storageKey: Self.clusterDefinitionStoreKey
        )
        insightClusterAssignments = Self.loadUUIDMapping(
            storageKey: Self.clusterAssignmentStoreKey(scope: midpointStoreScope)
        )
        clusterMergeTargets = Self.loadUUIDMapping(
            storageKey: Self.clusterMergeStoreKey(scope: midpointStoreScope)
        )
        placedMidpoints = Self.loadPlacedMidpoints(
            storageKey: "\(Self.placedMidpointStoreKeyPrefix):\(midpointStoreScope?.uuidString ?? "global")"
        )
        generatedChildInsights = Self.loadMakeNodeChildren(
            storageKey: "\(Self.makeNodeChildrenStoreKeyPrefix):\(midpointStoreScope?.uuidString ?? "global")"
        )
        branchInsightCounts = InsightTreeLocalStateStore.load([UUID: Int].self, key: "aquinas.insight-tree.branch-counts.v1:\(midpointStoreScope?.uuidString ?? "global")") ?? [:]
        generatedMakeNodeChildIDs = Set(generatedChildInsights.values.flatMap { $0.map(\.id) })
        scene = InsightTreeScene(size: CGSize(width: 390, height: 844))
        scene.scaleMode = .resizeFill
        scene.backgroundColor = UIColor(AngroveTheme.Colors.canvas)
        scene.onNodeTapped = { [weak self] node in
            Task { @MainActor in self?.handleTappedNode(node) }
        }
        scene.onSuggestConnection = { [weak self] edge in
            self?.generateSuggestedNode(for: edge)
        }

        rebuildTree()
    }

    /// StateObject initialization runs during SwiftUI rendering. Queue mutations must wait
    /// until the mounted view's task, or AttributeGraph can abort while updating the view.
    func startModelWork() {
        guard !modelWorkStarted else { return }
        modelWorkStarted = true
        rebuildTree()
        refreshEmbeddingsIfNeeded()
    }

    func updateInsights(_ concepts: [ConceptDefinition], promotedInsightIDs: [UUID]? = nil) {
#if DEBUG
        print("Angrove updateInsights: incoming \(concepts.count) concept(s) \(concepts.map(\.word))")
#endif
        embeddingRefreshGeneration += 1
        let previous = Dictionary(uniqueKeysWithValues: insights.map { ($0.id, $0) })
        insights = Self.deduplicated(concepts.map { concept in
            let next = InsightModel(concept: concept)
            if let existing = previous[next.id], existing.title == next.title,
               existing.definition == next.definition { return existing }
            return next
        })
        if let promotedInsightIDs {
            self.promotedInsightIDs = promotedInsightIDs
            let retainedNodeIDs = Set(promotedInsightIDs.map {
                promotedNodeID(for: $0)
            })
            generatedChildInsights = generatedChildInsights.filter {
                retainedNodeIDs.contains($0.key)
            }
            persistMakeNodeChildren()
            childGenerationInFlight.formIntersection(retainedNodeIDs)
            let retainedChildIDs = Set(promotedInsightIDs.flatMap { insightID in
                let nodeID = promotedNodeID(for: insightID)
                return (0..<childCount(for: insightID)).map { makeNodeChildID(for: nodeID, index: $0) }
            })
            generatedMakeNodeChildIDs.formIntersection(retainedChildIDs)
        }
        rebuildTree()
        refreshEmbeddingsIfNeeded()
    }

    /// Replaces the on-device Node-seed anchors and rebuilds. Seeds go through the SAME clustering
    /// pass as regular Insights rather than a separate snapshot: the seed renders as its own Node
    /// with zero Insights when none are saved yet, and a saved Insight that's semantically close
    /// attaches under it, rather than either side overwriting the other.
    func setLocalSeedAnchors(_ seeds: [LocalInsightTreeSeed]) {
#if DEBUG
        print("Angrove setLocalSeedAnchors: incoming \(seeds.map { "\($0.label)[emb=\($0.embedding?.count.description ?? "nil")]" }), unchanged=\(localSeedAnchors == seeds)")
#endif
        guard localSeedAnchors != seeds else { return }
        embeddingRefreshGeneration += 1
        localSeedAnchors = seeds
        rebuildTree()
        refreshEmbeddingsIfNeeded()
    }

    /// Drops any later entry that repeats an earlier one's id, keeping first-seen order. Callers
    /// like the per-conversation tree build this list fresh from live conversation state (rather
    /// than a stable saved-insights store), so a duplicate id can slip in upstream — e.g. two
    /// synthesized "question" pseudo-insights whose ids happen to coincide. Every downstream step
    /// (clustering, force layout, position persistence) keys dictionaries by insight/node id and
    /// fatally crashes on a duplicate key, so this is enforced once, right at the boundary.
    private static func deduplicated(_ insights: [InsightModel]) -> [InsightModel] {
        var seen = Set<UUID>()
        return insights.filter { seen.insert($0.id).inserted }
    }

    /// In-memory save entry point for canvas variants that don't rebuild from `updateInsights`.
    func onInsightSaved(_ insight: InsightModel) {
        var savedInsight = insight
        savedInsight.embedding = savedInsight.embedding ?? computeEmbedding(for: "\(insight.title). \(insight.definition)")
        savedInsight.embeddingVersion = savedInsight.embeddingVersion ?? NLEmbeddingProvider.version
        insights.append(savedInsight)
        rebuildTree()
        refreshEmbeddingsIfNeeded()
    }

    /// Confirms every insight's cached embedding matches the configured `embeddingProvider`,
    /// recomputing any that are missing or were produced by a different provider (a source swap).
    /// `rebuildTree`'s own embedding step above is a synchronous same-provider fallback only (it
    /// keeps the tree usable immediately, including during `init`); this is the versioned,
    /// async-capable path used by the live MiniLM provider. Membership is committed only after
    /// these vectors are ready.
    private var midpointEmbeddings: [UUID: SemanticClusterSubjectEmbedding] = [:]
    private let usesBackgroundGraphWorker: Bool
    private var embeddingRefreshTask: Task<Void, Never>?
    private func refreshEmbeddingsIfNeeded() {
        embeddingRefreshTask?.cancel()
        embeddingRefreshTask = Task { @MainActor [weak self] in await self?.prepareSemanticTree() }
    }

    /// Publish a snapshot only after Insights and seeds share the configured vector space.
    /// Reject an older asynchronous result if a bookmark or seed changed while it was embedding.
    func prepareSemanticTree() async {
        let generation = embeddingRefreshGeneration
        let originalInsights = insights
        let originalSeeds = localSeedAnchors
        let corrected = await ensureEmbeddings(for: originalInsights)
        let originalChildren = generatedChildInsights
        var correctedChildren = originalChildren
        for (nodeID, children) in originalChildren {
            guard let sourceID = promotedSourceInsightID(forNodeID: nodeID),
                  let source = corrected.first(where: { $0.id == sourceID })
                    ?? placedMidpoints.first(where: { $0.concept.id == sourceID }).map({ InsightModel(concept: $0.concept) }) else { continue }
            correctedChildren[nodeID] = await preparedChildren(children, source: source)
        }
        var correctedSeeds: [LocalInsightTreeSeed] = []
        for seed in originalSeeds {
            if seed.embedding != nil,
               (seed.embeddingVersion ?? NLEmbeddingProvider.version) == embeddingProvider.version {
                correctedSeeds.append(seed)
            } else {
                let embedding = await embeddingProvider.embed("\(seed.label). \(seed.summary)")
                correctedSeeds.append(LocalInsightTreeSeed(
                    id: seed.id, label: seed.label, summary: seed.summary,
                    embedding: embedding, embeddingVersion: embeddingProvider.version,
                    createdAt: seed.createdAt
                ))
            }
        }
        let originalMidpoints = placedMidpoints
        var correctedMidpoints = midpointEmbeddings
        for midpoint in originalMidpoints {
            let text = "\(midpoint.concept.word). \(midpoint.concept.semanticDefinition)"
            if correctedMidpoints[midpoint.concept.id]?.text != text
                || correctedMidpoints[midpoint.concept.id]?.version != embeddingProvider.version {
                if let vector = await embeddingProvider.embed(text) {
                    correctedMidpoints[midpoint.concept.id] = SemanticClusterSubjectEmbedding(
                        text: text, version: embeddingProvider.version, vector: vector)
                }
            }
        }
        var subjectEmbeddings = clusterSubjectEmbeddings
        let liveClusterIDs = Set(nodes.map(\.id)).union(insightClusterAssignments.values)
        for id in liveClusterIDs {
            guard let label = generatedClusterLabels[id],
                  let definition = generatedClusterDefinitions[id], !definition.isEmpty else { continue }
            let text = "\(label). \(definition)"
            guard subjectEmbeddings[id]?.text != text || subjectEmbeddings[id]?.version != embeddingProvider.version,
                  let vector = await embeddingProvider.embed(text) else { continue }
            subjectEmbeddings[id] = SemanticClusterSubjectEmbedding(text: text, version: embeddingProvider.version, vector: vector)
        }
        guard !Task.isCancelled, generation == embeddingRefreshGeneration,
              insights == originalInsights, localSeedAnchors == originalSeeds,
              generatedChildInsights == originalChildren, placedMidpoints == originalMidpoints else { return }
        guard corrected != insights || correctedSeeds != localSeedAnchors
                || subjectEmbeddings != clusterSubjectEmbeddings
                || correctedChildren != generatedChildInsights || correctedMidpoints != midpointEmbeddings else { return }
        midpointEmbeddings = correctedMidpoints.filter { id, _ in originalMidpoints.contains { $0.concept.id == id } }
        insights = corrected
        localSeedAnchors = correctedSeeds
        clusterSubjectEmbeddings = subjectEmbeddings
        generatedChildInsights = correctedChildren
        persistMakeNodeChildren()
        rebuildTree()
        await graphBuildTask?.value
    }

    private func ensureEmbeddings(for insights: [InsightModel]) async -> [InsightModel] {
        var next = insights
        for index in next.indices {
            guard !Task.isCancelled else { return next }
            let stale = next[index].embedding == nil || next[index].embeddingVersion != embeddingProvider.version
            guard stale else { continue }
            let text = "\(next[index].title). \(next[index].definition)"
            next[index].embedding = await embeddingProvider.embed(text)
            next[index].embeddingVersion = embeddingProvider.version
        }
        return next
    }

    /// Generated children bypass ordinary membership preparation, but still need the same
    /// vector space before their connector lengths can represent relatedness to their parent.
    private func preparedChildren(_ children: [InsightModel], source: InsightModel) async -> [InsightModel] {
        let parent = await ensureEmbeddings(for: [source])[0]
        var children = await ensureEmbeddings(for: children)
        for index in children.indices {
            guard let vector = children[index].embedding, !vector.isEmpty,
                  let parentVector = parent.embedding, vector.count == parentVector.count else {
                children[index].distanceToNode = nil
                children[index].relatednessToNode = nil
                continue
            }
            let distance = semanticDistance(vector, parentVector)
            children[index].distanceToNode = distance
            children[index].relatednessToNode = 1 - distance
        }
        return children
    }

    /// Commits the canvas's live-simulated positions back into the model and persists them.
    /// Mutates positions in place without changing the node id set, so the canvas's body
    /// reconciliation is a no-op (no jump) and next launch restores the live layout.
    func commitLivePositions(_ positions: [UUID: CGPoint]) {
        var changed = false
        for index in nodes.indices {
            if let p = positions[nodes[index].id], nodes[index].position != p {
                nodes[index].position = p
                changed = true
            }
        }
        guard changed else { return }
        persistPositions(nodes)
        // A placed Midpoint's position is authoritative from `placedMidpoints`, not the position
        // store — every `rebuildTree()` reconstructs its Node fresh from `placed.position` (see
        // `appendPlacedMidpointNodes`), so a live-followed position (from rotate-dragging one of
        // its sources) needs updating here too or it reverts on the next rebuild.
        var midpointsChanged = false
        for index in placedMidpoints.indices {
            guard let p = positions[placedMidpoints[index].concept.id],
                  placedMidpoints[index].position != p else { continue }
            placedMidpoints[index] = PlacedMidpoint(
                concept: placedMidpoints[index].concept,
                position: p,
                sources: placedMidpoints[index].sources
            )
            midpointsChanged = true
        }
        if midpointsChanged {
            persistPlacedMidpoints()
        }
    }

    /// Places a new permanent insight node at an explicit world position, pinned (never moved
    /// by the force layout) and connected by a line to each source insight it was spawned from.
    func addPlacedMidpoint(concept: ConceptDefinition, at position: CGPoint, sources: [MidpointSource]) {
        placedMidpoints.append(PlacedMidpoint(concept: concept, position: position, sources: sources))
        persistPlacedMidpoints()
        rebuildTree()
    }

    /// Replaces a placed Midpoint's loading placeholder without changing its application-owned
    /// identity, position, or source connectors. Keeping the id stable prevents the canvas from
    /// treating the generated contents as a second Insight and replaying the entrance sequence.
    func replacePlacedMidpoint(id: UUID, with generatedConcept: ConceptDefinition) {
        guard let index = placedMidpoints.firstIndex(where: { $0.concept.id == id }) else {
            return
        }
        let placed = placedMidpoints[index]
        let replacement = ConceptDefinition(
            id: id,
            word: generatedConcept.word,
            partOfSpeech: generatedConcept.partOfSpeech,
            pronunciation: generatedConcept.pronunciation,
            meaning: generatedConcept.meaning,
            example: generatedConcept.example
        )
        placedMidpoints[index] = PlacedMidpoint(
            concept: replacement,
            position: placed.position,
            sources: placed.sources
        )
        persistPlacedMidpoints()
        rebuildTree()
    }

    func removePlacedMidpoint(id: UUID) {
        placedMidpoints.removeAll { $0.concept.id == id }
        persistPlacedMidpoints()
        rebuildTree()
    }

    func placedMidpointConcept(for id: UUID) -> ConceptDefinition? {
        placedMidpoints.first(where: { $0.concept.id == id })?.concept
    }

    func generateSuggestedNode(between nodeA: NodeModel, and nodeB: NodeModel) {
        let temporaryEdge = EdgeModel(
            id: UUID(),
            fromNodeID: nodeA.id,
            toNodeID: nodeB.id,
            distance: semanticDistance(nodeA.embedding, nodeB.embedding),
            isSuggested: false,
            showSuggestButton: true
        )
        generateSuggestedNode(for: temporaryEdge)
    }

    func dismissSuggestedNode(_ node: NodeModel) {
        withAnimation(.springRelaxed) {
            nodes.removeAll { $0.id == node.id }
            edges.removeAll { $0.fromNodeID == node.id || $0.toNodeID == node.id }
        }
        scene.render(nodes: nodes, edges: edges, animated: true)
    }

    func selectNode(_ node: NodeModel) {
        handleTappedNode(node)
    }

    func suggestConnection(for edge: EdgeModel) {
        generateSuggestedNode(for: edge)
    }

    private func handleTappedNode(_ node: NodeModel) {
        if node.isSuggested {
            selectedSuggestedNode = node
        } else {
            selectedNode = node
        }
    }

    private func generateSuggestedNode(for edge: EdgeModel) {
        guard let modelTasks else { return }
        guard let from = nodes.first(where: { $0.id == edge.fromNodeID }),
              let to = nodes.first(where: { $0.id == edge.toNodeID }) else {
            return
        }

        let midpointEmbedding = centroid([from.embedding, to.embedding])
        let suggestions = insights
            .filter { $0.embedding != nil && !Self.labelDescriptions(for: [$0]).isEmpty }
            .sorted { lhs, rhs in
                semanticDistance(lhs.embedding ?? [], midpointEmbedding) < semanticDistance(rhs.embedding ?? [], midpointEmbedding)
            }
            .prefix(3)

        let suggestionInsights = Array(suggestions)
        guard !suggestionInsights.isEmpty else { return }

        let descriptions = Self.labelDescriptions(for: suggestionInsights)
        modelTasks.enqueue(
            kind: .labelInsightTree,
            originPage: modelTaskOriginPage,
            conversationID: midpointStoreScope,
            priority: .background
        ) { [weak self] in
            guard let self,
                  let label = try? await model.labelSubject(forTitles: descriptions, excludingInsightTitles: suggestionInsights.map(\.title))
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !Task.isCancelled, !label.isEmpty,
                  nodes.contains(where: { $0.id == from.id }),
                  nodes.contains(where: { $0.id == to.id }) else { return }
            let suggestedNode = NodeModel(
                id: UUID(),
                conceptLabel: label,
                insights: suggestionInsights,
                embedding: centroid(suggestionInsights.compactMap(\.embedding)),
                position: CGPoint(
                    x: (from.position.x + to.position.x) / 2,
                    y: (from.position.y + to.position.y) / 2
                ),
                isSuggested: true,
                suggestedInsights: suggestionInsights
            )

            withAnimation(.springRelaxed) {
                self.nodes.removeAll { $0.isSuggested }
                self.edges.removeAll { $0.isSuggested }
                self.nodes.append(suggestedNode)
                self.edges.append(EdgeModel(id: UUID(), fromNodeID: from.id, toNodeID: suggestedNode.id, distance: 0.18, isSuggested: true, showSuggestButton: false))
                self.edges.append(EdgeModel(id: UUID(), fromNodeID: suggestedNode.id, toNodeID: to.id, distance: 0.18, isSuggested: true, showSuggestButton: false))
            }
            scene.render(nodes: nodes, edges: edges, animated: true)
        }
    }

    private func rebuildTree() {
        // Synchronous same-provider fallback: keeps the tree usable immediately (including
        // during `init`, which can't await). `refreshEmbeddingsIfNeeded`/`ensureEmbeddings` is
        // the versioned, async-capable path layered on top (see its doc comment).
        let embeddedInsights = insights.map { insight -> InsightModel in
            var copy = insight
            guard (modelTasks == nil || !usesBackgroundGraphWorker), copy.embedding == nil, embeddingProvider.version == NLEmbeddingProvider.version else { return copy }
            copy.embedding = computeEmbedding(for: "\(insight.title). \(insight.definition)")
            copy.embeddingVersion = NLEmbeddingProvider.version
            return copy
        }
        insights = embeddedInsights

        // The children spawned by "Make Node" (deterministic IDs) — used by the canvas to
        // give only these the icon-first loading mask + splay animation.
        makeNodeChildIDs = Set(promotedInsightIDs.flatMap { insightID -> [UUID] in
            let nodeID = promotedNodeID(for: insightID)
            return (0..<childCount(for: insightID)).map { makeNodeChildID(for: nodeID, index: $0) }
        })

        // A placed Midpoint gets auto-bookmarked (see `InsightTreeView.placeMidpointInsight`),
        // which feeds its concept right back into `insights` alongside every ordinary saved
        // Insight. Without this exclusion it also goes through normal clustering below and gets
        // folded into whichever existing Node it's semantically nearest to — showing up doubled:
        // once as its own pinned Midpoint node, and again as a member listed under some other
        // Node's description that it happens to resemble.
        let placedMidpointIDs = Set(placedMidpoints.map { $0.concept.id })
        let attachedMakeNodeIDs = activeMakeNodeBookmarkIDs
        let seedsReady = localSeedAnchors.allSatisfy {
            $0.embedding != nil
                && ($0.embeddingVersion ?? NLEmbeddingProvider.version) == embeddingProvider.version
        }
        let members = embeddedInsights.filter {
            let semanticReady = seedsReady && (embeddingProvider.version == NLEmbeddingProvider.version
                || ($0.embedding != nil && $0.embeddingVersion == embeddingProvider.version))
            return semanticReady && !placedMidpointIDs.contains($0.id) && !attachedMakeNodeIDs.contains($0.id)
        }
        let saved = Self.loadStoredPositions(storageKey: positionStoreKey)
        let positions = saved.reduce(into: [UUID: CGPoint]()) { output, entry in
            if let id = UUID(uuidString: entry.key) { output[id] = entry.value.cgPoint }
        }
        let input = SemanticTreeComputation(allInsights: embeddedInsights, localSeedAnchors: localSeedAnchors,
            insightClusterAssignments: insightClusterAssignments, clusterMergeTargets: clusterMergeTargets,
            clusterSubjectEmbeddings: clusterSubjectEmbeddings, generatedClusterLabels: generatedClusterLabels,
            generatedClusterDefinitions: generatedClusterDefinitions, positions: positions,
            providerVersion: embeddingProvider.version, localMembershipThreshold: localMembershipThreshold)
        graphRevision += 1
        let revision = graphRevision
        graphBuildTask?.cancel()
        if modelTasks != nil && usesBackgroundGraphWorker {
            graphBuildTask = Task { [weak self, graphWorker] in
                let result = await graphWorker.compute(input, members: members)
                guard let self, !Task.isCancelled, graphRevision == revision else { return }
                await applyGraphAsync(result, embeddedInsights: embeddedInsights, revision: revision)
            }
        } else {
            var state = input
            let graph = state.build(from: members)
            applyGraph(SemanticTreeResult(nodes: graph.nodes, edges: graph.edges,
                assignments: state.insightClusterAssignments, merges: state.clusterMergeTargets), embeddedInsights: embeddedInsights)
        }
    }

    private func applyGraphAsync(_ result: SemanticTreeResult, embeddedInsights: [InsightModel], revision: Int) async {
        var nextNodes = result.nodes
        var nextEdges = result.edges
        appendPromotedNodes(to: &nextNodes, edges: &nextEdges, from: embeddedInsights)
        appendPlacedMidpointNodes(to: &nextNodes, edges: &nextEdges)
        let relaxation = SemanticOverlapRelaxation(placedMidpointNodeIDs: placedMidpointNodeIDs,
            showsAllClusterInsights: showsAllClusterInsights)
        let relaxed = await graphWorker.relax(nextNodes, using: relaxation)
        guard !Task.isCancelled, revision == graphRevision else { return }
        applyGraph(result, embeddedInsights: embeddedInsights, preparedNodes: relaxed, preparedEdges: nextEdges, spawnNodes: nextNodes)
    }

    private func applyGraph(_ result: SemanticTreeResult, embeddedInsights: [InsightModel], preparedNodes: [NodeModel]? = nil, preparedEdges: [EdgeModel]? = nil, spawnNodes: [NodeModel]? = nil) {
        insightClusterAssignments = result.assignments
        if clusterMergeTargets != result.merges {
            clusterMergeTargets = result.merges
            InsightTreeLocalStateStore.save(
                Dictionary(uniqueKeysWithValues: result.merges.map { ($0.key.uuidString, $0.value.uuidString) }),
                key: scopedClusterMergeStoreKey)
        }
        persistInsightClusterAssignments()
        var nextNodes = preparedNodes ?? result.nodes
        var nextEdges = preparedEdges ?? result.edges
        if preparedNodes == nil {
            appendPromotedNodes(to: &nextNodes, edges: &nextEdges, from: embeddedInsights)
            appendPlacedMidpointNodes(to: &nextNodes, edges: &nextEdges)
            adoptSpawnTargets(for: nextNodes)
            nextNodes = separateOverlaps(nodes: nextNodes)
        }
        if let spawnNodes { adoptSpawnTargets(for: spawnNodes) }
        persistPositions(nextNodes)
        recomputeBondLengths(for: nextNodes)

        let nextIDs = Set(nextNodes.map(\.id))
        let hasNew = !nextIDs.isSubset(of: renderedNodeIDs)
        renderedNodeIDs = nextIDs
        withAnimation(.springRelaxed) {
            nodes = nextNodes
            edges = nextEdges
        }
        scene.render(nodes: nodes, edges: edges, animated: hasNew)
        requestClusterLabels(for: nextNodes)
    }

    /// Bond length per visible insight = relatedness (semantic distance) to its parent node's
    /// centroid embedding. Midpoint nodes (bare center chip) are skipped.
    ///
    /// Membership in a Node already requires distance below `localMembershipThreshold`'s
    /// complement — every insight under the same Node sits in a narrow absolute slice of that
    /// range (tighter still for a well-matched cluster), which used to feed `insightBondLength`
    /// directly: real, meaningful differences in relatedness compressed into a handful of pixels,
    /// reading as "every bond is the same length." Stretching each Node's own distances to fill
    /// the full [0, 1] range before mapping to pixels keeps the *relative* ordering (this insight
    /// is closer than that one) visible regardless of how tightly clustered the absolute values
    /// happen to be.
    private func recomputeBondLengths(for nodes: [NodeModel]) {
        var lengths: [UUID: CGFloat] = [:]
        for node in nodes where !placedMidpointNodeIDs.contains(node.id) {
            let distances: [(id: UUID, distance: Double)] = canvasInsights(for: node).compactMap { insight in
                if let distance = insight.distanceToNode { return (insight.id, distance) }
                guard let vector = insight.embedding, !vector.isEmpty,
                      vector.count == node.embedding.count else {
                    // Missing embeddings mean unknown relatedness, not maximum separation.
                    lengths[insight.id] = 190
                    return nil
                }
                return (insight.id, semanticDistance(vector, node.embedding))
            }
            let range = distances.map(\.distance)
            guard let minDist = range.min(), let maxDist = range.max(), maxDist > minDist else {
                for entry in distances { lengths[entry.id] = insightBondLength(entry.distance) }
                continue
            }
            for entry in distances {
                let normalized = (entry.distance - minDist) / (maxDist - minDist)
                lengths[entry.id] = insightBondLength(normalized)
            }
        }
        insightBondLengths = lengths
    }

    /// Groups Insights around semantic subject Nodes in the on-device embedding space.
    /// `localSeedAnchors` (on-device Node-seed labels — see `setLocalSeedAnchors`) seed this
    /// clustering as pre-existing, always-rendered clusters: an Insight within the same
    /// similarity threshold attaches under the seeded subject instead of spawning its own
    /// cluster, and an anchor with zero attached Insights still renders as its own Node so the
    /// seeded subject never just disappears once real Insights exist.
    /// Empty placeholders must never become model input such as ": ".
    private static func labelDescriptions(for insights: [InsightModel]) -> [String] {
        insights.compactMap { insight in
            let title = insight.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let definition = insight.definition.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty || !definition.isEmpty else { return nil }
            return [title, definition].filter { !$0.isEmpty }.joined(separator: ": ")
        }
    }

    private func requestClusterLabels(for clusters: [NodeModel]) {
        // Previews without the shared queue remain static; never create a competing queue.
        guard modelWorkStarted, let modelTasks else { return }
        let seedLabels = Dictionary(localSeedAnchors.map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first })
        // Make Node is an explicit promotion; its chosen title is intentional. Midpoints are
        // single Insights rendered without a parent circle, not automatically named clusters.
        let explicitNodeIDs = Set(promotedInsightIDs.map { promotedNodeID(for: $0) }).union(promotedInsightIDs).union(placedMidpointNodeIDs)
        for cluster in clusters where !explicitNodeIDs.contains(cluster.id) {
            let subjects = Self.labelDescriptions(for: cluster.insights)
            let existingLabel = generatedClusterLabels[cluster.id] ?? seedLabels[cluster.id]
            let needsLabel = existingLabel.map {
                NodeConceptLabelPolicy.repeatsInsightTitle($0, insightTitles: cluster.insights.map(\.title))
            } ?? true
            guard !subjects.isEmpty, needsLabel,
                  clusterLabelGenerationInFlight.insert(cluster.id).inserted else { continue }
            let nodeID = cluster.id
            modelTasks.enqueue(
                kind: .labelInsightTree,
                originPage: modelTaskOriginPage,
                conversationID: midpointStoreScope,
                priority: .background,
                onCancel: { [weak self] in
                    self?.clusterLabelGenerationInFlight.remove(nodeID)
                }
            ) { [weak self] in
                guard let self else { return }
                // Preemption preserves the job for retry. Only explicit cancellation (above)
                // or a finished attempt releases the dedupe reservation.
                defer {
                    if !Task.isCancelled { clusterLabelGenerationInFlight.remove(nodeID) }
                }
                guard nodes.contains(where: { $0.id == nodeID }) else { return }
                do {
                    let label: String
                    let currentInsights = nodes.first(where: { $0.id == nodeID })?.insights ?? []
                    let currentSubjects = Self.labelDescriptions(for: currentInsights)
                    guard !currentSubjects.isEmpty else { return }
                    if let cached = generatedClusterLabels[nodeID],
                       NodeConceptLabelPolicy.isValid(cached, insightTitles: currentInsights.map(\.title)) {
                        label = cached
                    } else {
                        label = try await model.labelSubject(
                            forTitles: currentSubjects,
                            excludingInsightTitles: currentInsights.map(\.title)
                        )
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    try Task.checkCancellation()
                    guard !label.isEmpty,
                          let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
                    guard NodeConceptLabelPolicy.isValid(label, insightTitles: nodes[index].insights.map(\.title)) else { return }
                    if generatedClusterLabels[nodeID] != label {
                        generatedClusterDefinitions.removeValue(forKey: nodeID)
                        persistClusterDefinitions()
                        nodes[index].definition = ""
                    }
                    generatedClusterLabels[nodeID] = label
                    persistClusterLabels()
                    nodes[index].conceptLabel = label
                    if selectedNode?.id == nodeID {
                        selectedNode?.conceptLabel = label
                        selectedNode?.definition = nodes[index].definition
                    }
                    scene.render(nodes: nodes, edges: edges, animated: false)
                    // Keep the definition inside the same queue job and runtime lease.
                    try await generateClusterDefinition(for: nodeID, label: label)
                    // A named subject can now be compared with its neighbors for merging.
                    refreshEmbeddingsIfNeeded()
                } catch {
                    // Failed labels can be retried on the next rebuild.
                }
            }
        }
    }

    private func generateClusterDefinition(for nodeID: UUID, label: String) async throws {
        guard generatedClusterDefinitions[nodeID] == nil else { return }
        let concept = try await model.defineTerm(label, in: ConversationContext())
        try Task.checkCancellation()
        guard !concept.meaning.isEmpty,
              let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        generatedClusterDefinitions[nodeID] = concept.meaning
        persistClusterDefinitions()
        nodes[index].definition = concept.meaning
        if selectedNode?.id == nodeID {
            selectedNode?.definition = concept.meaning
        }
    }

    private func promotionChildren(for insight: InsightModel) -> [InsightModel] {
        let nodeID = promotedNodeID(for: insight.id)
        if let children = generatedChildInsights[nodeID] { return children }
        let placeholders = (0..<childCount(for: insight.id)).map { index in
            InsightModel(id: makeNodeChildID(for: nodeID, index: index), title: "", definition: "")
        }
        requestChildren(for: insight, promotedNodeID: nodeID)
        return placeholders
    }

    private func appendPromotedNodes(
        to nodes: inout [NodeModel],
        edges: inout [EdgeModel],
        from embeddedInsights: [InsightModel]
    ) {
        guard !promotedInsightIDs.isEmpty else { return }

        for insightID in promotedInsightIDs {
            guard let sourceIndex = nodes.firstIndex(where: { $0.insights.contains(where: { $0.id == insightID }) }),
                  let insight = nodes[sourceIndex].insights.first(where: { $0.id == insightID }) else {
                // Midpoints are also Insights. Their owning parents are the original source
                // nodes; replace the midpoint chip and retain those connections after Branch.
                guard branchInsightCounts[insightID] != nil,
                      let placed = placedMidpoints.first(where: { $0.concept.id == insightID }) else { continue }
                let source = InsightModel(concept: placed.concept)
                let nodeID = promotedNodeID(for: insightID)
                let parentIDs = Set(placed.sources.compactMap { source -> UUID? in
                    nodes.first { node in
                        source.isNode ? node.id == source.insightID
                            : node.insights.contains { $0.id == source.insightID }
                                || node.id == promotedNodeID(for: source.insightID)
                    }?.id
                })
                nodes.append(NodeModel(id: nodeID, conceptLabel: source.title, definition: source.definition,
                    insights: promotionChildren(for: source), embedding: source.embedding ?? [],
                    position: restoredPosition(for: nodeID) ?? placed.position,
                    isSuggested: false, suggestedInsights: nil))
                for parentID in parentIDs {
                    edges.append(EdgeModel(id: stableUUID(from: "branch-parent:\(parentID):\(nodeID)"), fromNodeID: parentID, toNodeID: nodeID,
                                           distance: 0.18, isSuggested: false, showSuggestButton: false))
                }
                continue
            }
            let sourceNode = nodes[sourceIndex]
            let promotedNodeID = promotedNodeID(for: insightID)
            let childInsights = promotionChildren(for: insight)

            // If the insight already is its own node (canvas early layout), convert it in
            // place so the insight itself becomes the concept — no duplicate node beside it.
            if sourceNode.id == insightID && sourceNode.insights.count == 1 && branchInsightCounts[insightID] == nil {
                nodes[sourceIndex].conceptLabel = insight.title
                nodes[sourceIndex].definition = insight.definition
                nodes[sourceIndex].insights = childInsights
                continue
            }

            guard !nodes.contains(where: { $0.id == promotedNodeID }) else { continue }

            // Clustered layout: pull the insight out into its own node, extending the chain from
            // its source node, and remove it from the cluster so it isn't shown twice.
            let chainPos = chainExtensionPosition(from: sourceNode, nodes: nodes, edges: edges)
            nodes[sourceIndex].insights.removeAll { $0.id == insightID }

            let promotedNode = NodeModel(
                id: promotedNodeID,
                conceptLabel: insight.title,
                definition: insight.definition,
                insights: childInsights,
                embedding: insight.embedding ?? [],
                position: restoredPosition(for: promotedNodeID) ?? chainPos,
                isSuggested: false,
                suggestedInsights: nil
            )

            nodes.append(promotedNode)
            edges.append(
                EdgeModel(
                    id: stableUUID(from: "promotion-parent:\(sourceNode.id):\(promotedNodeID)"),
                    fromNodeID: sourceNode.id,
                    toNodeID: promotedNodeID,
                    distance: 0.18,
                    isSuggested: false,
                    showSuggestButton: false
                )
            )
        }
    }

    /// Requests the real Make Node children once per promoted node. Generated content replaces
    /// the identity-only children in place, then publishes readiness after the rebuilt nodes are
    /// available so the canvas can safely begin its camera tour.
    private func requestChildren(for insight: InsightModel, promotedNodeID: UUID) {
        guard modelWorkStarted else { return }
        guard childGenerationInFlight.insert(promotedNodeID).inserted else { return }
        Task { @MainActor in
            do {
                try await generateMakeNodeChildren(
                    for: insight,
                    promotedNodeID: promotedNodeID
                )
            } catch {
                cancelMakeNodeGeneration(for: insight.id)
            }
        }
    }

    /// Reserves the generation slot before a queued Make Node task publishes its promoted id.
    /// This prevents the normal tree rebuild from launching an untracked duplicate request.
    func reserveMakeNodeGeneration(for insightID: UUID, branchCount: Int? = nil) {
        if let branchCount {
            guard (2...6).contains(branchCount) else { return }
            branchInsightCounts[insightID] = branchCount
            persistBranchCounts()
        }
        childGenerationInFlight.insert(promotedNodeID(for: insightID))
        if !promotedInsightIDs.contains(insightID) {
            promotedInsightIDs.append(insightID)
        }
        rebuildTree()
    }

    func generateReservedMakeNodeChildren(
        for insight: InsightModel
    ) async throws {
        try await generateMakeNodeChildren(
            for: insight,
            promotedNodeID: promotedNodeID(for: insight.id)
        )
    }

    func cancelMakeNodeGeneration(for insightID: UUID) {
        let nodeID = promotedNodeID(for: insightID)
        promotedInsightIDs.removeAll { $0 == insightID }
        childGenerationInFlight.remove(nodeID)
        generatedChildInsights.removeValue(forKey: nodeID)
        persistMakeNodeChildren()
        generatedMakeNodeChildIDs.subtract(
            (0..<6).map { makeNodeChildID(for: nodeID, index: $0) }
        )
        branchInsightCounts.removeValue(forKey: insightID)
        persistBranchCounts()
        rebuildTree()
    }

    /// The bookmark records represented by a completed Make Node action: the promoted node
    /// concept itself followed by its generated child Insights.
    func makeNodeBookmarkConcepts(for insightID: UUID) -> [ConceptDefinition] {
        let generatedNodeID = promotedNodeID(for: insightID)
        guard let source = insights.first(where: { $0.id == insightID })
                ?? placedMidpoints.first(where: { $0.concept.id == insightID }).map({ InsightModel(concept: $0.concept) }),
              let children = generatedChildInsights[generatedNodeID] else {
            return []
        }

        // The promoted Node retains the bookmark identity of the source Insight. This avoids
        // creating two library records with the same word (the library intentionally merges
        // same-word definitions) and makes unbookmarking the Node remove its original anchor.
        let nodeConcept = ConceptDefinition(
            id: source.id,
            word: source.title,
            partOfSpeech: "",
            pronunciation: "",
            meaning: source.definition,
            example: ""
        )
        return [nodeConcept] + children.map(Self.concept(for:))
    }

    func promotedSourceInsightID(forNodeID nodeID: UUID) -> UUID? {
        promotedInsightIDs.first { insightID in
            if promotedNodeID(for: insightID) == nodeID { return true }
            guard insightID == nodeID,
                  let node = nodes.first(where: { $0.id == nodeID }) else { return false }
            let generatedIDs = Set(
                generatedChildInsights[promotedNodeID(for: insightID)]?.map(\.id) ?? []
            )
            return !generatedIDs.isEmpty && node.insights.contains { generatedIDs.contains($0.id) }
        }
    }

    func removeMakeNodeChild(id childID: UUID) {
        guard let entry = generatedChildInsights.first(where: {
            $0.value.contains(where: { $0.id == childID })
        }) else { return }
        generatedChildInsights[entry.key]?.removeAll { $0.id == childID }
        generatedMakeNodeChildIDs.remove(childID)
        persistMakeNodeChildren()
        rebuildTree()
    }

    /// Removes a promoted node. Kept children are assigned to the semantically nearest remaining
    /// node before the promotion is released, so their next ordinary-tree rebuild has a stable,
    /// intentional home instead of depending on insertion order.
    func removeMakeNode(for insightID: UUID, keepingChildren: Bool) {
        let nodeID = promotedNodeID(for: insightID)
        let children = generatedChildInsights[nodeID] ?? []
        if keepingChildren {
            let candidates = nodes.filter {
                promotedSourceInsightID(forNodeID: $0.id) == nil
                    && !$0.insights.isEmpty
                    && !$0.embedding.isEmpty
            }
            for child in children {
                guard let embedding = child.embedding
                    ?? computeEmbedding(for: "\(child.title). \(child.definition)"),
                    !embedding.isEmpty,
                    let nearest = candidates.min(by: {
                    semanticDistance(embedding, $0.embedding)
                        < semanticDistance(embedding, $1.embedding)
                }) else { continue }
                insightClusterAssignments[child.id] = nearest.id
            }
            persistInsightClusterAssignments()
        }
        cancelMakeNodeGeneration(for: insightID)
    }

    private var activeMakeNodeBookmarkIDs: Set<UUID> {
        Set(promotedInsightIDs.map { promotedNodeID(for: $0) })
            .union(generatedChildInsights.values.flatMap { $0.map(\.id) })
    }

    private func generateMakeNodeChildren(
        for insight: InsightModel,
        promotedNodeID: UUID
    ) async throws {
        let sourceConcept = ConceptDefinition(
            word: insight.title,
            partOfSpeech: "",
            pronunciation: "",
            meaning: insight.definition,
            example: ""
        )
        let generated: [ConceptDefinition]
        do {
            if let count = branchInsightCounts[insight.id] {
                generated = try await model.generateChildren(for: sourceConcept, count: count)
            } else {
                generated = try await model.generateChildren(for: sourceConcept)
            }
        } catch {
            childGenerationInFlight.remove(promotedNodeID)
            throw error
        }
        guard !Task.isCancelled, promotedInsightIDs.contains(insight.id) else {
            childGenerationInFlight.remove(promotedNodeID)
            return
        }
        guard generated.count == childCount(for: insight.id) else {
            childGenerationInFlight.remove(promotedNodeID)
            throw AngroveModelActionError.invalidResponse
        }
        let rawChildren = generated.enumerated().map { index, concept in
            return InsightModel(
                id: makeNodeChildID(for: promotedNodeID, index: index),
                title: concept.word,
                definition: concept.meaning
            )
        }
        let children = await preparedChildren(rawChildren, source: insight)
        try Task.checkCancellation()
        guard promotedInsightIDs.contains(insight.id) else {
            childGenerationInFlight.remove(promotedNodeID)
            return
        }
        generatedChildInsights[promotedNodeID] = children
        persistMakeNodeChildren()
        childGenerationInFlight.remove(promotedNodeID)
        rebuildTree()
        generatedMakeNodeChildIDs.formUnion(children.map(\.id))
    }

    private static func concept(for insight: InsightModel) -> ConceptDefinition {
        ConceptDefinition(
            id: insight.id,
            word: insight.title,
            partOfSpeech: "",
            pronunciation: "",
            meaning: insight.definition,
            example: ""
        )
    }

    /// Appends user-placed midpoint nodes at their pinned positions, each connected by an edge
    /// to every source concept it was spawned from. Runs AFTER the force layout so these nodes
    /// are never relocated.
    private func appendPlacedMidpointNodes(to nodes: inout [NodeModel], edges: inout [EdgeModel]) {
        placedMidpointNodeIDs = Set(placedMidpoints.map { $0.concept.id })
        placedMidpointSources = Dictionary(placedMidpoints.map { ($0.concept.id, $0.sources) }, uniquingKeysWith: { _, latest in latest })
        guard !placedMidpoints.isEmpty else { return }

        for placed in placedMidpoints {
            if branchInsightCounts[placed.concept.id] != nil,
               promotedInsightIDs.contains(placed.concept.id) { continue }
            let nodeID = placed.concept.id
            guard !nodes.contains(where: { $0.id == nodeID }) else { continue }

            let insight = InsightModel(concept: placed.concept)
            let placedNode = NodeModel(
                id: nodeID,
                conceptLabel: placed.concept.word,
                insights: [insight],
                embedding: midpointEmbeddings[nodeID]?.vector
                    ?? ((modelTasks == nil || !usesBackgroundGraphWorker) ? computeEmbedding(for: "\(insight.title). \(insight.definition)") : nil) ?? [],
                position: placed.position,
                isSuggested: false,
                suggestedInsights: nil
            )

            // Connector lines are drawn by the canvas directly to each source insight chip /
            // node concept (see placedMidpointSources), not as generic node-to-node edges.
            nodes.append(placedNode)
        }
    }

    /// Where a newly promoted Node Concept spawns: extending the chain it's growing from, one
    /// link at a time (like a carbon adding onto a lipid tail), rather than orbiting its source
    /// at a semantically-meaningless angle. A node with no existing bonds — the chain's root —
    /// starts growing straight up. A node with two or more existing bonds is a real branch point,
    /// so the new bond bisects the largest open angular gap among them (VSEPR-style maximum
    /// separation). This is a placeholder: once the model drives relation-based folding between
    /// concepts, that will replace this simple maximized-angle continuation.
    ///
    /// A node with EXACTLY one existing bond is the plain-chain case, and deliberately does NOT
    /// use that same maximized-gap rule: with only one angle to separate from, "maximize
    /// separation" is just its exact opposite (180°) — so a simple chain (which is what most
    /// on-device Node-seed growth actually is, one seed per conversation turn) continued dead
    /// straight forever, however many links long. `chainBendDirection` alternates a small bend
    /// left/right at each link instead, so the chain reads as an organic curve/branch rather than
    /// a straight line down the canvas.
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

    /// Effective footprint radius of a node (its concept circle + the ring of orbiting chips),
    /// used to keep whole nodes from overlapping during the separation pass.
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

    /// Gently pushes apart only the nodes whose footprints overlap, starting from their current
    /// positions. Pinned midpoint nodes stay fixed (neighbors move around them). A no-op when
    /// nothing overlaps, so a settled tree never moves.
    private func separateOverlaps(nodes: [NodeModel]) -> [NodeModel] {
        SemanticOverlapRelaxation(placedMidpointNodeIDs: placedMidpointNodeIDs,
            showsAllClusterInsights: showsAllClusterInsights).solve(nodes: nodes)
    }

    private func makeNodeChildID(for nodeID: UUID, index: Int) -> UUID {
        stableUUID(from: "makenode-child:\(nodeID.uuidString):\(index)")
    }

    func promotedNodeID(for insightID: UUID) -> UUID {
        stableUUID(from: "promoted:\(insightID.uuidString)")
    }

    /// Embedding-driven layout: positions every non-pinned node at its semantic (MDS) target
    /// so on-screen distance reflects semantic distance. Publishes `layoutTargets` (the raw
    /// targets, before overlap separation) and `nodeDepths` for the canvas. Nodes without an
    /// embedding fall back to previous/restored position → graph-neighbor centroid → radial seed.
    private func runSemanticLayout(nodes: [NodeModel], edges: [EdgeModel]) -> [NodeModel] {
        var working = nodes
        guard working.count > 1 else {
            layoutTargets = Dictionary(working.map { ($0.id, $0.position) }, uniquingKeysWith: { _, latest in latest })
            nodeDepths = [:]
            return working
        }

        var previous: [UUID: CGPoint] = [:]
        for node in working {
            previous[node.id] = restoredPosition(for: node.id) ?? node.position
        }

        let result = SemanticLayout.solve(
            nodes: working,
            pinnedIDs: placedMidpointNodeIDs,
            previousPositions: previous
        )

        var targets: [UUID: CGPoint] = [:]
        for index in working.indices {
            let node = working[index]
            if placedMidpointNodeIDs.contains(node.id) {
                targets[node.id] = node.position   // user-pinned: never relocated
                continue
            }
            if let solved = result.positions[node.id] {
                working[index].position = solved
                targets[node.id] = solved
                continue
            }
            // No embedding: keep the previous position if one exists; otherwise sit near
            // the centroid of graph neighbors (small deterministic offset breaks ties),
            // falling back to the radial seed the node already carries.
            if let prev = previous[node.id] {
                targets[node.id] = prev
                working[index].position = prev
            } else {
                let neighborIDs = edges.compactMap { edge -> UUID? in
                    if edge.fromNodeID == node.id { return edge.toNodeID }
                    if edge.toNodeID == node.id { return edge.fromNodeID }
                    return nil
                }
                let neighborPoints = neighborIDs.compactMap { id in
                    result.positions[id] ?? previous[id]
                }
                if !neighborPoints.isEmpty {
                    let cx = neighborPoints.reduce(0) { $0 + $1.x } / CGFloat(neighborPoints.count)
                    let cy = neighborPoints.reduce(0) { $0 + $1.y } / CGFloat(neighborPoints.count)
                    let offset = CGFloat(index % 4) * 40 + 80
                    working[index].position = CGPoint(x: cx + offset, y: cy - offset / 2)
                }
                targets[node.id] = working[index].position
            }
        }

        layoutTargets = targets
        nodeDepths = result.depth
        return working
    }

    /// Nodes appended after the semantic solve (promoted / placed midpoints) anchor at
    /// their spawn position until the next rebuild folds them into the MDS solve proper.
    private func adoptSpawnTargets(for nodes: [NodeModel]) {
        for node in nodes where layoutTargets[node.id] == nil {
            layoutTargets[node.id] = node.position
        }
    }

    /// The position store's one key is shared across every Insight Tree instance — the global
    /// tree and every per-conversation tree — keyed by node id. Always read-modify-write through
    /// this pair (`loadStoredPositions`/`persistPositions`) rather than replacing the value
    /// outright, or one tree's rebuild silently wipes every other tree's saved positions.
    /// Write-through cache of the position file. A rebuild restores one position per node, and
    /// reading and decoding the file for each of them stalled the main thread on large trees.
    private static var storedPositionsCache: [String: [String: CodablePoint]] = [:]

    private static func loadStoredPositions(storageKey: String) -> [String: CodablePoint] {
        if let cached = storedPositionsCache[storageKey] { return cached }
        let stored = InsightTreeLocalStateStore.load(
            [String: CodablePoint].self,
            key: storageKey
        ) ?? [:]
        storedPositionsCache[storageKey] = stored
        return stored
    }

    private func restoredPosition(for id: UUID) -> CGPoint? {
        Self.loadStoredPositions(storageKey: positionStoreKey)[id.uuidString]?.cgPoint
    }

    private func persistPositions(_ nodes: [NodeModel]) {
        var positions = Self.loadStoredPositions(storageKey: positionStoreKey)
        for node in nodes {
            positions[node.id.uuidString] = CodablePoint(node.position)
        }
        Self.storedPositionsCache[positionStoreKey] = positions
        InsightTreeLocalStateStore.save(positions, key: positionStoreKey)
    }

    private static func loadClusterLabels(storageKey: String) -> [UUID: String] {
        guard let stored = InsightTreeLocalStateStore.load(
            [String: String].self,
            key: storageKey
        ) else { return [:] }
        return stored.reduce(into: [:]) { result, entry in
            guard let id = UUID(uuidString: entry.key) else { return }
            result[id] = entry.value
        }
    }

    private func persistClusterLabels() {
        let stored = Dictionary(
            uniqueKeysWithValues: generatedClusterLabels.map {
                ($0.key.uuidString, $0.value)
            }
        )
        InsightTreeLocalStateStore.save(stored, key: Self.clusterLabelStoreKey)
    }

    private func persistClusterDefinitions() {
        let stored = Dictionary(
            uniqueKeysWithValues: generatedClusterDefinitions.map {
                ($0.key.uuidString, $0.value)
            }
        )
        InsightTreeLocalStateStore.save(stored, key: Self.clusterDefinitionStoreKey)
    }

    private static func loadUUIDMapping(storageKey: String) -> [UUID: UUID] {
        guard let stored = InsightTreeLocalStateStore.load(
            [String: String].self,
            key: storageKey
        ) else { return [:] }
        return stored.reduce(into: [:]) { result, entry in
            guard let key = UUID(uuidString: entry.key), let value = UUID(uuidString: entry.value) else { return }
            result[key] = value
        }
    }

    private func persistInsightClusterAssignments() {
        let stored = Dictionary(
            uniqueKeysWithValues: insightClusterAssignments.map {
                ($0.key.uuidString, $0.value.uuidString)
            }
        )
        InsightTreeLocalStateStore.save(
            stored,
            key: scopedClusterAssignmentStoreKey
        )
    }

    /// Placed Midpoints previously lived only in memory — reopening the tree (navigating away and
    /// back re-creates this view model from scratch) dropped `placedMidpoints` back to empty, so
    /// the Midpoint's own auto-bookmarked concept fell through to ordinary clustering instead of
    /// staying a pinned node connected to its two sources. Persisting them the same way positions
    /// and cluster labels already are fixes that.
    private static func loadPlacedMidpoints(storageKey: String) -> [PlacedMidpoint] {
        guard let stored = InsightTreeLocalStateStore.load(
            [CodablePlacedMidpoint].self,
            key: storageKey
        ) else { return [] }
        return stored.map {
            PlacedMidpoint(concept: $0.concept, position: $0.position.cgPoint, sources: $0.sources)
        }
    }

    private func persistPlacedMidpoints() {
        let stored = placedMidpoints.map {
            CodablePlacedMidpoint(concept: $0.concept, position: CodablePoint($0.position), sources: $0.sources)
        }
        InsightTreeLocalStateStore.save(stored, key: placedMidpointStoreKey)
    }

    private static func loadMakeNodeChildren(storageKey: String) -> [UUID: [InsightModel]] {
        guard let stored = InsightTreeLocalStateStore.load(
            [String: [InsightModel]].self,
            key: storageKey
        ) else { return [:] }
        return stored.reduce(into: [:]) { result, entry in
            guard let id = UUID(uuidString: entry.key) else { return }
            result[id] = entry.value
        }
    }

    private func persistMakeNodeChildren() {
        let stored = Dictionary(
            uniqueKeysWithValues: generatedChildInsights.map { ($0.key.uuidString, $0.value) }
        )
        InsightTreeLocalStateStore.save(stored, key: makeNodeChildrenStoreKey)
    }

}

/// Deterministic UUID from a seed string (SHA-256, truncated to the first 16 bytes formatted as a
/// standard UUID) — the same input always yields the same id. Callers that need a stable identity
/// derived from content (a term, a promoted node, a generated child) use this instead of inventing
/// and tracking their own id-generation scheme. See MODEL-INTEGRATION.md: "Persistent IDs:
/// generated by application code, never by either model."
nonisolated func stableUUID(from seed: String) -> UUID {
    let digest = SHA256.hash(data: Data(seed.utf8))
    let bytes = Array(digest.prefix(16))
    let uuidString = String(
        format: "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5],
        bytes[6], bytes[7],
        bytes[8], bytes[9],
        bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
    )
    return UUID(uuidString: uuidString) ?? UUID()
}

nonisolated func computeEmbedding(for text: String) -> [Double]? {
    if let embedding = NLEmbedding.sentenceEmbedding(for: .english),
       let vector = embedding.vector(for: text) {
        return vector
    }

    var buckets = Array(repeating: 0.0, count: 64)
    for scalar in text.lowercased().unicodeScalars {
        let index = Int(scalar.value) % buckets.count
        buckets[index] += 1
    }
    return buckets
}

nonisolated func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
    guard a.count == b.count else { return 0 }
    // This runs for every pair during clustering and semantic layout. Avoid the three
    // intermediate arrays previously created by `zip(...).map` and the two `map` calls.
    var dot = 0.0
    var squaredMagnitudeA = 0.0
    var squaredMagnitudeB = 0.0
    for index in a.indices {
        let valueA = a[index]
        let valueB = b[index]
        dot += valueA * valueB
        squaredMagnitudeA += valueA * valueA
        squaredMagnitudeB += valueB * valueB
    }
    let magA = sqrt(squaredMagnitudeA)
    let magB = sqrt(squaredMagnitudeB)
    guard magA > 0, magB > 0 else { return 0 }
    return dot / (magA * magB)
}

nonisolated func semanticDistance(_ a: [Double], _ b: [Double]) -> Double {
    1.0 - cosineSimilarity(a, b)
}

nonisolated let nodeNodeMinLength: CGFloat = 360
nonisolated private let nodeNodeDistanceScale: CGFloat = 320

nonisolated func mapDistanceToLength(_ distance: Double) -> CGFloat {
    nodeNodeMinLength + CGFloat(max(distance, 0)) * nodeNodeDistanceScale
}

/// Bond length (insight connector radius) from how related an insight is to its parent node.
/// More related (smaller distance) → shorter bond; floored so close chips don't crowd the node.
nonisolated func insightBondLength(_ distance: Double) -> CGFloat {
    150 + CGFloat(min(max(distance, 0), 1)) * 180   // ~[150, 330]px
}

nonisolated func centroid(_ vectors: [[Double]]) -> [Double] {
    guard let first = vectors.first, !first.isEmpty else { return [] }
    var result = Array(repeating: 0.0, count: first.count)
    for vector in vectors where vector.count == first.count {
        for index in vector.indices {
            result[index] += vector[index]
        }
    }
    return result.map { $0 / Double(max(vectors.count, 1)) }
}

private struct CodablePoint: Codable {
    let x: CGFloat
    let y: CGFloat

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}
