import SwiftUI
import UIKit
import simd

// Discovery behavior for the shared global and conversation canvas.
extension InsightTreeCanvasView {
    // MARK: - New-Insight Entrance Sequence

    func visibleInsightIDs(in nodes: [NodeModel]) -> Set<UUID> {
        Set(nodes.flatMap { node in
            canvasInsights(for: node).map(\.id)
        })
    }

    func loadSeenInsightIDs() -> Set<UUID> {
        InsightDiscoveryStore.loadSeenInsightIDs()
    }

    /// Merges this open's visible insights into the persisted "seen" set — never replaces it.
    /// `seenInsightIDsKey` is one shared persisted set across every Insight Tree instance (the
    /// Global tree and every per-conversation tree), and the same saved Insight can legitimately
    /// appear in more than one of them. A plain overwrite here dropped every OTHER tree's
    /// previously-seen insights the moment this tree opened — so tapping an insight to clear its
    /// blue dot, then opening a different tree containing that same insight and coming back,
    /// re-flagged it "new" on `computeNewInsights()`'s next diff and put the dot right back.
    func saveAllInsightIDsAsSeen() {
        let ids = Set(nodes.flatMap { $0.insights }.map(\.id))
        InsightDiscoveryStore.markPresented(insightIDs: ids, nodeIDs: Set(nodes.map(\.id)))
    }

    /// Returns insights that weren't present the last time InsightTree was opened.
    /// Returns empty on the very first open (no persisted state yet).
    func computeNewInsights() -> [InsightModel] {
        let seenIDs = loadSeenInsightIDs()
        guard !seenIDs.isEmpty else { return [] }
        return nodes.flatMap { node in
            canvasInsights(for: node).filter { !seenIDs.contains($0.id) }
        }
    }

    /// Establishes the first seeded snapshot as the camera baseline, then tours only content
    /// introduced by later mutations. This prevents the temporary in-memory build from
    /// consuming the update animation before the seeded load finishes.
    func presentPersistedTree(animated: Bool, in size: CGSize) {
        revealState.entranceTask?.cancel()

        let currentInsightIDs = visibleInsightIDs(in: nodes)
        let currentNodeIDs = Set(nodes.map(\.id))
        // A live refresh uses the diff from the previously applied snapshot. If the update
        // completed while Canvas was closed, consume the exact persisted presentation targets
        // instead of treating the entire first snapshot as new.
        let pendingInsightIDs = InsightDiscoveryStore.pendingInsightPresentationIDs()
            .intersection(currentInsightIDs)
        let pendingNodeIDs = InsightDiscoveryStore.pendingNodePresentationIDs()
            .intersection(currentNodeIDs)
        let changedInsightIDs = InsightDiscoveryStore.newInsightIDs(
            in: currentInsightIDs,
            excluding: revealState.confirmedPersistedInsightIDs
        )
        let changedNodeIDs = InsightDiscoveryStore.newNodeIDs(
            in: currentNodeIDs,
            excluding: revealState.confirmedPersistedNodeIDs,
            memberInsightIDs: Dictionary(uniqueKeysWithValues: nodes.map {
                ($0.id, Set($0.insights.map(\.id)))
            })
        )
        // In-app mutations record their exact presentation targets. Intersecting those with
        // the snapshot diff prevents a first-load race from touring older content. Keep the
        // raw diff as a fallback for tree changes that recorded no presentation targets.
        let newInsightIDs = animated
            ? (pendingInsightIDs.isEmpty
                ? changedInsightIDs
                : changedInsightIDs.intersection(pendingInsightIDs))
            : pendingInsightIDs
        let newNodeIDs = animated
            ? (pendingNodeIDs.isEmpty
                ? changedNodeIDs
                : changedNodeIDs.intersection(pendingNodeIDs))
            : pendingNodeIDs
        let newInsights = nodes.flatMap { node in
            canvasInsights(for: node).filter { newInsightIDs.contains($0.id) }
        }
        // Clear these before the asynchronous camera/reveal sequence begins. This prevents a
        // connector from the previous topology from remaining visible during the camera scroll.
        revealState.revealedInsightConnectorIDs.subtract(newInsightIDs)
        let newGraphEdgeIDs = Set(displayGraphEdges().filter {
            newNodeIDs.contains($0.fromNodeID) || newNodeIDs.contains($0.toNodeID)
        }.map(\.id))
        revealState.revealedGraphEdgeIDs.subtract(newGraphEdgeIDs)
        revealState.animatedGraphEdgeIDs.formUnion(newGraphEdgeIDs)
        revealState.confirmedPersistedInsightIDs = currentInsightIDs
        revealState.confirmedPersistedNodeIDs = currentNodeIDs
        undiscoveredInsightIDs.formUnion(loadUndiscoveredInsightIDs())
        undiscoveredNodeIDs.formUnion(loadUndiscoveredNodeIDs())

        guard !newInsights.isEmpty || !newNodeIDs.isEmpty else {
            // Restoring the completed conversation snapshot is not a new-Insight entrance.
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                revealState.revealedInsightIDs = currentInsightIDs
                revealState.revealedInsightConnectorIDs = currentInsightIDs
                revealState.revealedGraphEdgeIDs = Set(displayGraphEdges().map(\.id))
                revealState.revealedNodeIDs = currentNodeIDs
            }
            saveAllInsightIDsAsSeen()
            reportUndiscoveredInsightCount()
            return
        }

        markUndiscovered(newInsights.map(\.id))
        markNodesUndiscovered(Array(newNodeIDs))
        reportUndiscoveredInsightCount()
        saveAllInsightIDsAsSeen()
        InsightDiscoveryStore.clearPendingTreePresentation(
            insightIDs: Set(newInsights.map(\.id)),
            nodeIDs: newNodeIDs
        )
        revealState.entranceTask = Task {
            // Let the node/body reconciliation from this same snapshot reach the canvas first.
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            await runPersistedUpdateSequence(
                newInsights: newInsights,
                newNodeIDs: newNodeIDs,
                in: size
            )
        }
    }

    /// Camera/reveal sequence for one fully loaded persisted mutation. Node Concepts participate
    /// even when analysis correctly adds no automatic Insights.
    func runPersistedUpdateSequence(
        newInsights: [InsightModel],
        newNodeIDs: Set<UUID>,
        in size: CGSize
    ) async {
        enum Target {
            case insight(InsightModel)
            case node(UUID)
        }

        let insightIDs = Set(newInsights.map(\.id))
        let allInsightIDs = visibleInsightIDs(in: nodes)
        let allNodeIDs = Set(nodes.map(\.id))
        revealState.revealedInsightIDs = allInsightIDs.subtracting(insightIDs)
        revealState.revealedInsightConnectorIDs = allInsightIDs.subtracting(insightIDs)
        let newGraphEdgeIDs = Set(displayGraphEdges().filter {
            newNodeIDs.contains($0.fromNodeID) || newNodeIDs.contains($0.toNodeID)
        }.map(\.id))
        revealState.revealedGraphEdgeIDs = Set(displayGraphEdges().map(\.id)).subtracting(newGraphEdgeIDs)
        revealState.revealedNodeIDs = allNodeIDs.subtracting(newNodeIDs)

        // The topology callback can arrive before the simulation has reconciled the new nodes.
        // Give the layout a beat to create/settle their bodies before resolving camera targets;
        // otherwise positionedTargets is empty and the post-update camera tour is skipped.
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }

        // The user is inspecting something: reveal the new content in place (with its blue dot)
        // rather than pulling the camera away from what they are looking at.
        if isHoveringTarget {
            revealState.revealedInsightIDs = allInsightIDs
            revealState.revealedInsightConnectorIDs = allInsightIDs.subtracting(insightIDs)
            growConnectors(insightIDs)
            revealState.revealedNodeIDs = allNodeIDs
            revealState.revealedGraphEdgeIDs = Set(displayGraphEdges().map(\.id))
            return
        }

        // An Insight past a Node's visible cap has no world position; tour its Node instead.
        var targets: [Target] =
            nodes.filter { newNodeIDs.contains($0.id) }.map { Target.node($0.id) }
        for insight in newInsights {
            if worldPosition(forInsightID: insight.id) != nil {
                targets.append(.insight(insight))
            } else if let host = nodes.first(where: { node in
                node.insights.contains { $0.id == insight.id }
            }), !targets.contains(where: {
                if case .node(let id) = $0 { return id == host.id }
                return false
            }) {
                targets.append(.node(host.id))
            }
        }

        func position(for target: Target) -> CGPoint? {
            switch target {
            case .insight(let insight):
                return worldPosition(forInsightID: insight.id)
            case .node(let nodeID):
                return simPosition(of: nodeID)
                    ?? nodes.first(where: { $0.id == nodeID })?.position
            }
        }

        let positionedTargets = targets.compactMap { target -> (Target, CGPoint)? in
            guard let position = position(for: target) else { return nil }
            return (target, position)
        }
        guard !positionedTargets.isEmpty else {
            revealState.revealedInsightIDs = allInsightIDs
            revealState.revealedInsightConnectorIDs = allInsightIDs
            revealState.revealedNodeIDs = allNodeIDs
            return
        }

        if positionedTargets.count <= 3 {
            for (target, position) in positionedTargets {
                guard !Task.isCancelled else { return }
                focusInsight(at: position, in: size)
                try? await Task.sleep(for: .milliseconds(950))
                guard !Task.isCancelled else { return }

                switch target {
                case .insight(let insight):
                    withAnimation(
                        .springRelaxed,
                        completionCriteria: .logicallyComplete
                    ) {
                        revealState.revealedInsightIDs.insert(insight.id)
                    } completion: {
                        guard !Task.isCancelled else { return }
                        growConnectors([insight.id])
                    }
                case .node(let nodeID):
                    _ = withAnimation(.easeOut(duration: 0.22)) {
                        revealState.revealedNodeIDs.insert(nodeID)
                    }
                    try? await Task.sleep(for: .milliseconds(620))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.62)) {
                        revealState.revealedGraphEdgeIDs.formUnion(displayGraphEdges().filter {
                            $0.fromNodeID == nodeID || $0.toNodeID == nodeID
                        }.map(\.id))
                    }
                }
                rippleTrigger = RippleTrigger(
                    worldOrigin: position,
                    startTime: Date().timeIntervalSinceReferenceDate
                )
                try? await Task.sleep(for: .milliseconds(700))
            }
        } else {
            let positions = positionedTargets.map(\.1)
            zoomToFit(worldPositions: positions, in: size)
            try? await Task.sleep(for: .milliseconds(1_100))
            guard !Task.isCancelled else { return }
            withAnimation(
                .easeOut(duration: 0.22),
                completionCriteria: .logicallyComplete
            ) {
                revealState.revealedNodeIDs.formUnion(newNodeIDs)
                revealState.revealedInsightIDs.formUnion(insightIDs)
            } completion: {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(620))
                    guard !Task.isCancelled else { return }
                    growConnectors(insightIDs)
                    withAnimation(.easeInOut(duration: 0.62)) {
                        revealState.revealedGraphEdgeIDs.formUnion(displayGraphEdges().filter {
                            newNodeIDs.contains($0.fromNodeID) || newNodeIDs.contains($0.toNodeID)
                        }.map(\.id))
                    }
                }
            }
            let center = CGPoint(
                x: positions.map(\.x).reduce(0, +) / CGFloat(positions.count),
                y: positions.map(\.y).reduce(0, +) / CGFloat(positions.count)
            )
            rippleTrigger = RippleTrigger(
                worldOrigin: center,
                startTime: Date().timeIntervalSinceReferenceDate
            )
        }
    }

    // MARK: - Undiscovered (blue-dot) tracking

    func loadUndiscoveredInsightIDs() -> Set<UUID> {
        InsightDiscoveryStore.loadUndiscoveredInsightIDs()
    }

    private func persistUndiscoveredInsightIDs() {
        InsightDiscoveryStore.saveUndiscoveredInsightIDs(undiscoveredInsightIDs)
    }

    func loadUndiscoveredNodeIDs() -> Set<UUID> {
        InsightDiscoveryStore.loadUndiscoveredNodeIDs()
    }

    private func persistUndiscoveredNodeIDs() {
        InsightDiscoveryStore.saveUndiscoveredNodeIDs(undiscoveredNodeIDs)
    }

    func reportUndiscoveredInsightCount() {
        let visibleInsightIDs = Set(nodes.flatMap { node in
            canvasInsights(for: node).map(\.id)
        })
        let visibleNodeIDs = Set(
            nodes.lazy
                .filter { !placedMidpointNodeIDs.contains($0.id) }
                .map(\.id)
        )
        let insightCount = undiscoveredInsightIDs.intersection(visibleInsightIDs).count
        let nodeCount = undiscoveredNodeIDs.intersection(visibleNodeIDs).count
        onUndiscoveredInsightCountChange(insightCount + nodeCount)
    }

    /// Flag newly appeared/generated insights as undiscovered (they get a blue dot).
    func markUndiscovered(_ ids: [UUID]) {
        var changed = false
        for id in ids where !undiscoveredInsightIDs.contains(id) {
            undiscoveredInsightIDs.insert(id)
            changed = true
        }
        if changed {
            persistUndiscoveredInsightIDs()
            reportUndiscoveredInsightCount()
        }
    }

    /// The user hovered an insight — clear its blue dot (forever).
    func markDiscovered(_ id: UUID) {
        InsightDiscoveryStore.markDiscovered(id)
        withAnimation(.easeOut(duration: 0.25)) {
            _ = undiscoveredInsightIDs.remove(id)
        }
        undiscoveredInsightIDs = loadUndiscoveredInsightIDs()
        reportUndiscoveredInsightCount()
    }

    /// Flag newly generated Node Concepts so they receive the same red discovery dot.
    func markNodesUndiscovered(_ ids: [UUID]) {
        let previousCount = undiscoveredNodeIDs.count
        undiscoveredNodeIDs.formUnion(ids)
        if undiscoveredNodeIDs.count != previousCount {
            persistUndiscoveredNodeIDs()
            reportUndiscoveredInsightCount()
        }
    }

    /// Opening a Node Concept clears its discovery dot permanently.
    func markNodeDiscovered(_ id: UUID) {
        guard undiscoveredNodeIDs.contains(id) else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            _ = undiscoveredNodeIDs.remove(id)
        }
        persistUndiscoveredNodeIDs()
        reportUndiscoveredInsightCount()
    }

    /// World position of an insight looked up by ID (nil if not visible on tree).
    func worldPosition(forInsightID id: UUID) -> CGPoint? {
        for node in displayNodes {
            if placedMidpointNodeIDs.contains(node.id), node.insights.contains(where: { $0.id == id }) {
                return node.position   // pinned chip sits on the node itself
            }
            let visible = canvasInsights(for: node)
            if let idx = visible.firstIndex(where: { $0.id == id }) {
                return insightWorldPosition(for: node, index: idx, count: visible.count)
            }
        }
        return nil
    }

    /// Zoom camera to a single insight (reuses focusInsight so camera memory is saved).
    private func zoomToInsight(_ insight: InsightModel, in size: CGSize) {
        guard let worldPos = worldPosition(forInsightID: insight.id) else { return }
        focusInsight(at: worldPos, in: size)
    }

    /// Zoom out so that all supplied insights fit in the viewport with padding.
    private func zoomToFitInsights(_ insights: [InsightModel], in size: CGSize) {
        let positions = insights.compactMap { worldPosition(forInsightID: $0.id) }
        zoomToFit(worldPositions: positions, in: size)
    }

    /// Zoom/pan so that all supplied world points fit in the viewport with padding.
    /// Pass `center` to anchor on a specific world point (e.g. a node) instead of the
    /// bounding-box centroid of `positions`.
    func zoomToFit(
        worldPositions positions: [CGPoint],
        in size: CGSize,
        padding: CGFloat = 180,
        fitFactor: CGFloat = 0.88,
        center: CGPoint? = nil
    ) {
        guard positions.count >= 2 else {
            if let pos = positions.first { focusInsight(at: pos, in: size) }
            return
        }

        let minX = positions.map { $0.x }.min()!
        let maxX = positions.map { $0.x }.max()!
        let minY = positions.map { $0.y }.min()!
        let maxY = positions.map { $0.y }.max()!

        let worldWidth          = max(maxX - minX + padding * 2, 1)
        let worldHeight         = max(maxY - minY + padding * 2, 1)
        let targetScale         = insightTreeCanvasClamp(
            min(size.width / worldWidth, size.height / worldHeight) * fitFactor,
            lower: 0.28, upper: 1.4
        )
        let centerX = center?.x ?? (minX + maxX) / 2
        let centerY = center?.y ?? (minY + maxY) / 2

        rememberCameraBeforeFocusIfNeeded()
        withAnimation(.springCamera) {
            cameraState.scale = targetScale
            cameraState.offset = CGSize(width: -(centerX * targetScale), height: centerY * targetScale)
        }
    }

    /// Orchestrates the full entrance sequence based on how many new insights there are.
    func runEntranceSequence(newInsights: [InsightModel], in size: CGSize) async {
        guard !newInsights.isEmpty else { return }
        let newIDs = Set(newInsights.map(\.id))

        // Small pause so the user can register the overview before we start zooming.
        try? await Task.sleep(nanoseconds: 200_000_000)

        if newInsights.count <= 3 {
            // Zoom to each new insight in turn, wait for the spring to settle,
            // then reveal it with its entrance animation.
            for insight in newInsights {
                guard !Task.isCancelled else { return }
                zoomToInsight(insight, in: size)
                try? await Task.sleep(nanoseconds: 950_000_000)   // spring settle ~0.95 s
                guard !Task.isCancelled else { return }
                withAnimation(
                    .springRelaxed,
                    completionCriteria: .logicallyComplete
                ) {
                    revealState.revealedInsightIDs.insert(insight.id)
                } completion: {
                    guard !Task.isCancelled else { return }
                    growConnectors([insight.id])
                }
                // Fire a ripple from this insight's world position as it springs in.
                if let worldPos = worldPosition(forInsightID: insight.id) {
                    rippleTrigger = RippleTrigger(worldOrigin: worldPos,
                                                  startTime: Date().timeIntervalSinceReferenceDate)
                }
                try? await Task.sleep(nanoseconds: 700_000_000)   // entrance anim + brief pause
            }
        } else {
            // 4+ new — zoom out so all are visible at once, then reveal them together.
            guard !Task.isCancelled else { return }
            zoomToFitInsights(newInsights, in: size)
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(
                .springRelaxed,
                completionCriteria: .logicallyComplete
            ) {
                revealState.revealedInsightIDs.formUnion(newIDs)
            } completion: {
                guard !Task.isCancelled else { return }
                growConnectors(newIDs)
            }
            // Single ripple at the centroid of all new insights.
            let positions = newInsights.compactMap { worldPosition(forInsightID: $0.id) }
            if !positions.isEmpty {
                let cx = positions.map { $0.x }.reduce(0, +) / CGFloat(positions.count)
                let cy = positions.map { $0.y }.reduce(0, +) / CGFloat(positions.count)
                rippleTrigger = RippleTrigger(worldOrigin: CGPoint(x: cx, y: cy),
                                              startTime: Date().timeIntervalSinceReferenceDate)
            }
        }
    }

    static func labelOpacity(for scale: CGFloat) -> Double {
        let startFade = CGFloat(0.44)
        let fullyVisible = CGFloat(0.78)
        let progress = (scale - startFade) / (fullyVisible - startFade)
        return Double(insightTreeCanvasClamp(progress, lower: 0, upper: 1))
    }

    /// Node Concept labels fade at a lower zoom than insight chips, so they stay legible
    /// when zoomed further out (insight chips drop away first, concepts persist).
    static func nodeLabelOpacity(for scale: CGFloat) -> Double {
        let startFade = CGFloat(0.30)
        let fullyVisible = CGFloat(0.40)
        let progress = (scale - startFade) / (fullyVisible - startFade)
        return Double(insightTreeCanvasClamp(progress, lower: 0, upper: 1))
    }
}
