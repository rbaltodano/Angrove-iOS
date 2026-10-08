import SwiftUI
import UIKit
import simd

// Lifecycle behavior for the shared global and conversation canvas.
extension InsightTreeCanvasView {

    /// Appearance, topology, and camera-request observers. Split out of `body` so its modifier
    /// chain stays within the type checker's limits on older toolchains.
    func canvasLifecycleObservers<Content: View>(_ content: Content, size: CGSize) -> some View {
        content
            .onAppear {
                // Restored content is already visible; only new items get a reveal.
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    hasAppeared = true
                    reconcileBodies()   // seed live physics bodies + start the tick
                    undiscoveredInsightIDs = loadUndiscoveredInsightIDs()
                    undiscoveredNodeIDs = loadUndiscoveredNodeIDs()
                    revealState.revealedNodeIDs = Set(nodes.map(\.id))
                    revealState.revealedGraphEdgeIDs = Set(displayGraphEdges().map(\.id))
                    revealState.observedLiveInsightIDs = visibleInsightIDs(in: nodes)
                    revealState.observedLiveNodeIDs = Set(nodes.map(\.id))
                    if defersEntranceUntilPersistedTree {
                        // Show the in-memory tree without moving the camera or marking it as the
                        // baseline. The completed seeded load will do both.
                        revealState.revealedInsightIDs = visibleInsightIDs(in: nodes)
                        revealState.revealedInsightConnectorIDs = visibleInsightIDs(in: nodes)
                        revealState.revealedGraphEdgeIDs = Set(displayGraphEdges().map(\.id))
                        reportUndiscoveredInsightCount()
                    } else {
                        let newInsights = computeNewInsights()
                        let existingIDs = visibleInsightIDs(in: nodes)
                            .subtracting(Set(newInsights.map(\.id)))
                        revealState.revealedInsightIDs = existingIDs
                        revealState.revealedInsightConnectorIDs = existingIDs
                        markUndiscovered(newInsights.map(\.id))   // new since last open → blue dot
                        reportUndiscoveredInsightCount()
                        saveAllInsightIDsAsSeen()
                        if !newInsights.isEmpty {
                            revealState.entranceTask = Task {
                                await runEntranceSequence(newInsights: newInsights, in: size)
                            }
                        }
                    }
                }
            }
            .onChange(of: persistedTreePresentationRevision) { _, revision in
                guard defersEntranceUntilPersistedTree, revision > 0 else { return }
                presentPersistedTree(
                    animated: animatedPersistedTreePresentationRevision == revision,
                    in: size
                )
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { persistLivePositions() }
            }
            .onChange(of: selectionPulseRequest) { _, newValue in
                guard newValue > 0 else { return }
                selectionState.selectionPulseStartTime = Date().timeIntervalSinceReferenceDate
            }
            .onChange(of: insightsFlashing) { _, flashing in
                if flashing {
                    selectionState.selectionFlashOpacity = 1
                    withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                        selectionState.selectionFlashOpacity = 0.25
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) { selectionState.selectionFlashOpacity = 1 }
                }
            }
            .onChange(of: physicsTopologySignature) { _, _ in
                // Only membership changes wake the layout. Content-only updates such as
                // generated labels and definitions leave the settled tree completely still.
                reconcileBodies()
                reportUndiscoveredInsightCount()
            }
            .onChange(of: layoutTargets) { _, _ in
                // New semantic targets (re-solve after a topology change): wake the sim so
                // the anchor springs glide nodes to their new positions.
                startSim(
                    intensity: Self.updateIntensity,
                    alphaDecay: Self.updateAlphaDecay,
                    frameBudget: 90
                )
            }
            .onChange(of: nodes) { _, newNodes in
                // Insights added after the initial entrance (Make Node children, placed midpoints):
                // they start as a flashing icon at the node center, splay out to their orbit
                // staggered by 0.15s each, then once "loaded" the title blurs up.
                guard hasAppeared else { return }
                if defersEntranceUntilPersistedTree {
                    // The persisted-tree presentation can run against an earlier snapshot of the
                    // tree (before its Insights were attached), so Insights that arrive in a later
                    // snapshot are never marked revealed and stay invisible. Unless a reveal tour
                    // is running, anything still hidden shortly after the tree changes is shown.
                    let reveal = revealState
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(500))
                        guard reveal.activeSequence == nil else { return }
                        let insightIDs = visibleInsightIDs(in: newNodes)
                        let hasHidden = !insightIDs.isSubset(of: reveal.revealedInsightIDs)
                            || !Set(newNodes.map(\.id)).isSubset(of: reveal.revealedNodeIDs)
                        if hasHidden { revealAllCurrentContent(in: newNodes) }
                    }
                }
                let currentInsightIDs = visibleInsightIDs(in: newNodes)
                let currentNodeIDs = Set(newNodes.map(\.id))
                let addedLiveInsightIDs = InsightDiscoveryStore.newInsightIDs(
                    in: currentInsightIDs,
                    excluding: revealState.observedLiveInsightIDs
                )
                let addedLiveNodeIDs = InsightDiscoveryStore.newNodeIDs(
                    in: currentNodeIDs,
                    excluding: revealState.observedLiveNodeIDs,
                    memberInsightIDs: Dictionary(uniqueKeysWithValues: newNodes.map {
                        ($0.id, Set($0.insights.map(\.id)))
                    })
                )
                if !defersEntranceUntilPersistedTree {
                    // Semantic preparation can populate an initially empty global canvas.
                    // Restore already presented chips and connectors without another entrance.
                    // Only restore items entering this view's snapshot, so a label update
                    // cannot prematurely reveal an entrance already running in this canvas.
                    let restoredIDs = currentInsightIDs
                        .subtracting(revealState.observedLiveInsightIDs)
                        .intersection(loadSeenInsightIDs())
                    let restoredNodeIDs = currentNodeIDs
                        .subtracting(revealState.observedLiveNodeIDs)
                        .subtracting(addedLiveNodeIDs)
                    revealState.observedLiveInsightIDs = currentInsightIDs
                    revealState.observedLiveNodeIDs = currentNodeIDs
                    revealState.revealedInsightIDs.formUnion(restoredIDs)
                    revealState.revealedInsightConnectorIDs.formUnion(restoredIDs)
                    revealState.revealedNodeIDs.formUnion(restoredNodeIDs)
                }
                let known = revealState.revealedInsightIDs.union(revealState.loadingInsightIDs)
                var newOnes: [(id: UUID, orbitIndex: Int)] = []
                var plainNewInsights: [InsightModel] = []
                var placedMidpointID: UUID? = nil
                for node in newNodes {
                    for (i, insight) in canvasInsights(for: node).enumerated()
                    where defersEntranceUntilPersistedTree
                        ? !known.contains(insight.id)
                        : addedLiveInsightIDs.contains(insight.id) {
                        if insight.id == midpointPlacedInsightID {
                            placedMidpointID = insight.id     // just-placed midpoint → simulated load + hover
                        } else if makeNodeChildIDs.contains(insight.id) {
                            newOnes.append((insight.id, i))   // Make Node child → loading mask + splay
                        } else {
                            plainNewInsights.append(insight)   // accepted Global Insights → camera tour + reveal
                        }
                    }
                }

                // Newly accepted Global Insights use the same staged camera/reveal sequence as
                // persisted tree updates. Waiting one layout beat lets their simulated positions
                // settle before the camera pans to them.
                if !plainNewInsights.isEmpty && !defersEntranceUntilPersistedTree {
                    revealState.entranceTask?.cancel()
                    let plainNewIDs = Set(plainNewInsights.map(\.id))
                    markUndiscovered(Array(plainNewIDs))
                    markNodesUndiscovered(Array(addedLiveNodeIDs))
                    reportUndiscoveredInsightCount()
                    saveAllInsightIDsAsSeen()
                    InsightDiscoveryStore.clearPendingTreePresentation(
                        insightIDs: plainNewIDs,
                        nodeIDs: addedLiveNodeIDs
                    )
                    revealState.entranceTask = Task {
                        await Task.yield()
                        try? await Task.sleep(for: .milliseconds(50))
                        guard !Task.isCancelled else { return }
                        await runPersistedUpdateSequence(
                            newInsights: plainNewInsights,
                            newNodeIDs: addedLiveNodeIDs,
                            in: size
                        )
                    }
                } else if !addedLiveNodeIDs.isEmpty && !defersEntranceUntilPersistedTree {
                    // Make Node and other node-only additions own their Insight animation below,
                    // but their parent concept still needs to become visible immediately.
                    withAnimation(.easeOut(duration: 0.22)) {
                        revealState.revealedNodeIDs.formUnion(addedLiveNodeIDs)
                    }
                }

                // A freshly placed midpoint insight runs a generation sequence:
                //   1. hover/zoom on the hollow "Insight Loading Icon" while generating
                //   2. once complete, the hollow icon fades+blurs out while the solid icon+title
                //      cross-fade in (fade/transform/blur), AND a big shockwave radiates — together
                //   3. shortly after, the insight card pops up
                if let placedID = placedMidpointID {
                    beginMidpointLoading(placedID, in: size)
                }

                guard !newOnes.isEmpty else { return }
                beginMakeNodeLoading(newOnes, in: newNodes, size: size)
            }
    }

    /// Loading, midpoint, and pulse observers, split out of `body` like `canvasLifecycleObservers`.
    func canvasRequestObservers<Content: View>(_ content: Content, size: CGSize) -> some View {
        content
            .onChange(of: revealState.loadingInsightIDs.isEmpty) { _, empty in
                if empty {
                    revealState.loadingFlashOpacity = 1
                } else {
                    revealState.loadingFlashOpacity = 1
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        revealState.loadingFlashOpacity = 0.35
                    }
                }
            }
            .onChange(of: isMidpointMode) { _, active in
                if active {
                    midpointHandleWorld = centeredMidpointHandle()
                    midpointHandleVisible = false
                    reportMidpointWeights()
                    let positions = selectedWorldPositions()
                    zoomToFit(worldPositions: positions, in: size)
                    // Delay the handle entrance until after the zoom spring settles (~0.7s).
                    Task {
                        try? await Task.sleep(for: .milliseconds(680))
                        withAnimation(.springLively) {
                            midpointHandleVisible = true
                        }
                    }
                } else {
                    midpointHandleVisible = false
                    midpointHandleWorld = nil
                    // On a placement we hand the camera to the new insight (the nodes onChange
                    // focuses it), so don't restore the pre-midpoint camera. Only restore on cancel.
                    if midpointPlacedInsightID == nil {
                        restorePreFocusCamera()
                    }
                }
            }
            .onChange(of: midpointGeneratedInsightID) { _, generatedID in
                guard let generatedID else { return }
                scheduleMidpointReveal(generatedID, in: size)
            }
            .onChange(of: generatedMakeNodeChildIDs) { _, ids in
                if studyBranchSource != nil || revealState.pendingMakeNodeChildren.isEmpty {
                    revealState.revealedInsightIDs.formUnion(ids)
                } else {
                    scheduleMakeNodeRevealIfReady(in: size)
                }
            }
            .onChange(of: midpointCenterRequest) { _, newValue in
                guard newValue > 0, isMidpointMode else { return }
                withAnimation(.springLively) {
                    midpointHandleWorld = centeredMidpointHandle()
                }
                reportMidpointWeights()
            }
            .onChange(of: midpointPercentRequest) { _, newValue in
                guard newValue > 0, isMidpointMode else { return }
                applyMidpointTarget(index: midpointTargetIndex, weight: midpointTargetWeight)
            }
            .onChange(of: midpointPlaceRequest) { _, newValue in
                guard newValue > 0, isMidpointMode, let handle = effectiveMidpointHandle() else { return }
                guard let nearest = nearestSelectedTarget(to: handle) else { return }
                onMidpointPlaced(handle, nearest, midpointWeights(for: handle))
            }
            // A freshly placed Midpoint's own two source chips haven't been manually angled by
            // anyone yet — point both of them at it immediately so the new connector doesn't
            // start out crossing some other line by default.
            .onChange(of: placedMidpointSources) { _, newValue in
                withAnimation(.springRelaxed) {
                    for midpointID in newValue.keys {
                        reangleMidpointSources(of: midpointID)
                    }
                }
            }
            .onDisappear {
                revealState.cancelPendingAnimations()
                revealAllCurrentContent()
                if !revealState.pendingMakeNodeChildren.isEmpty {
                    onGeneratingChange(false)
                }
                persistLivePositions()
                stopSim()
            }
            .task(id: selectionRippleKey) {
                // All selected items pulse the dot grid together, faster than the hover cadence.
                guard selectionRippleKey != nil else { return }
                while !Task.isCancelled {
                    let positions = selectedWorldPositions()
                    if !positions.isEmpty {
                        let now = Date().timeIntervalSinceReferenceDate
                        selectionState.selectionRipples = positions.map { RippleTrigger(worldOrigin: $0, startTime: now) }
                    }
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                }
            }
            .onChange(of: selectionRippleKey) { _, key in
                if key == nil { selectionState.selectionRipples = [] }
            }
            .task(id: pulseSourceKey) {
                guard pulseSourceKey != nil else { return }
                let now = Date().timeIntervalSinceReferenceDate
                connectorPulseDelayUntil = now + 0.58
                pulseCycleStartedAt = connectorPulseDelayUntil

                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled,
                          selectedCanvasTargets.isEmpty,   // selected items run their own faster ripple
                          let worldPosition = pulsingWorldPosition() else { continue }

                    rippleTrigger = RippleTrigger(
                        worldOrigin: worldPosition,
                        startTime: Date().timeIntervalSinceReferenceDate
                    )
                }
            }
    }

    /// Single drag gesture that routes to handle movement when the drag starts near the
    /// midpoint handle, otherwise falls through to normal canvas panning.
}
