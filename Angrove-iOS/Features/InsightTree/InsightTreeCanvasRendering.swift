import SwiftUI
import UIKit
import simd

// Rendering behavior for the shared global and conversation canvas.
extension InsightTreeCanvasView {
    @ViewBuilder
    func graphEdges(camera: InsightTreeCamera, size: CGSize) -> some View {
        let hasSelection = !selectedCanvasTargets.isEmpty
        ForEach(displayGraphEdges()) { edge in
            if revealState.revealedGraphEdgeIDs.contains(edge.id),
               let from = simPosition(of: edge.fromNodeID),
               let to = simPosition(of: edge.toNodeID) {
                let start = camera.worldToScreen(from, in: size)
                let end = camera.worldToScreen(to, in: size)

                let isPromotionEdge = nodes.contains { node in
                    (node.id == edge.fromNodeID || node.id == edge.toNodeID)
                        && node.insights.contains { makeNodeChildIDs.contains($0.id) }
                }
                let lineColor = isPromotionEdge
                    ? AngroveTheme.Colors.primaryReadable.opacity(0.3)
                    : AngroveTheme.Colors.divider.opacity(edge.isSuggested ? 0.55 : 0.9)
                InsightTreeCanvasGraphEdge(
                    start: start, end: end, color: lineColor,
                    isAnimated: revealState.animatedGraphEdgeIDs.contains(edge.id),
                    isSuggested: edge.isSuggested
                )
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
                    .opacity((hasSelection ? 0.5 : 1.0) * (isInStudy
                        && !(studyFocusNodeID == completedBranchNodeID
                            && (edge.fromNodeID == completedBranchNodeID || edge.toNodeID == completedBranchNodeID))
                        ? 1 - studyProgress : 1))
                    .animation(.easeInOut(duration: 0.22), value: hasSelection)
            }
        }
    }

    /// World endpoint for a midpoint's source: the insight's chip, or the node center for a
    /// whole-node-concept source.
    private func midpointSourceEndpoint(_ source: MidpointSource) -> CGPoint? {
        if source.isNode {
            if let node = displayNodes.first(where: { $0.insights.contains { $0.id == source.insightID } }) {
                return node.position
            }
            return simPosition(of: source.insightID)
        }
        return worldPosition(forInsightID: source.insightID)
    }

    /// Screen endpoint for a midpoint's source. Insight sources end exactly where their chip is
    /// drawn (including local elevation and perspective); node sources use the node's depth.
    private func midpointSourceScreenPosition(
        _ source: MidpointSource,
        layout: CanvasInsightLayout,
        camera: InsightTreeCamera,
        size: CGSize
    ) -> CGPoint? {
        if !source.isNode, let placement = layout.placements[source.insightID] {
            return insightScreenPosition(placement, camera: camera, size: size)
        }
        guard let sourceWorld = midpointSourceEndpoint(source) else { return nil }
        return camera.worldToScreen(sourceWorld, in: size)
    }

    /// Lines from each placed midpoint to the insight chips / node concepts it was spawned from.
    @ViewBuilder
    func midpointConnectors(layout: CanvasInsightLayout, camera: InsightTreeCamera, size: CGSize) -> some View {
        let hasSelection = !selectedCanvasTargets.isEmpty
        ForEach(Array(placedMidpointNodeIDs), id: \.self) { placedID in
            if let placedWorld = simPosition(of: placedID), let sources = placedMidpointSources[placedID] {
                let end = camera.worldToScreen(placedWorld, in: size)
                ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                    if let start = midpointSourceScreenPosition(source, layout: layout, camera: camera, size: size) {
                        FadedCanvasLine(start: start, end: end, color: AngroveTheme.Colors.divider.opacity(0.9))
                            .frame(width: size.width, height: size.height)
                            .allowsHitTesting(false)
                            .opacity(hasSelection ? 0.5 : 1.0)
                    }
                }
            }
        }
    }

    @ViewBuilder
    func insightConnectors(layout: CanvasInsightLayout, camera: InsightTreeCamera, size: CGSize) -> some View {
        let hasSelection = !selectedCanvasTargets.isEmpty
        // Placed-midpoint chips sit on the node itself, so they have no orbit connectors.
        let connectorNodes = layout.nodes.filter { !placedMidpointNodeIDs.contains($0.id) }
        ForEach(connectorNodes, id: \.id) { node in
            let visibleInsights = layout.insightsByNode[node.id] ?? []
            ForEach(visibleInsights) { insight in
                if revealState.revealedInsightConnectorIDs.contains(insight.id),
                   let placement = layout.placements[insight.id] {
                    let start = camera.worldToScreen(node.position, in: size)
                    let end = insightScreenPosition(placement, camera: camera, size: size)
                    // Connector lines stay at a constant opacity regardless of zoom — only the
                    // chip label/background fade with `labelOpacity`, not the lines themselves.
                    let baseOpacity = 0.55

                    let lineColor = makeNodeChildIDs.contains(insight.id)
                        ? AngroveTheme.Colors.primaryReadable.opacity(0.28)
                        : AngroveTheme.Colors.divider.opacity(baseOpacity)
                    InsightConnectorLine(
                        start: start,
                        end: end,
                        color: lineColor.opacity((hasSelection ? 0.5 : 1.0)
                            * studyOpacity(forInsightID: insight.id, nodeID: node.id)),
                        grows: revealState.growingConnectorIDs.contains(insight.id)
                    )
                        .frame(width: size.width, height: size.height)
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: 0.22), value: hasSelection)

                }
            }
        }
    }

    /// Reveals new Insights' connectors, growing each out of its Node Concept.
    func growConnectors(_ insightIDs: Set<UUID>) {
        let fresh = revealState.beginConnectorGrowth(insightIDs)
        guard !fresh.isEmpty else { return }
        Task { @MainActor in
            // Past the grow, so a connector redrawn later appears whole.
            try? await Task.sleep(for: .milliseconds(800))
            revealState.growingConnectorIDs.subtract(fresh)
        }
    }

    private struct ConnectorPulseEndpoints: Identifiable {
        let id: String
        let start: CGPoint
        let end: CGPoint
        let lineWidth: CGFloat
    }

    /// Screen endpoints of every connector that should pulse, resolved once per render from the
    /// same placements the chips and connectors use. Empty when nothing is hovered, so the
    /// per-frame timeline below draws nothing and scans nothing.
    private func connectorPulseEndpoints(
        layout: CanvasInsightLayout,
        camera: InsightTreeCamera,
        size: CGSize
    ) -> [ConnectorPulseEndpoints] {
        guard pulsingInsightID != nil || pulsingNodeID != nil else { return [] }
        var lines: [ConnectorPulseEndpoints] = []

        let sourceNodeID = pulsingNodeID ?? pulsingInsightNodeID()
        if let sourceNodeID, let sourcePos = simPosition(of: sourceNodeID) {
            let start = camera.worldToScreen(sourcePos, in: size)
            for edge in displayGraphEdges()
            where edge.fromNodeID == sourceNodeID || edge.toNodeID == sourceNodeID {
                let targetNodeID = edge.fromNodeID == sourceNodeID ? edge.toNodeID : edge.fromNodeID
                guard let targetPos = simPosition(of: targetNodeID) else { continue }
                lines.append(ConnectorPulseEndpoints(
                    id: "edge-\(edge.id)",
                    start: start,
                    end: camera.worldToScreen(targetPos, in: size),
                    lineWidth: 2.2
                ))
            }
        }

        for node in layout.nodes {
            let visibleInsights = layout.insightsByNode[node.id] ?? []
            let pulsed: [InsightModel]
            let lineWidth: CGFloat
            if let pulsingInsightID, let insight = visibleInsights.first(where: { $0.id == pulsingInsightID }) {
                pulsed = [insight]
                lineWidth = 2.2
            } else if pulsingNodeID == node.id {
                pulsed = visibleInsights
                lineWidth = 1.8
            } else {
                continue
            }
            let nodePosition = camera.worldToScreen(node.position, in: size)
            for insight in pulsed {
                guard let placement = layout.placements[insight.id] else { continue }
                lines.append(ConnectorPulseEndpoints(
                    id: "insight-\(insight.id.uuidString)",
                    start: insightScreenPosition(placement, camera: camera, size: size),
                    end: nodePosition,
                    lineWidth: lineWidth
                ))
            }
        }
        return lines
    }

    @ViewBuilder
    func connectorPulseOverlay(layout: CanvasInsightLayout, camera: InsightTreeCamera, size: CGSize) -> some View {
        let lines = connectorPulseEndpoints(layout: layout, camera: camera, size: size)
        // Paused while idle: an always-running `.animation` timeline re-evaluated this overlay
        // every display frame even when no connector was pulsing.
        TimelineView(.animation(minimumInterval: nil, paused: lines.isEmpty)) { timeline in
            let pulseProgress = connectorPulseProgress(at: timeline.date)

            ZStack {
                ForEach(lines) { line in
                    TravelingCanvasPulse(start: line.start, end: line.end, progress: pulseProgress, lineWidth: line.lineWidth)
                        .frame(width: size.width, height: size.height)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    /// 0 in the tree, 1 once Study has framed a selection: its lines between the selected
    /// Insights solidify (no pulses) and the selection borders and reticle go away.
    private var selectionStudyAmount: Double {
        studySelectionCenter == nil ? 0 : studyProgress
    }

    func selectionOverlay(
        layout: CanvasInsightLayout,
        camera: InsightTreeCamera,
        size: CGSize,
        restFade: Double
    ) -> some View {
        InsightTreeSelectionOverlay(
            positions: selectedCanvasTargets.map {
                selectionScreenPosition(for: $0, layout: layout, camera: camera, size: size)
            },
            isMidpointMode: isMidpointMode,
            center: focusAnchor(in: size), size: size, restFade: restFade,
            studyAmount: selectionStudyAmount,
            selectionPulseStartTime: selectionState.selectionPulseStartTime
        )
    }

    /// Node targets keep their existing unshifted camera position; Insight targets use the
    /// position their chip is actually drawn at.
    private func selectionScreenPosition(
        for target: CanvasSelectionTarget,
        layout: CanvasInsightLayout,
        camera: InsightTreeCamera,
        size: CGSize
    ) -> CGPoint? {
        if case .insight(let insightID) = target, let placement = layout.placements[insightID] {
            return insightScreenPosition(placement, camera: camera, size: size)
        }
        return worldPosition(for: target).map { camera.worldToScreen($0, in: size) }
    }

    private func connectorPulseProgress(at date: Date) -> Double {
        let cycleDuration = 2.0
        guard date.timeIntervalSinceReferenceDate >= connectorPulseDelayUntil else { return 0 }

        return max(0, date.timeIntervalSinceReferenceDate - pulseCycleStartedAt)
            .truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
    }

    var pulseSourceKey: String? {
        if let pulsingInsightID {
            return "insight-\(pulsingInsightID.uuidString)"
        }

        if let pulsingNodeID {
            return "node-\(pulsingNodeID.uuidString)"
        }

        return nil
    }

    var selectionRippleKey: String? {
        guard !selectedCanvasTargets.isEmpty else { return nil }
        return selectedCanvasTargets.map { target -> String in
            switch target {
            case .node(let id): return "n\(id.uuidString)"
            case .insight(let id): return "i\(id.uuidString)"
            }
        }.joined(separator: "|")
    }

    func pulsingWorldPosition() -> CGPoint? {
        if let pulsingInsightID {
            return insightFocusTarget(for: pulsingInsightID)
        }

        if let pulsingNodeID {
            return simPosition(of: pulsingNodeID)
        }

        return nil
    }

    private func pulsingInsightNodeID() -> UUID? {
        guard let pulsingInsightID else { return nil }

        return nodes.first { node in
            node.insights.contains { $0.id == pulsingInsightID }
        }?.id
    }

    func worldPosition(for target: CanvasSelectionTarget) -> CGPoint? {
        switch target {
        case .node(let nodeID):
            return simPosition(of: nodeID)
        case .insight(let insightID):
            return insightFocusTarget(for: insightID)
        }
    }

    @ViewBuilder
    func midpointOverlay(layout: CanvasInsightLayout, camera: InsightTreeCamera, size: CGSize, labelOpacity: Double) -> some View {
        let positions = selectedWorldPositions()
        let boundaryPositions = positions.count >= 3 ? convexHull(of: positions) : positions
        let screenPts = boundaryPositions.map { camera.worldToScreen($0, in: size) }

        ZStack {
            // Connecting region: filled polygon for 3+, single segment for 2.
            // PolygonShape is animatable so it follows the camera's zoom-out spring.
            if screenPts.count >= 3 {
                PolygonShape(points: screenPts)
                    .fill(AngroveTheme.Colors.lightGreen.opacity(0.25))
                    .allowsHitTesting(false)

                PolygonShape(points: screenPts)
                    .stroke(AngroveTheme.Colors.lightGreen.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .allowsHitTesting(false)
            } else if screenPts.count == 2 {
                AnimatableLine(start: screenPts[0], end: screenPts[1])
                    .stroke(AngroveTheme.Colors.lightGreen.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
            }

            // Re-draw the selected items at full opacity so they "pop" above the dimmed canvas.
            ForEach(Array(selectedCanvasTargets.enumerated()), id: \.offset) { _, target in
                midpointSelectedItem(target, layout: layout, camera: camera, size: size, labelOpacity: labelOpacity)
            }
            .allowsHitTesting(false)

            // Draggable handle.
            if let handle = effectiveMidpointHandle() {
                let handleScreen = camera.worldToScreen(handle, in: size)
                MidpointHandle()
                    .scaleEffect(midpointHandleVisible ? 1 : 0.3)
                    .opacity(midpointHandleVisible ? 1 : 0)
                    .position(handleScreen)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func midpointSelectedItem(
        _ target: CanvasSelectionTarget,
        layout: CanvasInsightLayout,
        camera: InsightTreeCamera,
        size: CGSize,
        labelOpacity: Double
    ) -> some View {
        // Selected items stay fully legible while the rest dims — ignore the
        // zoom-driven label fade by forcing full label opacity.
        switch target {
        case .node(let id):
            if let node = displayNodes.first(where: { $0.id == id }) {
                nodeGroup(node, camera: camera, size: size, labelOpacity: 1)
            }
        case .insight(let id):
            if let placement = layout.placements[id],
               let node = layout.nodes.first(where: { $0.id == placement.nodeID }) {
                insightLabel(placement, node: node, camera: camera, size: size, labelOpacity: 1)
            }
        }
    }

    @ViewBuilder
    func edgeHitTargets(camera: InsightTreeCamera, size: CGSize) -> some View {
        ForEach(edges) { edge in
            if edge.showSuggestButton,
               let from = simPosition(of: edge.fromNodeID),
               let to = simPosition(of: edge.toNodeID) {
                // Midpoint of the depth-parallaxed endpoints, so the button tracks the line.
                let fromScreen = camera.worldToScreen(from, in: size)
                let toScreen = camera.worldToScreen(to, in: size)
                let position = CGPoint(
                    x: (fromScreen.x + toScreen.x) / 2,
                    y: (fromScreen.y + toScreen.y) / 2
                )

                Button {
                    guard canAcceptTap else { return }
                    if selectionState.selectedEdgeID == edge.id {
                        selectionState.selectedEdgeID = nil
                        onSuggestConnection(edge)
                    } else {
                        selectionState.selectedEdgeID = edge.id
                    }
                } label: {
                    ZStack {
                        if selectionState.selectedEdgeID == edge.id {
                            Text("Suggest Connection")
                                .font(.figtreeHeading3)
                                .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(AngroveTheme.Colors.surface)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(AngroveTheme.Colors.controlBorder, lineWidth: 1))
                                .transition(.scale(scale: 0.92).combined(with: .opacity))
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 170, height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(position)
            }
        }
    }

    @ViewBuilder
    func nodeGroup(
        _ node: NodeModel,
        camera: InsightTreeCamera,
        size: CGSize,
        labelOpacity: Double
    ) -> some View {
        let projection = camera.project(node.position, in: size)
        let position = projection.position

        InsightTreeCanvasConceptNode(
            title: node.conceptLabel,
            isSuggested: node.isSuggested,
            isNaming: namingNodeIDs.contains(node.id),
            isUndiscovered: undiscoveredNodeIDs.contains(node.id),
            hasAppeared: hasAppeared,
            labelOpacity: labelOpacity,
            backgroundColor: insightTreeCanvasColor,
            scale: depthScale(node.id) * projection.scale * completedBranchContentScale,
            opacity: depthOpacity(node.id) * chipDragDimFactor,
            position: position,
            zOrder: (node.isSuggested ? 20 : 10) + Double(depthFactor(node.id)) * 5,
            onTap: {
                guard canAcceptTap else { return }
                markNodeDiscovered(node.id)
                if selectedCanvasTargets.isEmpty {
                    rippleTrigger = RippleTrigger(
                        worldOrigin: node.position,
                        startTime: Date().timeIntervalSinceReferenceDate
                    )
                }
                focusHoveredTarget(at: node.position, in: size)
                onNodeTapped(node)
            },
            onDismiss: { onDismissSuggestedNode(node) }
        )
    }

    /// Dims every Node and every non-dragged Insight chip to half opacity while a chip
    /// rotate-drag is active, so the one chip under the finger reads unambiguously.
    private var chipDragDimFactor: Double {
        draggingChipID == nil ? 1.0 : 0.5
    }

    /// Two quick medium taps, fired as a generated insight's shockwave bursts out.
    func playGeneratedHaptics() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred(intensity: 0.9)
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.9)
        }
    }

    func insightLabel(
        _ placement: InsightPlacement,
        node: NodeModel,
        camera: InsightTreeCamera,
        size: CGSize,
        labelOpacity: Double
    ) -> some View {
        let insight = placement.insight
        let index = placement.index
        let count = placement.count
        // Placed-midpoint insights are pinned at the node position itself (no orbit).
        let isPinnedAtNode = placement.isPinnedAtNode
        let worldPosition = placement.world
        let isRevealed    = revealState.revealedInsightIDs.contains(insight.id)
        let isLoading     = revealState.loadingInsightIDs.contains(insight.id)
        let isSelected    = selectedCanvasTargets.contains(.insight(insight.id))
        // Pinned (placed-midpoint) chips stay visible from the moment they appear — even in
        // the brief gap between the icon turning solid and the title blurring in.
        let isVisible     = isRevealed || isLoading || isPinnedAtNode
        // While unsplayed, render at the node center so the child appears to splay out from it.
        let atCenter      = revealState.unsplayedInsightIDs.contains(insight.id)
        let projection    = atCenter
            ? camera.project(node.position, in: size)
            : insightProjection(placement, camera: camera, size: size)
        let position      = projection.position
        // Stable per-chip delay (0.05–0.25s) so the title collapse/expand staggers across chips.

        return InsightTreeCanvasChip(
            title: insight.title,
            isLoading: isLoading,
            isRevealed: isRevealed,
            isVisible: isVisible,
            isSelected: isSelected,
            isUndiscovered: undiscoveredInsightIDs.contains(insight.id),
            loadingFlashOpacity: revealState.loadingFlashOpacity,
            labelOpacity: labelOpacity,
            selectionStudyAmount: selectionStudyAmount,
            backgroundColor: insightTreeCanvasColor
        )
        .onTapGesture {
            // The placed-midpoint "Insight Loading Icon" stays hoverable even while generating;
            // other loading insights (Make Node children) are not tappable until revealed.
            guard canAcceptTap, !isLoading || isPinnedAtNode else { return }
            markDiscovered(insight.id)   // hovering clears its blue dot
            if selectedCanvasTargets.isEmpty {
                rippleTrigger = RippleTrigger(
                    worldOrigin: worldPosition,
                    startTime: Date().timeIntervalSinceReferenceDate
                )
            }
            focusHoveredTarget(at: worldPosition, elevation: placement.elevation, in: size)
            onInsightTapped(insight)
        }
        .simultaneousGesture(
            chipRotateDragGesture(
                insight: insight,
                node: node,
                index: index,
                count: count,
                isPinnedAtNode: isPinnedAtNode,
                camera: camera,
                size: size
            ),
            isEnabled: canAcceptTap
        )
        .offset(y: isVisible ? 0 : 24)
        .opacity(isVisible ? 1 : 0)
        .blur(radius: isVisible ? 0 : 8)
        .animation(.springRelaxed, value: isVisible)
        .transition(.scale(scale: 0.88, anchor: .center).combined(with: .opacity))
        // 2.5D depth: each chip combines its Node Concept's semantic depth with its own
        // bounded local elevation, so a cluster reads as a shallow spatial volume.
        // While rotate-dragging, the dragged chip grows 5% and stays full opacity; every other
        // chip dims along with the Nodes (see `chipDragDimFactor`).
        // No `.animation(_, value:)` here: that resets the animation context for every modifier
        // after it — including `.position()` below — to ONLY animate on `draggingChipID`
        // changes, using its own spring. That decoupled the chip from `AnimatableLine`'s
        // connector, which has no such override and just rides whatever ambient `withAnimation`
        // is active — so the line eased back on release while the chip itself snapped instantly.
        // Wrapping the state mutations in `chipRotateDragGesture` in `withAnimation` covers scale,
        // opacity, AND position uniformly, the same way it already covers the connector line.
        // Node Concept depth times true perspective magnification at the chip's elevation.
        .scaleEffect(depthScale(node.id) * chipScale(nodeID: node.id, magnification: projection.scale) * (draggingChipID == insight.id ? 1.05 : 1.0) * completedBranchContentScale)
        .opacity(insightDepthOpacity(placement) * (draggingChipID == insight.id ? 1.0 : chipDragDimFactor))
        .opacity(studyOpacity(forInsightID: insight.id, nodeID: node.id) * (1 - 0.4 * studyProgress * studyDepthDim(placement, camera: camera)))
        // A hovered Insight in Study always draws in front; it never dims (see `studyDepthDim`).
        .position(position)
        // Nearer the camera draws on top, whether nearer by elevation or by plane position.
        // In Study, Insights behind the Node Concept draw behind it.
        .zIndex(
            studyDepthDim(placement, camera: camera) > 0.5 && insight.id != studyPivotID
                ? 5 + Double(projection.scale)
                : 30 + Double(projection.scale) * 5 + (draggingChipID == insight.id ? 100 : 0)
        )
    }

}
