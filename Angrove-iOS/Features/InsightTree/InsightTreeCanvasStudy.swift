import SwiftUI
import UIKit
import simd

// Study behavior for the shared global and conversation canvas.
extension InsightTreeCanvasView {
    // MARK: - Node Concept Study

    /// The ring's bottom edge sits this far above the canvas's bottom, which is the top of the
    /// docked Study tool card.
    private static let studyRingBottomMargin: CGFloat = 24

    /// Studying a Node Concept or a selection of Insights.
    var isInStudy: Bool { studyFocusNodeID != nil || studySelectionCenter != nil }
    var isStudyRequested: Bool { studyNodeID != nil || studySelectionIDs != nil }

    /// What Study turns around: the studied node, or the selection's centroid.
    private var studyCenter: CGPoint? {
        if let studySelectionCenter { return studySelectionCenter }
        guard let nodeID = studyFocusNodeID else { return nil }
        return bodies[nodeID]?.pos ?? nodes.first(where: { $0.id == nodeID })?.position
    }

    func makeStudyFraming(in size: CGSize) -> StudyFraming? {
        guard let slot = studySlot, let position = studyCenter else { return nil }
        return StudyFraming(
            nodeCenter: SIMD3(Double(position.x), Double(position.y), 0),
            radius: studyRadius,
            slot: slot,
            ringCenterY: studyRingCenterY ?? Self.studyRingCenterY(in: size)
        )
    }

    /// The ring is 42 pt tall, so its center is 21 pt above its bottom edge.
    static func studyRingCenterY(in size: CGSize) -> CGFloat {
        size.height - studyRingBottomMargin - 21
    }

    /// Docking or dismissing a card resizes the canvas at once; in Study the ring (and the
    /// camera framed around it) follows on the cards' own spring instead of jumping.
    func glideStudyRing(from oldSize: CGSize, to newSize: CGSize) {
        let target = Self.studyRingCenterY(in: newSize)
        guard isInStudy, oldSize.height > 0, oldSize.height != newSize.height else {
            if !isInStudy { studyRingLink?.stop(); studyRingCenterY = nil }
            return
        }
        let from = studyRingCenterY ?? Self.studyRingCenterY(in: oldSize)
        let spring = Spring(response: 0.42, dampingRatio: 0.86)
        studyRingLink?.stop()
        studyRingCenterY = from
        let start = CACurrentMediaTime()
        let driver = DisplayLinkDriver()
        driver.onTick = { now in
            let elapsed = now - start
            guard elapsed < spring.settlingDuration else {
                studyRingCenterY = nil
                studyRingLink?.stop()
                studyRingLink = nil
                return
            }
            studyRingCenterY = from + (target - from) * CGFloat(spring.value(target: 1.0, time: elapsed))
        }
        driver.start()
        studyRingLink = driver
    }

    /// The Study camera starts from the tree's live camera, not a snapshot: the canvas can
    /// resize while docked cards swap, and at progress 0 the two must match exactly so handing
    /// back to the tree never jumps.
    func studyCamera(_ tree: InsightTreeCamera, framing: StudyFraming?, in size: CGSize) -> InsightTreeCamera {
        guard let framing else { return tree }
        var camera = tree
        camera.orbit = framing.camera(
            from: tree.currentOrbitCamera(in: size),
            progress: studyProgress,
            yaw: studyYaw,
            pan: studyPan,
            zoom: studyZoom,
            endPitch: studyFocusNodeID == completedBranchNodeID ? completedBranchPitch : StudyFraming.studyPitch,
            pivot: studyPivotPoint(framing: framing),
            pivotBlend: studyPivotBlend,
            targetShift: studyTargetShift
        )
        camera.studyNodeCenter = framing.nodeCenter
        return camera
    }

    /// Everything but the studied Node Concept and its Insights fades as the camera moves in.
    func studyOpacity(forNodeID nodeID: UUID) -> Double {
        guard isInStudy, nodeID != studyFocusNodeID else { return 1 }
        if studyFocusNodeID == completedBranchNodeID,
           edges.contains(where: {
               ($0.fromNodeID == nodeID && $0.toNodeID == completedBranchNodeID)
                || ($0.toNodeID == nodeID && $0.fromNodeID == completedBranchNodeID)
           }) { return 1 }
        return 1 - studyProgress
    }

    /// Studying a selection keeps its Insights while their Node Concepts fade.
    func studyOpacity(forInsightID insightID: UUID, nodeID: UUID) -> Double {
        if studyFocusNodeID == completedBranchNodeID, nodeID != studyFocusNodeID { return 1 - studyProgress }
        return studySelectionMembers.contains(insightID) ? 1 : studyOpacity(forNodeID: nodeID)
    }

    /// The completed Branch fit scales its labels with its camera so fitting the parent and
    /// children cannot compress their positions into overlapping full-size chips.
    var completedBranchContentScale: CGFloat {
        guard studyFocusNodeID == completedBranchNodeID, completedBranchNodeID != nil else { return 1 }
        return 1 + (min(studyZoom / StudyFraming.entryZoom, 1) - 1) * CGFloat(studyProgress)
    }

    /// Chip scale: the tree's, blending in Study to the same size with gentle depth scaling.
    func chipScale(nodeID: UUID, magnification: CGFloat) -> CGFloat {
        // In the tree, perspective moves chips but doesn't resize them.
        let tree: CGFloat = 1
        guard nodeID == studyFocusNodeID || studySelectionCenter != nil else { return tree }
        let study = pow(max(magnification, 0.01), 0.6)
        return tree + (study - tree) * CGFloat(studyProgress)
    }

    /// How far a studied Insight has swung behind its Node Concept: 0 in front, 1 behind, easing
    /// smoothly (smoothstep) across the node's depth so dimming never snaps while rotating.
    func studyDepthDim(_ placement: InsightPlacement, camera: InsightTreeCamera) -> Double {
        guard placement.nodeID == studyFocusNodeID || studySelectionMembers.contains(placement.insight.id),
              placement.insight.id != studyPivotID,
              let orbit = camera.orbit, let center = camera.studyNodeCenter,
              let chip = orbit.project(SIMD3(Double(placement.world.x), Double(placement.world.y), Double(placement.elevation))),
              let node = orbit.project(center)
        else { return 0 }
        let band = 0.7 * studyRadius
        let t = min(max((chip.depth - node.depth + band / 2) / band, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// A studied Insight's offset from the Study center (its Node Concept, or the selection's
    /// centroid), moving from its tree position to its place on the Study sphere.
    func studyOffset(forInsightID insightID: UUID) -> SIMD3<Double>? {
        guard isInStudy, studyProgress > 0,
              let start = studyTreeOffsets[insightID], let spread = studySpread[insightID]
        else { return nil }
        return StudyNodeLayout.offset(from: start, toward: spread,
            bondLength: Double(bondLength(forInsightID: insightID)), progress: studyProgress)
    }

    private func parentNodeID(ofInsight insightID: UUID) -> UUID? {
        displayNodes.first { node in node.insights.contains { $0.id == insightID } }?.id
    }

    func beginStudy(of nodeID: UUID) {
        let layout = makeInsightLayout()
        guard let node = layout.nodes.first(where: { $0.id == nodeID }) else { return }
        let placements = (layout.insightsByNode[nodeID] ?? []).compactMap { layout.placements[$0.id] }
        studySelectionCenter = nil
        studySelectionMembers = []
        startStudy(around: node.position, placements: placements, radius: nil)
        studyFocusNodeID = nodeID
        if nodeID == completedBranchNodeID { fitCompletedBranchStudy(node: node, size: lastCanvasSize) }
        flyIntoStudy()
    }

    /// Frame the complete new cluster and its original parent, not the generic 2x close-up.
    /// Uniform camera zoom preserves semantic ordering while keeping labels and edges in view.
    private func fitCompletedBranchStudy(node: NodeModel, size: CGSize) {
        guard size.width > 48, size.height > 48,
              let framing = makeStudyFraming(in: size) else { return }
        let parentIDs = Set(edges.compactMap { edge -> UUID? in
            if edge.fromNodeID == node.id { return edge.toNodeID }
            if edge.toNodeID == node.id { return edge.fromNodeID }
            return nil
        })
        let center = framing.nodeCenter
        var items: [(point: SIMD3<Double>, halfSize: CGSize)] = [(center, CGSize(width: 138, height: 80))]
        for child in node.insights {
            guard let direction = studySpread[child.id] else { continue }
            let point = center + direction * Double(bondLength(forInsightID: child.id))
            let footprint = insightCollisionSize(for: child)
            items.append((point, CGSize(width: footprint.width / 2 + 8, height: footprint.height / 2 + 8)))
        }
        for parent in displayNodes where parentIDs.contains(parent.id) {
            items.append((SIMD3(Double(parent.position.x), Double(parent.position.y), 0), CGSize(width: 138, height: 80)))
        }
        let treeCamera = InsightTreeCamera(scale: activeScale, offset: activeOffset).currentOrbitCamera(in: size)
        // Choose the opening orientation by label separation, not just spherical point
        // separation: an eye-level view can put a front/back pair directly over the Node.
        var bestOverlap = Double.infinity
        var openingYaw = 0.0
        var openingPitch = StudyFraming.studyPitch
        for pitch in [StudyFraming.studyPitch, Double.pi / 3, Double.pi / 4, Double.pi / 6] {
            for step in 0..<12 {
                let yaw = Double(step) * .pi / 6
                let camera = framing.camera(from: treeCamera, progress: 1, yaw: yaw,
                    zoom: StudyFraming.entryZoom, endPitch: pitch)
                let frames = items.compactMap { item -> CGRect? in
                    guard let projected = camera.project(item.point) else { return nil }
                    return CGRect(x: projected.position.x - item.halfSize.width,
                        y: projected.position.y - item.halfSize.height,
                        width: item.halfSize.width * 2, height: item.halfSize.height * 2)
                }
                var overlap = 0.0
                for index in frames.indices {
                    for other in frames.dropFirst(index + 1) {
                        let intersection = frames[index].intersection(other)
                        if !intersection.isNull { overlap += intersection.width * intersection.height }
                    }
                }
                if overlap < bestOverlap {
                    bestOverlap = overlap
                    openingYaw = yaw
                    openingPitch = pitch
                }
            }
        }
        studyYaw = openingYaw
        completedBranchPitch = openingPitch
        // A spherical point spread can still stack wide labels along the view axis. Start
        // Branch's children in the opening view plane and spread their label footprints around
        // their own semantic radii. Rotation remains 3D and the radii never change.
        let right = SIMD3(cos(openingYaw), sin(openingYaw), 0)
        let up = SIMD3(-sin(openingYaw) * cos(openingPitch),
                       cos(openingYaw) * cos(openingPitch), sin(openingPitch))
        let openingCamera = framing.camera(from: treeCamera, progress: 1, yaw: openingYaw,
            zoom: StudyFraming.entryZoom, endPitch: openingPitch)
        items = [(center, CGSize(width: 138, height: 80))] + items.dropFirst(node.insights.count + 1)
        var occupied = items.compactMap { item -> CGRect? in
            guard let point = openingCamera.project(item.point)?.position else { return nil }
            return CGRect(x: point.x - item.halfSize.width, y: point.y - item.halfSize.height,
                width: item.halfSize.width * 2, height: item.halfSize.height * 2)
        }
        for (index, child) in node.insights.sorted(by: {
            bondLength(forInsightID: $0.id) < bondLength(forInsightID: $1.id)
        }).enumerated() {
            let radius = Double(bondLength(forInsightID: child.id))
            let footprint = insightCollisionSize(for: child)
            let halfSize = CGSize(width: footprint.width / 2 + 8, height: footprint.height / 2 + 8)
            let preferred = index.isMultiple(of: 2) ? Double.pi / 2 : -Double.pi / 2
            var bestCost = Double.infinity
            var bestDirection = up
            var bestFrame = CGRect.zero
            for step in 0..<120 {
                let angle = preferred + Double(step) * 2 * .pi / 120
                let direction = right * cos(angle) + up * sin(angle)
                guard let point = openingCamera.project(center + direction * radius)?.position else { continue }
                let frame = CGRect(x: point.x - halfSize.width, y: point.y - halfSize.height,
                    width: halfSize.width * 2, height: halfSize.height * 2)
                let area = occupied.reduce(0.0) { total, other in
                    let intersection = frame.intersection(other)
                    return total + (intersection.isNull ? 0 : intersection.width * intersection.height)
                }
                if area < bestCost {
                    bestCost = area
                    bestDirection = direction
                    bestFrame = frame
                    if area == 0 { break }
                }
            }
            studySpread[child.id] = bestDirection
            items.append((center + bestDirection * radius, halfSize))
            occupied.append(bestFrame)
        }
        var zoom = StudyFraming.entryZoom
        var bounds = CGRect.zero
        for _ in 0..<6 {
            let camera = framing.camera(from: treeCamera, progress: 1, yaw: openingYaw,
                zoom: zoom, endPitch: openingPitch)
            let frames = items.compactMap { item -> CGRect? in
                guard let projected = camera.project(item.point) else { return nil }
                let contentScale = min(zoom / StudyFraming.entryZoom, 1)
                let halfWidth = item.halfSize.width * contentScale
                let halfHeight = item.halfSize.height * contentScale
                return CGRect(x: projected.position.x - halfWidth,
                    y: projected.position.y - halfHeight,
                    width: halfWidth * 2, height: halfHeight * 2)
            }
            bounds = frames.reduce(CGRect.null) { $0.union($1) }
            guard !bounds.isNull else { return }
            let fit = min(1, (size.width - 48) / bounds.width, (size.height - 48) / bounds.height)
            if fit > 0.98 { break }
            zoom *= max(fit * 0.96, 0.1)
        }
        studyZoom = zoom
        studyPan = CGSize(width: size.width / 2 - bounds.midX, height: size.height / 2 - bounds.midY)
    }

    /// Studies selected Insights on their own, around their centroid. They keep a node-sized
    /// sphere however far apart they were in the tree.
    func beginStudy(ofSelection insightIDs: [UUID]) {
        let layout = makeInsightLayout()
        let placements = insightIDs.compactMap { layout.placements[$0] }
        guard !placements.isEmpty else { return }
        let center = CGPoint(
            x: placements.map(\.world.x).reduce(0, +) / CGFloat(placements.count),
            y: placements.map(\.world.y).reduce(0, +) / CGFloat(placements.count)
        )
        studyFocusNodeID = nil
        studySelectionMembers = Set(placements.map(\.insight.id))
        startStudy(around: center, placements: placements, radius: 190)
        studySelectionCenter = center
        flyIntoStudy()
    }

    /// Each studied Insight's tree offset from `center`, its direction on the Study sphere, and
    /// a fresh Study camera. `radius` nil uses the Insights' mean distance.
    private func startStudy(around center2D: CGPoint, placements: [InsightPlacement], radius: Double?) {
        let center = SIMD3(Double(center2D.x), Double(center2D.y), 0)
        var ids: [UUID] = []
        var offsets: [SIMD3<Double>] = []
        for placement in placements where !placement.isPinnedAtNode {
            ids.append(placement.insight.id)
            offsets.append(SIMD3(
                Double(placement.world.x), Double(placement.world.y), Double(placement.elevation)
            ) - center)
        }
        studyTreeOffsets = Dictionary(uniqueKeysWithValues: zip(ids, offsets))
        studySpread = Dictionary(uniqueKeysWithValues: zip(ids, StudyNodeLayout.sphereSpread(from: offsets)))
        let lengths = offsets.map(simd_length).filter { $0 > 1 }
        studyRadius = radius ?? (lengths.isEmpty ? 190 : lengths.reduce(0, +) / Double(lengths.count))
        studyYaw = 0
        studyPan = .zero
        studyZoom = StudyFraming.entryZoom
        studyLastDetentYaw = 0
        studyPivotLink?.stop()
        studyPivotSwitchLink?.stop()
        studyPivotID = nil
        studyPivotFrom = nil
        studyPivotBlend = 0
        studyTargetShift = .zero
    }

    private func flyIntoStudy() {
        // Opened from an Insight's Study: fly straight to that Insight, hovered. It is already
        // the hover, so only the Study camera needs it.
        if let insightID = studyInitialHoverInsightID, studyTreeOffsets[insightID] != nil {
            studyPivotID = insightID
            studyPivotBlend = 1
            studyZoom = max(studyZoom, StudyFraming.hoverZoom)
        }
        animateStudyProgress(to: 1, duration: 0.8)
    }

    func endStudy() {
        guard isInStudy else { return }
        studyDragMode = nil
        studyRingActive = 0
        studySpinLink?.stop()
        studySpinLink = nil
        // Whole turns look identical, so drop them before flying back: the exit unwinds at most
        // half a turn, the short way, rather than every turn the user made.
        let wrappedYaw = remainder(studyYaw, 2 * .pi)
        studyLastDetentYaw += wrappedYaw - studyYaw
        studyYaw = wrappedYaw
        // Leaving Study keeps a hovered Insight hovered; only the Study camera lets go of it.
        if studyPivotID != nil { releaseStudyPivot(in: lastCanvasSize) }
        animateStudyProgress(to: 0, duration: 0.6) {
            studyFocusNodeID = nil
            studySelectionCenter = nil
            studySelectionMembers = []
            studyTreeOffsets = [:]
            studySpread = [:]
        }
    }

    /// Drives the camera move frame by frame (ease in-out), since every position on the canvas
    /// is computed from `studyProgress` rather than interpolated by SwiftUI.
    private func animateStudyProgress(to target: Double, duration: Double, completion: (() -> Void)? = nil) {
        studyLink?.stop()
        let from = studyProgress
        let start = CACurrentMediaTime()
        let driver = DisplayLinkDriver()
        driver.onTick = { now in
            let t = min(max((now - start) / duration, 0), 1)
            let eased = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
            studyProgress = from + (target - from) * eased
            if t >= 1 {
                studyLink?.stop()
                studyLink = nil
                completion?()
            }
        }
        driver.start()
        studyLink = driver
    }

    /// In Study a drag on the ring spins the node like a turntable; any other drag moves it. It
    /// starts on touch-down so the ring responds the moment a finger lands on it.
    func studyDragGesture(
        ring: [CGPoint],
        chips: [(id: UUID, frame: CGRect)],
        nodeFrame: CGRect?,
        size: CGSize
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if studyDragMode == nil {
                    // Any touch catches a coasting ring.
                    studySpinLink?.stop()
                    studySpinLink = nil
                    let onRing = StudyFraming.distance(from: value.startLocation, toPolyline: ring) < 28
                    studyDragMode = onRing ? .rotate : .pending
                    studyLastDragLocation = value.startLocation
                    if studyDragMode == .rotate {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
                        withAnimation(.easeInOut(duration: 0.25)) { studyRingActive = 1 }
                    }
                }
                if studyDragMode == .pending {
                    // Still possibly a tap; becomes a pan once it moves.
                    guard hypot(value.translation.width, value.translation.height) > Self.studyTapSlop else { return }
                    studyDragMode = .pan
                    // Like panning in the tree, moving around unhovers whatever is hovered and
                    // its card goes away (open tools stay open).
                    if studyPivotID != nil {
                        unhoverStudyInsight(in: size)
                    } else {
                        onRequestDismissHover()
                    }
                }
                let previous = studyLastDragLocation ?? value.startLocation
                let delta = CGSize(width: value.location.x - previous.x, height: value.location.y - previous.y)
                studyLastDragLocation = value.location
                switch studyDragMode {
                case .rotate:
                    // Dragging right carries the front of the ring to the right.
                    let xs = ring.map(\.x)
                    let halfWidth = max(((xs.max() ?? 0) - (xs.min() ?? 0)) / 2, 40)
                    studyRingHalfWidth = halfWidth
                    spinStudy(by: -Double(delta.width / halfWidth))
                case .pan:
                    studyPan.width += delta.width
                    studyPan.height += delta.height
                case .pending, nil:
                    break
                }
            }
            .onEnded { value in
                if studyDragMode == .pending {
                    if let hit = chips.first(where: { $0.frame.contains(value.location) }) {
                        hoverStudyInsight(hit.id, in: size)
                    } else if let nodeFrame, nodeFrame.contains(value.location) {
                        hoverStudyNode(in: size)
                    }
                } else if studyDragMode == .rotate {
                    coastStudySpin(velocity: -Double(value.velocity.width / studyRingHalfWidth))
                }
                studyDragMode = nil
                studyLastDragLocation = nil
                withAnimation(.easeInOut(duration: 0.3)) { studyRingActive = 0 }
            }
    }

    var studyPinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = studyPinchStartZoom ?? studyZoom
                studyPinchStartZoom = start
                studyZoom = min(max(start * value.magnification, 0.5), 5)
            }
            .onEnded { _ in studyPinchStartZoom = nil }
    }

    /// Where the camera centers for the focused Insight, gliding from the previous one.
    private func studyPivotPoint(framing: StudyFraming) -> SIMD3<Double>? {
        guard let id = studyPivotID, let target = studyInsightPosition(id, framing: framing) else { return nil }
        guard let from = studyPivotFrom else { return target }
        return from + (target - from) * studyPivotSwitch
    }

    /// A studied Insight's position on its Study sphere.
    private func studyInsightPosition(_ insightID: UUID, framing: StudyFraming) -> SIMD3<Double>? {
        guard let offset = studyOffset(forInsightID: insightID) else { return nil }
        return framing.nodeCenter + offset
    }

    /// Where each studied Insight's chip is on screen, padded for an easy tap.
    func studyTapTargets(
        layout: CanvasInsightLayout,
        camera: InsightTreeCamera,
        size: CGSize
    ) -> [(id: UUID, frame: CGRect)] {
        let studied: [InsightModel]
        if let focus = studyFocusNodeID {
            studied = layout.insightsByNode[focus] ?? []
        } else {
            studied = studySelectionMembers.compactMap { layout.placements[$0]?.insight }
        }
        return studied.compactMap { insight in
            guard let placement = layout.placements[insight.id], !placement.isPinnedAtNode else { return nil }
            let projection = insightProjection(placement, camera: camera, size: size)
            let chip = insightCollisionSize(for: insight)
            let scale = chipScale(nodeID: placement.nodeID, magnification: projection.scale)
            let frame = CGRect(
                x: projection.position.x - chip.width * scale / 2,
                y: projection.position.y - chip.height * scale / 2,
                width: chip.width * scale,
                height: chip.height * scale
            )
            return (insight.id, frame.insetBy(dx: -8, dy: -8))
        }
        // Nearer chips first, so the one drawn on top wins an overlapping tap.
        .sorted { first, second in
            (studyDepth(of: first.id, camera: camera) ?? 0) < (studyDepth(of: second.id, camera: camera) ?? 0)
        }
    }

    private func studyDepth(of insightID: UUID, camera: InsightTreeCamera) -> Double? {
        guard let orbit = camera.orbit, let center = camera.studyNodeCenter,
              let offset = studyOffset(forInsightID: insightID) else { return nil }
        return orbit.project(center + offset)?.depth
    }

    /// Hovering an Insight in Study is the tree's hover (same haptic, card state, and pulses via
    /// `onInsightTapped`), and the Study camera centers it, zooms in, and turns around it. The
    /// tree's own camera focuses it too, unseen, so leaving Study lands on it still hovered.
    private func hoverStudyInsight(_ insightID: UUID, in size: CGSize) {
        guard let nodeID = studyFocusNodeID ?? parentNodeID(ofInsight: insightID),
              let node = nodes.first(where: { $0.id == nodeID }),
              let insight = node.insights.first(where: { $0.id == insightID }) else { return }
        markDiscovered(insightID)
        if let treeOffset = studyTreeOffsets[insightID] {
            let base = studySelectionCenter ?? bodies[nodeID]?.pos ?? node.position
            focusHoveredTarget(
                at: CGPoint(x: base.x + CGFloat(treeOffset.x), y: base.y + CGFloat(treeOffset.y)),
                elevation: CGFloat(treeOffset.z),
                in: size
            )
        }
        onInsightTapped(insight)
        focusStudyInsight(insightID)
    }

    /// The studied node's label on screen, padded for an easy tap.
    func studyNodeTapTarget(camera: InsightTreeCamera, size: CGSize) -> CGRect? {
        guard let focus = studyFocusNodeID,
              let node = displayNodes.first(where: { $0.id == focus }) else { return nil }
        let position = camera.project(node.position, in: size).position
        let width: CGFloat = node.isSuggested ? 220 : 260
        return CGRect(x: position.x - width / 2, y: position.y - 44, width: width, height: 88)
    }

    /// Tapping the studied node hovers it (the tree's node hover), and the camera glides back to
    /// center the node with the axis on it (from a hovered Insight, or from a pan).
    private func hoverStudyNode(in size: CGSize) {
        guard let focus = studyFocusNodeID,
              let node = displayNodes.first(where: { $0.id == focus }) else { return }
        if studyPivotID != nil { releaseStudyPivot(in: size) }
        recenterStudyNode()
        focusHoveredTarget(at: node.position, in: size)
        onNodeTapped(node)
    }

    /// Eases any pan and look-at shift back to zero, centering the node, and zooms in like a
    /// hover in the tree (to at least `StudyFraming.hoverZoom`).
    private func recenterStudyNode() {
        let fromPan = studyPan
        let fromShift = studyTargetShift
        let fromZoom = studyZoom
        let toZoom = max(studyZoom, StudyFraming.hoverZoom)
        studyPivotLink?.stop()
        let start = CACurrentMediaTime()
        let driver = DisplayLinkDriver()
        driver.onTick = { now in
            let (eased, done) = Self.studyHoverCurve(elapsed: now - start)
            studyPan = CGSize(width: fromPan.width * (1 - eased), height: fromPan.height * (1 - eased))
            studyTargetShift = fromShift * (1 - eased)
            studyZoom = fromZoom + (toZoom - fromZoom) * CGFloat(eased)
            if done {
                studyPivotLink?.stop()
                studyPivotLink = nil
            }
        }
        driver.start()
        studyPivotLink = driver
    }

    /// Turns the node, with a detent haptic every 15°.
    private func spinStudy(by delta: Double) {
        studyYaw += delta
        if abs(studyYaw - studyLastDetentYaw) >= .pi / 12 {
            studyLastDetentYaw = studyYaw
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    /// After a ring swipe the node keeps turning at the release velocity (radians per second)
    /// and eases to a stop.
    private func coastStudySpin(velocity: Double) {
        studySpinLink?.stop()
        guard abs(velocity) > 0.3 else { return }
        var speed = min(max(velocity, -12), 12)
        var last = CACurrentMediaTime()
        let driver = DisplayLinkDriver()
        driver.onTick = { now in
            let dt = min(now - last, 1.0 / 30)
            last = now
            spinStudy(by: speed * dt)
            speed *= exp(-3.2 * dt)
            if abs(speed) < 0.05 {
                studySpinLink?.stop()
                studySpinLink = nil
            }
        }
        driver.start()
        studySpinLink = driver
    }

    /// Unhovering clears the hover, like panning in the tree, and returns the axis of rotation to
    /// the Study center without moving the view.
    private func unhoverStudyInsight(in size: CGSize) {
        releaseStudyPivot(in: size)
        onRequestDismissHover()
    }

    private func focusStudyInsight(_ insightID: UUID) {
        guard insightID != studyPivotID || studyPivotBlend < 1 else { return }
        let settledPan = studyPan
        if studyPivotID != nil, studyPivotID != insightID, studyPivotBlend > 0,
           // Only the node's position matters here, not the canvas size.
           let framing = makeStudyFraming(in: .zero),
           let from = studyPivotPoint(framing: framing) {
            // Moving between focused Insights: glide from one to the other.
            studyPivotFrom = from
            studyPivotID = insightID
            animateStudyPivotSwitch()
            return animateStudyPivot(to: 1)
        }
        studyPivotID = insightID
        animateStudyPivot(to: 1) {
            // Fully centered: the pan and any shift have eased out, so drop them for good.
            if studyPan == settledPan {
                studyPan = .zero
                studyTargetShift = .zero
            }
        }
    }

    /// The tree's hover spring as a 0 → 1 curve (it overshoots slightly), and whether it has
    /// settled.
    private static func studyHoverCurve(elapsed: TimeInterval) -> (value: Double, done: Bool) {
        let spring = StudyFraming.hoverSpring
        guard elapsed < spring.settlingDuration else { return (1, true) }
        return (spring.value(target: 1.0, time: elapsed), false)
    }

    /// Returns the axis of rotation to the node's center without moving anything on screen: the
    /// rotation center moves to the node while the look-at point, zoom, and pan are re-expressed
    /// so every point projects exactly where it did.
    func releaseStudyPivot(in size: CGSize) {
        studyPivotLink?.stop()
        studyPivotSwitchLink?.stop()
        defer {
            studyPivotID = nil
            studyPivotFrom = nil
            studyPivotBlend = 0
        }
        guard let framing = makeStudyFraming(in: size),
              let current = studyCamera(
                  InsightTreeCamera(scale: activeScale, offset: activeOffset),
                  framing: framing,
                  in: size
              ).orbit,
              studyProgress > 0.99
        else { return }
        let blend = studyPivotBlend
        let newTarget = current.target(
            keepingViewWhenCenterMovesFrom: current.rotationCenter ?? current.target,
            to: framing.nodeCenter
        )
        studyTargetShift = newTarget - framing.nodeCenter
        // Fold the focus's zoom and eased-out pan into the plain Study values.
        studyZoom *= 1 + (StudyFraming.hoverZoomFactor(zoom: studyZoom) - 1) * CGFloat(blend)
        studyPan = CGSize(
            width: studyPan.width * (1 - blend),
            height: studyPan.height * (1 - blend) + StudyFraming.pivotDrop * blend
        )
    }

    private func animateStudyPivotSwitch() {
        studyPivotSwitchLink?.stop()
        studyPivotSwitch = 0
        let start = CACurrentMediaTime()
        let driver = DisplayLinkDriver()
        driver.onTick = { now in
            let (eased, done) = Self.studyHoverCurve(elapsed: now - start)
            studyPivotSwitch = eased
            if done {
                studyPivotSwitchLink?.stop()
                studyPivotSwitchLink = nil
                studyPivotFrom = nil
            }
        }
        driver.start()
        studyPivotSwitchLink = driver
    }

    private func animateStudyPivot(to target: Double, completion: (() -> Void)? = nil) {
        studyPivotLink?.stop()
        let from = studyPivotBlend
        let start = CACurrentMediaTime()
        let driver = DisplayLinkDriver()
        driver.onTick = { now in
            let (eased, done) = Self.studyHoverCurve(elapsed: now - start)
            studyPivotBlend = from + (target - from) * eased
            if done {
                studyPivotLink?.stop()
                studyPivotLink = nil
                completion?()
            }
        }
        driver.start()
        studyPivotLink = driver
    }

    /// The Node currently hosting `insightID` as one of its own (non-pinned) chips.
    func parentNode(ofInsightID insightID: UUID) -> NodeModel? {
        nodes.first { node in
            !placedMidpointNodeIDs.contains(node.id) && node.insights.contains { $0.id == insightID }
        }
    }

}
