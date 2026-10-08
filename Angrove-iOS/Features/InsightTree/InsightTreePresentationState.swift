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
    /// Membership baselines for persisted topology mutations.
    var confirmedPersistedInsightIDs: Set<UUID> = []
    var confirmedPersistedNodeIDs: Set<UUID> = []
    var loadingInsightIDs: Set<UUID> = []
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
