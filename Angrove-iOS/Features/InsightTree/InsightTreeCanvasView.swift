//
//  InsightTreeCanvasView.swift
//  Angrove-iOS
//

import SwiftUI
import UIKit
import Observation
import simd

// MARK: - Insight Tree Canvas

/// SwiftUI-native graph renderer for the insight tree.
/// Text and SF Symbols stay vector/crisp while the graph remains pannable and zoomable.
struct InsightTreeCanvasView: View {
    @AppStorage(SettingsStorageKey.insightTreeBackground) private var insightTreeBackground: CanvasBackgroundOption = .system
    let nodes: [NodeModel]
    let edges: [EdgeModel]
    let restoreFocusedCameraRequest: Int
    let focusedInsightID: UUID?
    let focusedSearchNodeID: UUID?
    let pulsingInsightID: UUID?
    let pulsingNodeID: UUID?
    let selectedCanvasTargets: [CanvasSelectionTarget]
    let selectionPulseRequest: Int
    var showsBackground: Bool = true
    var makeNodeChildIDs: Set<UUID> = []
    var generatedMakeNodeChildIDs: Set<UUID> = []
    /// Nodes that are user-placed midpoints — rendered as a bare insight chip (no
    /// node-concept circle), pinned at the node position.
    var placedMidpointNodeIDs: Set<UUID> = []
    /// For each placed-midpoint node, the sources it connects to (insight chips / node concepts).
    var placedMidpointSources: [UUID: [MidpointSource]] = [:]
    /// Per-insight bond length (connector radius) from relatedness to the parent node.
    var insightBondLengths: [UUID: CGFloat] = [:]
    /// Semantic (MDS) target position per node. The sim anchors each node here with a weak
    /// spring so overlap cleanup can't destroy the embedding-driven layout.
    var layoutTargets: [UUID: CGPoint] = [:]
    /// Normalized [0,1] depth per node (1 = nearest) from the third MDS component,
    /// driving the 2.5D depth cues. Missing entries render at full depth.
    var nodeDepths: [UUID: Double] = [:]
    /// Global Insights renders every member in each cluster. Conversation trees remain compact.
    var showsAllClusterInsights: Bool = false
    /// Conversation trees begin with an in-memory build and apply their on-device seeds
    /// asynchronously. Their entrance must wait for that seeded snapshot.
    var defersEntranceUntilPersistedTree: Bool = false
    /// Advances after the seeded snapshot is applied.
    var persistedTreePresentationRevision: Int = 0
    /// Matches the presentation revision only when that snapshot follows a real mutation.
    var animatedPersistedTreePresentationRevision: Int = 0
    var isHoveringTarget: Bool = false
    /// Nodes whose generated name is still pending; their label shimmers until it arrives.
    var namingNodeIDs: Set<UUID> = []
    var isMidpointMode: Bool = false
    var midpointCenterRequest: Int = 0
    var midpointPlaceRequest: Int = 0
    var midpointTargetIndex: Int = 0            // which selected insight's weight to set
    var midpointTargetWeight: Double = 0.5      // desired weight (0–1) for that insight
    var midpointPercentRequest: Int = 0
    var onMidpointWeightsChange: ([Double]) -> Void = { _ in }
    var onNodeTapped: (NodeModel) -> Void
    var onInsightTapped: (InsightModel) -> Void
    var onCanvasMoved: () -> Void
    var onSuggestConnection: (EdgeModel) -> Void
    var onDismissSuggestedNode: (NodeModel) -> Void
    var onMidpointPlaced: (CGPoint, CanvasSelectionTarget, [Double]) -> Void = { _, _, _ in }
    /// The insight id of a just-placed midpoint, so it runs the loading-icon → text-reveal sequence.
    var midpointPlacedInsightID: UUID? = nil
    /// Matches the placed id after generated content has replaced the loading placeholder.
    var midpointGeneratedInsightID: UUID? = nil
    /// Fired once the placed midpoint insight has "loaded" (icon flash → text reveal → dot pulse),
    /// so the orchestration layer can pop its card.
    var onMidpointInsightLoaded: (UUID) -> Void = { _ in }
    /// True while Make Node children are generating, so the Context wheel spins.
    var onGeneratingChange: (Bool) -> Void = { _ in }
    /// Fired for each Make Node child at the instant it's revealed (as its haptic taps fire),
    /// so the parent's docked card can grow an Insight link for it in sync with the animation.
    var onMakeNodeChildRevealed: (UUID) -> Void = { _ in }
    /// Live simulated node positions, reported up for persistence (on disappear / background).
    var onPositionsSettled: ([UUID: CGPoint]) -> Void = { _ in }
    /// Fired to clear any currently hovered/docked insight or node card (e.g. before a
    /// generation zoom-out, so the previously hovered card doesn't linger).
    var onRequestDismissHover: () -> Void = {}
    /// Reports the current blue-dot count whenever Insights or Node Concepts change discovery.
    var onUndiscoveredInsightCountChange: (Int) -> Void = { _ in }
    /// The Node Concept being studied. The canvas camera shifts from the tree's framing into
    /// `studySlot` while the rest of the tree fades; nil shifts it back. The studied node is
    /// the tree's own node, never a copy.
    var studyNodeID: UUID? = nil
    /// An Insight of the studied node to open Study already hovered on.
    var studyInitialHoverInsightID: UUID? = nil
    /// Selected Insights to study together (from the Select tool), instead of a Node Concept:
    /// the camera moves the same way, around their centroid, and only they stay visible.
    var studySelectionIDs: [UUID]? = nil
    /// The Study slot, in this canvas's coordinates.
    var studySlot: CGRect? = nil
    var studyBranchSource: InsightModel? = nil
    var studyBranchNodeID: UUID? = nil
    var studyBranchIsPromoted: Bool = false
    var onStudyBranchFinished: () -> Void = {}


    @Environment(\.scenePhase) var scenePhase

    // State stays owned by this view; feature extensions implement its behavior.
    @State var cameraState = InsightTreeCanvasCameraState()
    @State var revealState = InsightTreeRevealState()
    @State var selectionState = InsightTreeSelectionState()
    @State var rippleTrigger:      RippleTrigger? = nil
    @State var hasAppeared:        Bool = false
    /// Insights the user hasn't opened yet — they show a blue "new" dot until first hovered.
    @State var undiscoveredInsightIDs: Set<UUID> = []
    /// New Node Concepts keep their own discovery state and clear it when first opened.
    @State var undiscoveredNodeIDs: Set<UUID> = []
    @State var pulseCycleStartedAt = Date().timeIntervalSinceReferenceDate
    @State var connectorPulseDelayUntil = Date().timeIntervalSinceReferenceDate
    @State var midpointHandleWorld: CGPoint?
    @State var midpointHandleVisible: Bool = false
    @State var dragStartHandleWorld: CGPoint?
    @State var lastHandleHapticPercent: Int?
    /// Set when the user pans/zooms/taps after placing a midpoint, so the auto camera-hover
    /// stops chasing the generating insight and the user can look around freely.
    @GestureState var dragOffset:  CGSize = .zero


    /// The narrow slice of node state that actually changes graph geometry.
    /// Labels, definitions, embeddings, and refreshed snapshots with identical membership
    /// must not wake the physics simulation.
    struct PhysicsNodeSignature: Equatable {
        let id: UUID
        let visibleInsightIDs: [UUID]
    }

    // MARK: - Live physics simulation
    /// Per-node simulated position + velocity. The canvas briefly relaxes these from the
    /// view model's seed positions after topology changes, then freezes to avoid passive drift.
    @State var bodies: [UUID: SimBody] = [:]
    /// Per-insight free bond angle around its node; VSEPR repulsion spreads chips to maximize
    /// angular separation. Keyed by insight id.
    @State var chipAngles: [UUID: ChipAngle] = [:]
    /// Per-insight elevation angle (radians, within ±45°) above or below the plane. Seeded at
    /// its cluster's spread target (`InsightClusterSpatialLayout.elevationTargets`) in
    /// `reconcileBodies`; the sim eases each toward updated targets as the cluster changes.
    @State var chipElevationAngles: [UUID: CGFloat] = [:]

    // MARK: Node Concept Study
    /// The node being studied; kept through the shift back so it lands in place.
    @State var studyFocusNodeID: UUID?
    /// Studying selected Insights: their centroid on the plane (the Study center), and them.
    @State var studySelectionCenter: CGPoint?
    @State var studySelectionMembers: Set<UUID> = []
    /// 0 = the tree's framing, 1 = the Study framing.
    @State var studyProgress: Double = 0
    /// Each studied Insight's offset from its Node Concept in the tree, and its Study direction
    /// (spread over the whole sphere; the ±45° limit only applies in the tree).
    @State var studyTreeOffsets: [UUID: SIMD3<Double>] = [:]
    @State var studySpread: [UUID: SIMD3<Double>] = [:]
    @State var studyRadius: Double = 190
    @State var completedBranchNodeID: UUID?
    @State var completedBranchPitch: Double = StudyFraming.studyPitch
    @State var studyYaw: Double = 0
    @State var studyPan: CGSize = .zero
    @State var studyZoom: CGFloat = 1
    @State var studyPinchStartZoom: CGFloat?
    @State var studyDragMode: StudyDragMode?
    @State var studyLastDragLocation: CGPoint?
    @State var studyLastDetentYaw: Double = 0
    /// 0 → 1 while a finger is on the ring; eased, so the ring brightens and grows smoothly.
    @State var studyRingActive: Double = 0
    /// A tapped Insight in Study: centered, zoomed in on, and the axis of rotation.
    /// `studyPivotBlend` eases 0 ↔ 1; the id is kept while easing back to the node.
    @State var studyPivotID: UUID?
    @State var studyPivotBlend: Double = 0
    @State var studyPivotLink: DisplayLinkDriver?
    /// When the focus moves from one Insight to another, the camera glides from the previous
    /// one's position (`studyPivotSwitch` 0 → 1).
    @State var studyPivotFrom: SIMD3<Double>?
    @State var studyPivotSwitch: Double = 1
    @State var studyPivotSwitchLink: DisplayLinkDriver?
    /// Set when a focused Insight is released, so the axis returns to the node without the
    /// view moving (see `releaseStudyPivot`).
    @State var studyTargetShift: SIMD3<Double> = .zero
    @State var lastCanvasSize: CGSize = .zero
    /// Ring momentum: yaw keeps turning after release and eases to a stop.
    @State var studySpinLink: DisplayLinkDriver?
    @State var studyRingHalfWidth: CGFloat = 150
    /// A plain touch becomes a pan (and lets go of a focused Insight) only past this distance,
    /// so a tap never releases it.
    static let studyTapSlop: CGFloat = 6
    @State var studyLink: DisplayLinkDriver?
    /// Where the floor ring sits while it glides to a new spot after the canvas resizes (a card
    /// docking or leaving); nil when it's settled at the canvas's own spot.
    @State var studyRingCenterY: CGFloat?
    @State var studyRingLink: DisplayLinkDriver?
    /// Measured label footprints by title. A reference type so filling it never invalidates the
    /// view; the simulation reads every chip's footprint on every frame.
    @State var collisionSizeCache = InsightCollisionSizeCache()
    @State var alpha: Double = 0
    @State var displayLink: DisplayLinkDriver? = nil
    @State var lastTickAt: CFTimeInterval = 0
    @State var simFramesRemaining: Int = 0
    @State var simAlphaDecay: Double = 0.08
    @State var breezeStartedAt: CFTimeInterval?
    @State var breezeDirection = CGVector(dx: 0.92, dy: -0.38)

    // MARK: - Chip rotate-drag
    /// The Insight chip currently being press-and-dragged around its parent Node. While set,
    /// `insightWorldPosition` reports the live drag point instead of the (angle, bond length)
    /// pair, so the chip and its connector line follow the finger anywhere — including stretching
    /// past the chip's normal orbit radius.
    @State var draggingChipID: UUID? = nil
    @State var draggingChipWorldPosition: CGPoint? = nil
    /// Where the dragged chip started, captured once when the drag is promoted. Any placed
    /// Midpoint it's a source of leans toward it by a fraction of `live - start` (see
    /// `stepSimulation`'s pinned-body loop) — the delta, not the raw drag point, is what that
    /// Midpoint follows.
    @State var draggingChipStartWorldPosition: CGPoint? = nil
    /// Insight chip angles the user (or a Midpoint connection) has deliberately pointed somewhere
    /// specific — the ongoing VSEPR angular-spread simulation must never overwrite these, or the
    /// very torque that keeps siblings from overlapping quietly rotates a chosen angle right back
    /// out from under it a few frames later.
    @State var pinnedChipAngleIDs: Set<UUID> = []
    /// Sticky for one `panGesture` lifetime: set as soon as a chip rotate-drag is seen to be in
    /// progress, so `.onEnded` — which fires with the gesture's full raw translation regardless of
    /// what `.onChanged`/`.updating` did — knows not to commit that translation as a canvas pan.
    @State var panGestureBlockedByChipDrag = false
    /// The chip a touch-down is currently pending a long-press timer for (see
    /// `chipRotateDragGesture`). Kept as plain state rather than `LongPressGesture.sequenced` —
    /// composed with the always-simultaneous root pan gesture, the sequenced form dropped its own
    /// `.onEnded` on release often enough in practice to leave `draggingChipID` stuck, freezing
    /// the whole canvas at half opacity. A single `DragGesture` has none of that ambiguity.
    @State var chipPressCandidateID: UUID? = nil
    @State var chipPressStartLocation: CGPoint? = nil
    @State var chipPressLastLocation: CGPoint? = nil

    // Cleanup-pass constants. Global structure comes from the view model's semantic (MDS)
    // layout; the sim only anchors nodes to those targets, separates overlaps, and spreads
    // chip labels — it never invents structure of its own.
    static let anchorSpringK: CGFloat = 0.04    // weak pull toward the MDS target
    static let overlapPadding: CGFloat = 24
    static let simDamping: CGFloat = 0.62       // lower = settles faster, less wobble
    static let simMaxStep: CGFloat = 4          // per-frame move clamp
    static let simMaxDt: CFTimeInterval = 1.0 / 30
    static let alphaDecay: Double = 0.045
    static let updateAlphaDecay: Double = 0.05
    static let updateIntensity: Double = 0.14
    static let breezeDuration: CFTimeInterval = 1.5
    static let breezeForce: CGFloat = 0.9
    static let alphaFloor: Double = 0
    static let jitterAmplitude: CGFloat = 0
    static let settleFrameBudget: Int = 150   // longer: chip bonds rotate into place
    static let settleVelocityThreshold: CGFloat = 0.02
    // Insight collision uses the chip's measured horizontal label footprint, not a fixed circle.
    // Cross-node contact both separates parent nodes and rotates each free Insight bond.
    static let insightCollisionPadding: CGFloat = 24
    static let bubblePushK: CGFloat = 0.08
    static let crossNodeChipTorqueK: Double = 2.4
    static let forceGain: CGFloat = 0.5          // scales summed force → velocity
    // Chip-label angular spread: every bond domain around a Node Concept has equal angular
    // weight, including both Insight bonds and fixed node-to-node lines. Only chip angles move;
    // node positions remain anchored to the semantic MDS targets.
    static let bondDomainK: Double = 1.4
    static let chipAngGain: Double = 0.45        // viscous angular response speed
    static let chipMaxAngStep: Double = 0.07     // max radians a bond rotates per frame
    static let elevationEaseRate: CGFloat = 0.2  // fraction of the way to target per frame
    static let chipAngleEps: Double = 0.12       // softens the 1/Δθ repulsion
    // The uniform VSEPR spread above maximizes angular separation equally across every bond, but
    // has no notion of how WIDE any one chip's label actually is — a long title next to a short
    // one can still settle at an angular gap that's fine on average yet too tight for their real
    // footprints, especially at a small orbit radius (arc length = radius × angle, so the same
    // angular gap is a smaller physical gap closer in). This adds an extra, targeted push whenever
    // two same-node Insight chips' angular gap is below what their combined half-widths need at
    // their shared orbit radius — same-node counterpart to the cross-node bounding-box collision.
    static let chipWidthAngularPadding: CGFloat = 20   // desired gap between chip edges
    static let chipWidthRepulsionK: Double = 2.2
    static let insightCollisionFont =
        UIFont(name: "Figtree-Bold", size: 14) ?? .boldSystemFont(ofSize: 14)
    // 2.5D depth cues from the third MDS component. One switch: false → pure 2D rendering.
    static let depthCuesEnabled = true
    static let depthMinScale: CGFloat = 0.85     // farthest node's scale
    static let depthMinOpacity: Double = 0.75    // farthest node's dimming

    /// One visible Insight's resolved geometry for the current render.
    struct InsightPlacement {
        let insight: InsightModel
        let nodeID: UUID
        let index: Int
        let count: Int
        let isPinnedAtNode: Bool
        /// Footprint on the graph plane (the live drag point while this chip is dragged).
        let world: CGPoint
        /// World units above (+) or below (−) the graph plane; 0 for pinned midpoints.
        let elevation: CGFloat
        /// Normalized local elevation in [-1, 1]; 0 for pinned midpoints.
        let localDepth: CGFloat
    }

    struct CanvasInsightLayout {
        var nodes: [NodeModel]
        var insightsByNode: [UUID: [InsightModel]] = [:]
        var placements: [UUID: InsightPlacement] = [:]
    }

    var activeScale: CGFloat {
        insightTreeCanvasClamp(cameraState.scale, lower: 0.28, upper: 2.6)
    }

    var activeOffset: CGSize {
        CGSize(
            width: cameraState.offset.width + dragOffset.width,
            height: cameraState.offset.height + dragOffset.height
        )
    }

    var physicsTopologySignature: [PhysicsNodeSignature] {
        nodes.map {
            PhysicsNodeSignature(
                id: $0.id,
                visibleInsightIDs: canvasInsights(for: $0).map(\.id)
            )
        }
    }

    var insightTreeCanvasColor: Color {
        AngroveTheme.Colors.canvas
    }

    /// While a selection exists and nothing is hovered, the unselected nodes/insights flash
    /// (mirroring the "Add concept to selection" button) to invite adding another. Hovering stops it.
    var insightsFlashing: Bool {
        !selectedCanvasTargets.isEmpty
            && selectedCanvasTargets.count < CanvasSelectionPolicy.maximumCount
            && !isHoveringTarget
            && !isMidpointMode
    }

    private func itemFlashOpacity(selected: Bool) -> Double {
        guard insightsFlashing, !selected else { return 1 }
        return Double(selectionState.selectionFlashOpacity)
    }

    private var insightTreeInsightColor: Color {
        AngroveTheme.Colors.insightNodeFill
    }

    func focusAnchor(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let studyFraming = makeStudyFraming(in: size)
            let treeCamera = InsightTreeCamera(scale: activeScale, offset: activeOffset)
            let camera = studyCamera(treeCamera, framing: studyFraming, in: size)
            // The ring stays put while the user pans or zooms the node in Study; its dashes turn
            // with the node.
            let studyRingCamera = studyFraming.map { framing in
                framing.camera(from: treeCamera.currentOrbitCamera(in: size), progress: studyProgress)
            }
            let studyRing = studyFraming.flatMap { framing in
                studyRingCamera.map { framing.ringPoints(camera: $0) }
            } ?? []
            let studyRingDashes = studyFraming.flatMap { framing in
                studyRingCamera.map { framing.ringDashes(camera: $0, yaw: studyYaw * studyProgress) }
            } ?? []
            let restFade = isInStudy ? 1 - studyProgress : 1
            let studyReady = isStudyRequested && isInStudy && studyProgress > 0.99 && studyBranchSource == nil
            let labelOpacity = Self.labelOpacity(for: activeScale)
            let nodeLabelOpacity = Self.nodeLabelOpacity(for: activeScale)
            let layout = makeInsightLayout()
            let studyChipTargets = studyReady ? studyTapTargets(layout: layout, camera: camera, size: size) : []
            let studyNodeTarget = studyReady ? studyNodeTapTarget(camera: camera, size: size) : nil

            let canvas = ZStack {
                if showsBackground {
                    CanvasBackground(option: insightTreeBackground).ignoresSafeArea()
                }
                AnimatedDotGridBackground(
                    settledOffset: cameraState.offset,
                    settledScale:  activeScale,
                    dragOffset:    dragOffset,
                    ripples:       (rippleTrigger.map { [$0] } ?? []) + selectionState.selectionRipples
                )
                // Keep the grid's Canvas in the exact same coordinate frame as the graph.
                // Expanding it independently into the safe area shifts ripple origins away
                // from the focused chip even though both use the same camera transform.
                .frame(width: size.width, height: size.height)
                .opacity(hasAppeared && studyBranchSource == nil ? restFade : 0)
                .animation(.easeOut(duration: 0.6), value: hasAppeared)

                // In Study the grid tips up into a floor under the ring, moving with the node.
                if let studyFraming, let studyOrbit = camera.orbit {
                    StudyFloorGrid(framing: studyFraming, camera: studyOrbit)
                        .frame(width: size.width, height: size.height)
                        .opacity(studyBranchSource == nil ? studyProgress : 0)
                }

                ZStack {
                    if isInStudy {
                        StudyFloorRing(points: studyRing, dashes: studyRingDashes, activeAmount: studyRingActive)
                            .frame(width: size.width, height: size.height)
                            .opacity(studyProgress)
                    }
                    // Each connector is a gradient-stroked, full-canvas shape. Rendering them as
                    // one flattened layer keeps a large global tree from compositing hundreds of
                    // separate layers on every pan and zoom frame.
                    ZStack {
                        graphEdges(camera: camera, size: size)
                        midpointConnectors(layout: layout, camera: camera, size: size)
                            .opacity(restFade)
                        insightConnectors(layout: layout, camera: camera, size: size)
                    }
                    .frame(width: size.width, height: size.height)
                    .drawingGroup()
                    // Hover pulses stay in Study: they only ever run along the hovered item's
                    // connectors, which in Study belong to the studied cluster.
                    connectorPulseOverlay(layout: layout, camera: camera, size: size)
                    // Fades with the rest of the tree, except a studied selection's own lines.
                    selectionOverlay(layout: layout, camera: camera, size: size, restFade: restFade)
                    edgeHitTargets(camera: camera, size: size)
                        .opacity(restFade)

                    ForEach(layout.nodes) { node in
                        let visibleInsights = layout.insightsByNode[node.id] ?? []
                        // Placed-midpoint nodes render as just their insight chip — no concept circle.
                        if !placedMidpointNodeIDs.contains(node.id),
                           revealState.revealedNodeIDs.contains(node.id) {
                            nodeGroup(node, camera: camera, size: size, labelOpacity: nodeLabelOpacity)
                                .opacity(itemFlashOpacity(selected: selectedCanvasTargets.contains(.node(node.id))))
                                .opacity(studyOpacity(forNodeID: node.id))
                        }

                        ForEach(visibleInsights) { insight in
                            if let placement = layout.placements[insight.id] {
                                insightLabel(
                                    placement,
                                    node: node,
                                    camera: camera,
                                    size: size,
                                    labelOpacity: labelOpacity
                                )
                                .opacity(itemFlashOpacity(selected: selectedCanvasTargets.contains(.insight(insight.id))))
                            }
                        }
                    }
                }
                .opacity(isMidpointMode || studyBranchSource != nil ? 0 : 1)
                .animation(.easeInOut(duration: 0.3), value: studyBranchSource?.id)
                // In Study only the Study gestures below respond.
                .allowsHitTesting(!isMidpointMode && !isInStudy)
                .animation(.easeInOut(duration: 0.3), value: isMidpointMode)

                if let source = studyBranchSource {
                    let children = nodes.first(where: { $0.id == studyBranchNodeID })?.insights ?? []
                    let ready = studyBranchIsPromoted && !children.isEmpty
                        && Set(children.map(\.id)).isSubset(of: generatedMakeNodeChildIDs)
                    StudyBranchScene(
                        sourceTitle: source.title,
                        initialPosition: layout.placements[source.id].map {
                            insightProjection($0, camera: camera, size: size).position
                        } ?? CGPoint(x: size.width / 2, y: size.height / 2),
                        isPromoted: studyBranchIsPromoted,
                        children: children,
                        isReady: ready,
                        childOffsets: Dictionary(uniqueKeysWithValues: children.enumerated().map { index, child in
                            let angle = chipAngles[child.id]?.angle ?? baseChipAngle(index: index, count: children.count)
                            let radius = bondLength(forInsightID: child.id)
                            return (child.id, CGPoint(x: cos(angle) * radius, y: sin(angle) * radius))
                        }),
                        onFinished: {
                            revealState.completeBranch(childIDs: Set(children.map(\.id)),
                                nodeIDs: Set(nodes.map(\.id)), graphEdgeIDs: Set(displayGraphEdges().map(\.id)))
                            completedBranchNodeID = studyBranchNodeID
                            onStudyBranchFinished()
                        },
                        onInsightTapped: { insight in
                            markDiscovered(insight.id)
                            onInsightTapped(insight)
                        }
                    )
                    .id(source.id)
                    .transition(.opacity)
                }

                if isMidpointMode {
                    midpointOverlay(layout: layout, camera: camera, size: size, labelOpacity: labelOpacity)
                }
            }
            .environment(\.insightTreeClearsLabelChrome, insightTreeBackground == .clouds)
            .contentShape(Rectangle())
            .coordinateSpace(name: Self.canvasSpace)
            .simultaneousGesture(panGesture(camera: camera, size: size), including: isInStudy ? .none : .all)
            // Always available for precision zooming, except in Study, which has its own pinch.
            .simultaneousGesture(zoomGesture(in: size), including: isInStudy ? .none : .all)
            .simultaneousGesture(studyDragGesture(ring: studyRing, chips: studyChipTargets, nodeFrame: studyNodeTarget, size: size), including: studyReady ? .all : .none)
            .onChange(of: size, initial: true) { oldSize, newSize in
                lastCanvasSize = newSize
                glideStudyRing(from: oldSize, to: newSize)
            }
            .simultaneousGesture(studyPinchGesture, including: studyReady ? .all : .none)
            .onTapGesture {
                guard !isInStudy else { return }
                selectionState.selectedEdgeID = nil
                cameraState.userMovedSincePlacement = true
            }
            .onChange(of: studyNodeID) { _, nodeID in
                if let nodeID {
                    beginStudy(of: nodeID)
                } else {
                    endStudy()
                }
            }
            .onChange(of: studySelectionIDs) { _, insightIDs in
                if let insightIDs {
                    beginStudy(ofSelection: insightIDs)
                } else {
                    endStudy()
                }
            }
            .onChange(of: restoreFocusedCameraRequest) { oldValue, newValue in
                restorePreFocusCamera()
            }
            .onChange(of: focusedInsightID) { oldValue, newValue in
                guard let newValue,
                      let focusTarget = insightFocusTarget(for: newValue) else { return }

                focusHoveredTarget(
                    at: focusTarget,
                    elevation: insightElevation(forInsightID: newValue),
                    in: size
                )
            }
            .onChange(of: pulsingInsightID, initial: true) { _, insightID in
                // Cards opened from search, a Node card, or Study are discoveries too.
                if let insightID { markDiscovered(insightID) }
            }
            .onChange(of: focusedSearchNodeID) { _, newValue in
                guard let newValue,
                      let focusTarget = simPosition(of: newValue) else { return }

                focusHoveredTarget(at: focusTarget, in: size)
            }
            canvasRequestObservers(canvasLifecycleObservers(canvas, size: size), size: size)
        }
        .canvasAppearance(insightTreeBackground)
    }
}
