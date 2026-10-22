import SwiftUI

/// The iPhone presenter owns cards, menus, selection, search, Study, Midpoint and Branch.
/// Mac only supplies the surrounding split workspace and native input adapter.
struct MacInsightTreePane: View {
    let session: MacConversationState
    let controls: MacTreeControls
    let runtime: MacApplicationRuntime
    let isVisible: Bool
    var isGlobal = false
    var acceptedGlobalUpdateIDs: Set<UUID> = []
    var originPage: ModelTaskOriginPage? = nil
    var cardsAtFrameBottom = false
    /// An Insight to open on the canvas, such as one chosen from global search.
    var focusInsightID: UUID? = nil
    var onActivity: () -> Void = {}
    @State private var hasMounted = false
    @AppStorage(SettingsStorageKey.insightTreeBackground) private var background: CanvasBackgroundOption = .system

    var body: some View {
        ZStack {
            CanvasBackground(option: background)
            if hasMounted {
                InsightTreeView(
                    insights: session.concepts, conversationID: isGlobal ? nil : session.id, acceptedGlobalUpdateIDs: acceptedGlobalUpdateIDs, persistsDiscoveryState: !session.isPreview,
                    selectionRequest: controls.selectionRequest,
                    clearSelectionRequest: controls.clearSelectionRequest,
                    dismissHoverRequest: controls.dismissHoverRequest,
                    createConceptRequest: controls.createConceptRequest,
                    studyRequest: controls.studyRequest, studyExitRequest: controls.studyExitRequest,
                    studyToolsToggleRequest: controls.studyToolsRequest,
                    studyBranchCount: controls.studyBranchCount,
                    studyBranchConfirmRequest: controls.studyBranchConfirmRequest,
                    onStudyModeChange: { controls.isStudy = $0 },
                    onStudyToolsActiveChange: { controls.studyToolsOpen = $0 },
                    onStudyBranchCountChange: { controls.studyBranchCount = $0 },
                    restoreSelectedInsightID: focusInsightID,
                    promotedInsightIDs: session.promotedIDs,
                    onRemoveInsight: session.remove, onRestoreInsight: session.restore,
                    onForkInsight: session.fork,
                    onQuoteInsight: { controls.hoveredConcept = $0 },
                    onSelectionStateChange: { controls.hasHover = $0 },
                    onInsightSelectionStateChange: { controls.hasInsightHover = $0 },
                    onSelectedCanvasItemCountChange: { if $0 > 0 { onActivity() }; controls.selectedCount = $0 },
                    onPromotedInsightIDsChange: { session.promotedIDs = $0; if isGlobal && !session.isPreview { GlobalInsightPromotedIDsStore.save($0) } },
                    savedConceptIDs: session.savedIDs,
                    onToggleSavedConcept: session.toggleBookmark, onBookmarkConcepts: session.bookmark,
                    inquireConnectionRequest: controls.inquireConnectionRequest,
                    onInquireConnectionConcepts: { session.connectionConcepts = $0 },
                    midpointEnterRequest: controls.midpointEnterRequest,
                    midpointCenterRequest: controls.midpointCenterRequest,
                    midpointPlaceRequest: controls.midpointPlaceRequest,
                    searchQuery: controls.searchQuery,
                    searchPreviousRequest: controls.searchPreviousRequest,
                    searchNextRequest: controls.searchNextRequest,
                    onSearchResultsChange: { controls.searchIndex = $0; controls.searchCount = $1 },
                    onMidpointModeChange: { controls.isMidpoint = $0 },
                    onMidpointGeneratingChange: { controls.isGenerating = $0 },
                    showQuestionBar: false,
                    modelTasks: runtime.modelTasks, modelTaskOriginPage: originPage ?? (isGlobal ? .insights : .conversation),
                    model: runtime.model, embeddingProvider: runtime.embeddingProvider
                )
            }
        }
        .canvasAppearance(background)
        .frame(minWidth: MacInsightPaneLayout.minimumContentWidth, alignment: .leading)
        .overlayPreferenceValue(ModelControlsPreferenceKey.self, alignment: .bottom) { configuration in
            if cardsAtFrameBottom && isVisible, let card = configuration?.dockedCard {
                card.view
                    .padding(24)
                    .animation(.springStandard, value: card.key)
            }
        }
        .transformPreference(ModelControlsPreferenceKey.self) {
            if !isVisible { $0 = nil }
            else if cardsAtFrameBottom { $0?.dockedCard = nil }
        }
        .onChange(of: isVisible, initial: true) { _, visible in
            if visible { hasMounted = true }
        }
    }
}
