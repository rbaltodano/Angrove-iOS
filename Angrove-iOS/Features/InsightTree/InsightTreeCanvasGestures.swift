import SwiftUI
import UIKit
import simd

// Gestures behavior for the shared global and conversation canvas.
extension InsightTreeCanvasView {
    func panGesture(camera: InsightTreeCamera, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($dragOffset) { value, state, _ in
                // An Insight chip's own press-and-hold rotate-drag (see `chipRotateDragGesture`)
                // is attached lower in the hierarchy as merely `.simultaneousGesture`, which does
                // NOT stop this root-level pan gesture from also recognizing the same touch once
                // it moves — so panning the whole canvas would otherwise hijack every chip drag.
                // The hold itself doesn't move enough to trip `minimumDistance: 2`, so this guard
                // only ever needs to catch the drag phase, which starts after `draggingChipID` is
                // already set.
                guard draggingChipID == nil else {
                    panGestureBlockedByChipDrag = true
                    return
                }
                // Lock the handle-vs-pan decision to the gesture's start so it can't
                // flip to panning as the handle moves away from the finger.
                guard !isHandleDragStart(value.startLocation, camera: camera, size: size) else { return }
                state = flatTranslation(value, camera: camera, size: size)
            }
            .onChanged { value in
                guard draggingChipID == nil else {
                    panGestureBlockedByChipDrag = true
                    return
                }
                if dragStartHandleWorld == nil {
                    dragStartHandleWorld = midpointHandleWorld   // capture once at gesture start
                }
                if isHandleDragStart(value.startLocation, camera: camera, size: size) {
                    let newHandle = constrainHandle(camera.screenToWorld(value.location, in: size))
                    midpointHandleWorld = newHandle
                    reportMidpointWeights()
                    // Light haptic for every 1% change while dragging the dot.
                    let pct = Int(((midpointWeights(for: newHandle).first ?? 0) * 100).rounded())
                    if pct != lastHandleHapticPercent {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
                        lastHandleHapticPercent = pct
                    }
                    return
                }
                if markCanvasDragIfNeeded(value.translation) {
                    cameraState.userMovedSincePlacement = true
                    onCanvasMoved()
                }
            }
            .onEnded { value in
                let wasHandleDrag = isHandleDragStart(value.startLocation, camera: camera, size: size)
                dragStartHandleWorld = nil
                lastHandleHapticPercent = nil
                guard !wasHandleDrag else { return }
                guard !panGestureBlockedByChipDrag else {
                    panGestureBlockedByChipDrag = false
                    return
                }
                let translation = flatTranslation(value, camera: camera, size: size)
                cameraState.offset.width += translation.width
                cameraState.offset.height += translation.height

                if hypot(value.translation.width, value.translation.height) > 8 {
                    cameraState.lastDragEndedAt = Date()
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    cameraState.isDragging = false
                }
            }
    }

    /// A screen drag converted to the flat pan offset that keeps the grabbed point of the
    /// perspective plane under the finger. Independent of the current offset.
    private func flatTranslation(_ value: DragGesture.Value, camera: InsightTreeCamera, size: CGSize) -> CGSize {
        let projection = camera.projection(in: size)
        let start = projection.unproject(value.startLocation)
        let current = projection.unproject(value.location)
        return CGSize(width: current.x - start.x, height: current.y - start.y)
    }

    /// Whether the gesture began on the handle. Uses the handle position captured at the
    /// gesture's start (falling back to the live position on the very first event) so the
    /// decision stays stable as the handle is dragged.
    private func isHandleDragStart(_ startLocation: CGPoint, camera: InsightTreeCamera, size: CGSize) -> Bool {
        guard isMidpointMode, let handle = dragStartHandleWorld ?? midpointHandleWorld else { return false }
        let screen = camera.worldToScreen(handle, in: size)
        // Generous grab zone, biased upward to cover the bobbing icon that sits above the circle.
        let center = CGPoint(x: screen.x, y: screen.y - 16)
        return hypot(startLocation.x - center.x, startLocation.y - center.y) <= 64
    }

    /// Press-and-hold an Insight chip, then drag it anywhere — the connector line stretches to
    /// follow (see `insightWorldPosition`'s `draggingChipID` check). On release the bond length
    /// eases back to what it was before (relatedness to the parent Node is unchanged), but the
    /// angle you dragged to sticks. Any placed Midpoint this chip is a source of gets its other
    /// source re-aimed at the same time, so the two ends of that connection keep facing each
    /// other instead of drifting back into a crossing line.
    func chipRotateDragGesture(
        insight: InsightModel,
        node: NodeModel,
        index: Int,
        count: Int,
        isPinnedAtNode: Bool,
        camera: InsightTreeCamera,
        size: CGSize
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.canvasSpace))
            .onChanged { value in
                if draggingChipID == insight.id {
                    // Unproject at the chip's own elevation so the chip stays exactly under the finger.
                    draggingChipWorldPosition = isPinnedAtNode
                        ? camera.screenToWorld(value.location, in: size)
                        : draggedChipFootprint(under: value.location, insight: insight, node: node, camera: camera, size: size)
                    // Top up the frame budget every move so a long drag never lets the sim
                    // expire mid-gesture — but WITHOUT re-boosting `alpha` (startSim's own
                    // `max(alpha, intensity)` would do that on every single move event). Alpha
                    // scales both the repulsion force and its random per-frame jitter term, so
                    // continuously re-flooring it near the drag's initial intensity kept the
                    // whole layout visibly trembling for as long as the drag lasted; letting it
                    // decay on its own settles the jitter while collision avoidance stays live.
                    simFramesRemaining = max(simFramesRemaining, Self.settleFrameBudget)
                    return
                }
                guard draggingChipID == nil else { return }   // some other chip owns the drag
                chipPressLastLocation = value.location
                guard chipPressCandidateID != insight.id else { return }   // timer already armed
                chipPressCandidateID = insight.id
                chipPressStartLocation = value.location
                chipPressLastLocation = value.location
                let capturedID = insight.id
                // A placed Midpoint's chip sits ON its node — nothing to orbit, so its "start"
                // is just its own current position, and dragging repositions it freely instead
                // of picking a new angle.
                let startWorld = isPinnedAtNode ? node.position : insightWorldPosition(for: node, index: index, count: count)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    guard chipPressCandidateID == capturedID, draggingChipID == nil else { return }
                    // Cancelled if the finger drifted too far during the hold — that's a pan,
                    // not a rotate-drag, and the root pan gesture is already handling it.
                    if let start = chipPressStartLocation, let last = chipPressLastLocation,
                       hypot(last.x - start.x, last.y - start.y) > 14 {
                        chipPressCandidateID = nil
                        return
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.75)
                    withAnimation(.springLively) {
                        draggingChipID = capturedID
                        draggingChipWorldPosition = startWorld
                        draggingChipStartWorldPosition = startWorld
                    }
                    // Keep the sim actively stepping for the whole drag — nearby chips/nodes
                    // need live collision forces reacting every frame to make room, not just a
                    // one-shot settle once the finger lifts. A modest starting intensity (rather
                    // than a full topology-change jolt) keeps that initial nudge from reading as
                    // a jitter itself.
                    startSim(intensity: 0.22, alphaDecay: Self.updateAlphaDecay, frameBudget: Self.settleFrameBudget)
                }
            }
            .onEnded { value in
                let wasDragging = draggingChipID == insight.id
                if chipPressCandidateID == insight.id {
                    chipPressCandidateID = nil
                }
                guard wasDragging else { return }   // released before the hold armed: a plain tap
                // Commit whatever position the drag settled at (either this Midpoint's own free
                // reposition, or a followed Midpoint's drift — see `stepSimulation`'s pinned-body
                // loop) into the view model BEFORE clearing the drag state below — otherwise the
                // very next simulation tick's "pinned bodies track their authoritative
                // view-model position" sync would read the OLD, uncommitted position and snap
                // straight back.
                persistLivePositions()
                if isPinnedAtNode {
                    // Free reposition: wherever it was dropped IS the new position — no angle or
                    // bond length to compute (there's no orbit to compute them around).
                    withAnimation(.springRelaxed) {
                        draggingChipID = nil
                        draggingChipWorldPosition = nil
                        draggingChipStartWorldPosition = nil
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                    return
                }
                // Unproject at the chip's elevation: the drop point is its footprint on the plane,
                // so raised or lowered chips keep the angle they were released at.
                let releasePoint = draggedChipFootprint(
                    under: value.location, insight: insight, node: node, camera: camera, size: size
                )
                let finalAngle = Double(atan2(
                    releasePoint.y - node.position.y,
                    releasePoint.x - node.position.x
                ))
                withAnimation(.springRelaxed) {
                    chipAngles[insight.id] = ChipAngle(angle: finalAngle)
                    pinnedChipAngleIDs.insert(insight.id)
                    draggingChipID = nil
                    draggingChipWorldPosition = nil
                    draggingChipStartWorldPosition = nil
                    for midpointID in midpointIDs(sourcedBy: insight.id) {
                        reangleMidpointSources(of: midpointID, excluding: insight.id)
                    }
                }
                UISelectionFeedbackGenerator().selectionChanged()
            }
    }

    func zoomGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                if cameraState.pinchStartScale == nil {
                    cameraState.pinchStartScale = cameraState.scale
                    cameraState.pinchStartOffset = cameraState.offset
                    cameraState.userMovedSincePlacement = true
                    onCanvasMoved()
                }

                let initialScale = cameraState.pinchStartScale ?? cameraState.scale
                let initialOffset = cameraState.pinchStartOffset ?? cameraState.offset
                let nextScale = insightTreeCanvasClamp(initialScale * pow(value.magnification, 0.72), lower: 0.28, upper: 2.6)
                let anchor = InsightTreeCamera(scale: initialScale, offset: initialOffset)
                    .projection(in: size)
                    .unproject(CGPoint(
                        x: value.startAnchor.x * size.width,
                        y: value.startAnchor.y * size.height
                    ))

                cameraState.scale = nextScale
                cameraState.offset = offsetKeeping(anchor, fixedFrom: initialOffset, initialScale: initialScale, nextScale: nextScale, in: size)
            }
            .onEnded { value in
                let initialScale = cameraState.pinchStartScale ?? cameraState.scale
                let initialOffset = cameraState.pinchStartOffset ?? cameraState.offset
                let nextScale = insightTreeCanvasClamp(initialScale * pow(value.magnification, 0.72), lower: 0.28, upper: 2.6)
                let anchor = InsightTreeCamera(scale: initialScale, offset: initialOffset)
                    .projection(in: size)
                    .unproject(CGPoint(
                        x: value.startAnchor.x * size.width,
                        y: value.startAnchor.y * size.height
                    ))

                cameraState.scale = nextScale
                cameraState.offset = offsetKeeping(anchor, fixedFrom: initialOffset, initialScale: initialScale, nextScale: nextScale, in: size)
                cameraState.pinchStartScale = nil
                cameraState.pinchStartOffset = nil
            }
    }

    private func offsetKeeping(
        _ anchor: CGPoint,
        fixedFrom initialOffset: CGSize,
        initialScale: CGFloat,
        nextScale: CGFloat,
        in size: CGSize
    ) -> CGSize {
        let centeredAnchorX = anchor.x - size.width / 2
        let centeredAnchorY = anchor.y - size.height / 2
        let worldX = (centeredAnchorX - initialOffset.width) / initialScale
        let worldY = (initialOffset.height - centeredAnchorY) / initialScale

        return CGSize(
            width: centeredAnchorX - (worldX * nextScale),
            height: centeredAnchorY + (worldY * nextScale)
        )
    }

    var canAcceptTap: Bool {
        !cameraState.isDragging && Date().timeIntervalSince(cameraState.lastDragEndedAt) > 0.16
    }

    /// Pans (and, if `targetScale` is supplied, simultaneously zooms) to center `worldPosition`
    /// — a single spring rather than two sequential ones when both need to change together.
    func focusInsight(at worldPosition: CGPoint, in size: CGSize, targetScale: CGFloat? = nil) {
        rememberCameraBeforeFocusIfNeeded()
        let nextScale = targetScale ?? cameraState.scale
        let target = focusFlatTarget(elevation: 0, scale: nextScale, in: size)

        withAnimation(.springCamera) {
            cameraState.scale = nextScale
            cameraState.offset = CGSize(
                width: target.x - size.width / 2 - (worldPosition.x * nextScale),
                height: target.y - size.height / 2 + (worldPosition.y * nextScale)
            )
        }
    }

    /// Centers a hovered target on screen. An Insight passes its elevation so the chip itself —
    /// not its footprint on the plane — lands under the selection reticle.
    /// Returns the zoom scale the camera is animating to.
    @discardableResult
    func focusHoveredTarget(at worldPosition: CGPoint, elevation: CGFloat = 0, in size: CGSize) -> CGFloat {
        rememberCameraBeforeFocusIfNeeded()
        let nextScale = insightTreeCanvasClamp(max(cameraState.scale, 1.15), lower: 0.28, upper: 2.6)
        let target = focusFlatTarget(elevation: elevation, scale: nextScale, in: size)

        withAnimation(.springCamera) {
            cameraState.scale = nextScale
            cameraState.offset = CGSize(
                width: target.x - size.width / 2 - (worldPosition.x * nextScale),
                height: target.y - size.height / 2 + (worldPosition.y * nextScale)
            )
        }
        return nextScale
    }

    /// The flat (pre-perspective) point a target must occupy to project onto the focus anchor.
    private func focusFlatTarget(elevation: CGFloat, scale: CGFloat, in size: CGSize) -> CGPoint {
        InsightTreeCamera(scale: scale, offset: .zero)
            .flatPointCentering(elevation: elevation, in: size)
    }

    func rememberCameraBeforeFocusIfNeeded() {
        guard cameraState.preFocusSnapshot == nil else { return }

        cameraState.preFocusSnapshot = InsightTreeCameraSnapshot(
            scale: cameraState.scale,
            offset: cameraState.offset
        )
    }

    func restorePreFocusCamera() {
        guard let snapshot = cameraState.preFocusSnapshot else { return }

        withAnimation(.springCamera) {
            cameraState.scale = snapshot.scale
            cameraState.offset = snapshot.offset
        }

        cameraState.preFocusSnapshot = nil
    }

    @discardableResult
    private func markCanvasDragIfNeeded(_ translation: CGSize) -> Bool {
        guard hypot(translation.width, translation.height) > 8 else { return false }
        guard !cameraState.isDragging else { return false }
        cameraState.isDragging = true
        return true
    }

}
