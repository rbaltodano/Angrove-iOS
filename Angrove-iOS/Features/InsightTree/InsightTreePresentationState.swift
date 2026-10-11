import SwiftUI
import Observation

/// Reveal bookkeeping is separate from camera, physics, selection, and discovery state.
/// Geometry-dependent animation sequences stay with the canvas; their values and tasks have
/// one owner for the lifetime of that canvas.
@MainActor
@Observable
final class InsightTreeRevealState {
    var revealedInsightIDs: Set<UUID> = []
    /// Connectors appear after their chips finish entering.
    var revealedInsightConnectorIDs: Set<UUID> = []
    var growingConnectorIDs: Set<UUID> = []
    var revealedGraphEdgeIDs: Set<String> = []
    var animatedGraphEdgeIDs: Set<String> = []
    var revealedNodeIDs: Set<UUID> = []
    /// Membership baselines are independent of reveal state, so content updates cannot replay
    /// an entrance while a newly inserted Insight is still hidden.
    var observedLiveInsightIDs: Set<UUID> = []
    var observedLiveNodeIDs: Set<UUID> = []
    @ObservationIgnored var entranceTask: Task<Void, Never>? = nil
    /// Identifies the reveal tour that currently owns the hidden/revealed sets.
    @ObservationIgnored var activeSequence: UUID?
    @ObservationIgnored var midpointRevealTask: Task<Void, Never>? = nil
    var midpointLoadingStartedAt: [UUID: TimeInterval] = [:]
    @ObservationIgnored var makeNodeRevealTask: Task<Void, Never>? = nil
    var makeNodeLoadingStartedAt: TimeInterval?
    var pendingMakeNodeChildren: [PendingMakeNodeChild] = []
    /// The pending children came from Study's Branch, which never tours the camera, even if
    /// the person leaves Study before they finish loading.
    var pendingMakeNodeIsBranch = false
    /// Membership baselines for persisted topology mutations.
    var confirmedPersistedInsightIDs: Set<UUID> = []
    var confirmedPersistedNodeIDs: Set<UUID> = []
    var loadingInsightIDs: Set<UUID> = []
    var transferProgress: CGFloat = 1
    var transfers: [UUID: MidpointTransfer] = [:]
    var previousBondLengths: [UUID: CGFloat] = [:]
    @ObservationIgnored var transferTask: Task<Void, Never>?
    struct MidpointTransfer {
        let oldParent: CGPoint
        let world: CGPoint
        let elevation: CGFloat
    }
    var loadingFlashOpacity: CGFloat = 1
    var unsplayedInsightIDs: Set<UUID> = []

    struct PendingMakeNodeChild: Equatable {
        let id: UUID
        let orbitIndex: Int
    }

    /// Branch has its own entrance. Hand its finished topology back to the ordinary renderer
    /// with both kinds of connectors visible, without scheduling a second reveal tour.
    func completeBranch(childIDs: Set<UUID>, nodeIDs: Set<UUID>, graphEdgeIDs: Set<String>) {
        revealedInsightIDs.formUnion(childIDs)
        revealedInsightConnectorIDs.formUnion(childIDs)
        revealedNodeIDs.formUnion(nodeIDs)
        revealedGraphEdgeIDs.formUnion(graphEdgeIDs)
    }

    func cancelPendingAnimations() {
        transferTask?.cancel()
        transfers = [:]
        entranceTask?.cancel()
        midpointRevealTask?.cancel()
        makeNodeRevealTask?.cancel()
    }

    func beginConnectorGrowth(_ insightIDs: Set<UUID>) -> Set<UUID> {
        let fresh = insightIDs.subtracting(revealedInsightConnectorIDs)
        growingConnectorIDs.formUnion(fresh)
        revealedInsightConnectorIDs.formUnion(insightIDs)
        return fresh
    }
}

/// Transient selection effects, independent of reveal and topology changes.
@MainActor
@Observable
final class InsightTreeSelectionState {
    var selectedEdgeID: UUID?
    var selectionRipples: [RippleTrigger] = []
    var selectionPulseStartTime: TimeInterval?
    var selectionFlashOpacity: CGFloat = 1
}

/// One clock keeps the new connector attached before releasing the old parent or moving a chip.
nonisolated struct MidpointTransferPresentation {
    static let connectorDuration: TimeInterval = 0.63
    static let fadeDuration: TimeInterval = 0.36
    static let pullStart = connectorDuration + fadeDuration
    static let duration = pullStart + Spring.relaxed.settlingDuration

    let connectorGrowth: CGFloat
    let oldConnectorOpacity: CGFloat
    let pullProgress: CGFloat

    init(progress: CGFloat) {
        let elapsed = Double(min(max(progress, 0), 1)) * Self.duration
        connectorGrowth = Self.ease(CGFloat(elapsed / Self.connectorDuration))
        oldConnectorOpacity = 1 - Self.ease(CGFloat((elapsed - Self.connectorDuration) / Self.fadeDuration))
        let pullElapsed = elapsed - Self.pullStart
        if pullElapsed <= 0 {
            pullProgress = 0
        } else if progress >= 1 {
            pullProgress = 1
        } else {
            // Keep the drag-release spring's overshoot instead of clamping it to the orbit.
            pullProgress = CGFloat(Spring.relaxed.value(target: 1.0, time: pullElapsed))
        }
    }

    private static func ease(_ value: CGFloat) -> CGFloat {
        let t = min(max(value, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
