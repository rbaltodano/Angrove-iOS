//
//  InsightTreeView.swift
//  Angrove-iOS
//

import SwiftUI
import UIKit

// MARK: - Insight Tree View

private let insightTreeCanvasColor = AngroveTheme.Colors.canvas
let insightTreeInsightColor = AngroveTheme.Colors.canvasSecondary

struct InsightTreeView: View {
    @AppStorage(SettingsStorageKey.insightTreeBackground) private var insightTreeBackground: CanvasBackgroundOption = .system
    let insights: [ConceptDefinition]
    let conversationID: UUID?
    var selectionRequest: Int = 0
    var persistedTreeRefreshRequest: Int = 0
    var clearSelectionRequest: Int = 0
    var dismissHoverRequest: Int = 0
    var createConceptRequest: Int = 0
    /// Monotonically increasing request from the shared canvas controls to study the hovered Insight.
    var studyRequest: Int = 0
    var studyExitRequest: Int = 0
    /// Toggles Study's tool card (the dock's Tools button).
    var studyToolsToggleRequest: Int = 0
    var studyBranchCount: Int = 2
    var studyBranchConfirmRequest: Int = 0
    var onStudyModeChange: ((Bool) -> Void)? = nil
    /// Whether Study's tools are open, so the dock can color its Tools button.
    var onStudyToolsActiveChange: ((Bool) -> Void)? = nil
    var onStudyBranchCountChange: ((Int) -> Void)? = nil
    var restoreSelectedInsightID: UUID? = nil
    var restoreSelectedNodeID: UUID? = nil
    var nodeSelectionRequest: Int = 0
    var promotedInsightIDs: [UUID] = []
    var onClose: (() -> Void)?
    var onRemoveInsight:  ((ConceptDefinition) -> Void)? = nil
    var onRestoreInsight: ((ConceptDefinition) -> Void)? = nil
    var onForkInsight:    ((ConceptDefinition) -> Void)? = nil
    var onQuoteInsight:   ((ConceptDefinition?) -> Void)? = nil
    var onSelectionStateChange: ((Bool) -> Void)? = nil
    var onInsightSelectionStateChange: ((Bool) -> Void)? = nil
    var onSelectedCanvasItemCountChange: ((Int) -> Void)? = nil
    var onPromotedInsightIDsChange: (([UUID]) -> Void)? = nil
    var savedConceptIDs: Set<UUID> = []
    var onToggleSavedConcept: ((ConceptDefinition) -> Void)? = nil
    var onBookmarkConcepts: (([ConceptDefinition]) -> Void)? = nil
    var inquireConnectionRequest: Int = 0
    var onInquireConnectionConcepts: (([ConceptDefinition]) -> Void)? = nil
    var midpointEnterRequest: Int = 0
    var midpointCenterRequest: Int = 0
    var midpointPlaceRequest: Int = 0
    var searchQuery: String = ""
    var searchPreviousRequest: Int = 0
    var searchNextRequest: Int = 0
    var onSearchResultsChange: ((_ current: Int, _ total: Int) -> Void)? = nil
    var highlightedInsightPair: (UUID, UUID)? = nil
    var highlightPairRequest: Int = 0
    var startsMidpointForHighlightedPair: Bool = false
    var onMidpointModeChange: ((Bool) -> Void)? = nil
    /// Reports whether a just-placed midpoint insight is currently "generating".
    var onMidpointGeneratingChange: ((Bool) -> Void)? = nil
    var onUndiscoveredInsightCountChange: ((Int) -> Void)? = nil
    /// Fires after a mutation-triggered persisted snapshot is fully reconciled and applied.
    var onPersistedTreeRefreshCompleted: (() -> Void)? = nil
    var inputFont: ConversationFontOption = .serif
    var conversationFontSize: ConversationFontSizeOption = .medium
    var showQuestionBar: Bool = true
    let modelTasks: ModelTaskQueue?
    let modelTaskOriginPage: ModelTaskOriginPage
    let model: AngroveModel
    let embeddingProvider: EmbeddingProvider

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// The shell overlays Model Controls outside this view, so its inset is not always inherited.

    /// On a landscape phone the tree becomes a true left-hand workspace. The detail dock and
    /// shared model controls use the matching right-hand pane instead of floating over the map.
    private var usesLandscapeSplitLayout: Bool {
        verticalSizeClass == .compact
    }

    @StateObject private var viewModel: InsightTreeViewModel
    @State private var selectedInsight: InsightModel?
    @State private var selectedNode: NodeModel?
    @State private var hoveredConcept: ConceptDefinition?
    /// Insight id of a just-placed midpoint while it "loads" on the canvas.
    @State private var midpointPlacedInsightID: UUID?
    /// Matches the placed id only after its generated content has replaced the loading
    /// placeholder. The canvas waits for this signal before revealing the title and card.
    @State private var midpointGeneratedInsightID: UUID?
    @State private var midpointGenerationTask: Task<Void, Never>?
    /// True only for the card that pops after a midpoint placement, so its body text
    /// animates in like a streamed model response.
    @State private var animateMidpointCardText: Bool = false
    @State private var dockedCardDragY: CGFloat = 0
    /// Top edge of the docked cards in global coordinates. They render in the shell's Model
    /// Controls stack, outside this view, so the canvas can't learn their height from layout.
    @State private var dockedCardTopInGlobal: CGFloat?
    /// While Make Node generates children from a docked insight, its card stays up and grows an
    /// Insight link per child. `makeNodeParentInsightID` is the insight whose card is growing;
    /// `makeNodeLinkInsightIDs` are the child ids revealed so far (each appended on its haptic).
    @State private var makeNodeParentInsightID: UUID?
    @State private var makeNodeLinkInsightIDs: [UUID] = []
    /// True from the Make Node tap until generation finishes, so the generation zoom-out doesn't
    /// dismiss the parent card we're growing.
    @State private var makeNodeGenerating: Bool = false
    @State private var restoreFocusedCameraRequest: Int = 0
    @State private var focusedInsightID: UUID?
    @State private var focusedNodeID: UUID?
    @State private var undoInsight: ConceptDefinition? = nil
    @State private var undoTask: Task<Void, Never>? = nil
    @State private var pendingRemoveInsight: InsightModel? = nil
    @State private var pendingUnbookmarkMakeNode: NodeModel? = nil
    @State private var questionBarContextInsight: InsightModel? = nil
    @State private var questionBarKeyboardActive: Bool = false
    @State private var cardShouldHide: Bool = false
    @State private var chipShouldShow: Bool = false
    @State private var questionBarFocusTrigger: Int = 0
    @State private var selectedCanvasTargets: [CanvasSelectionTarget] = []
    @State private var selectionPulseRequest: Int = 0
    @State private var isMidpointMode: Bool = false
    @State private var midpointWeights: [Double] = []
    @State private var midpointTargetIndex: Int = 0
    @State private var midpointTargetWeight: Double = 0.5
    @State private var midpointPercentRequest: Int = 0
    @State private var searchResults: [CanvasSelectionTarget] = []
    @State private var searchResultIndex: Int = 0
    /// Advances each time the on-device tree snapshot has been applied.
    /// The canvas uses this—not its own appearance—to decide when a persisted update may animate.
    @State private var persistedTreePresentationRevision: Int = 0
    /// Equals `persistedTreePresentationRevision` only for refreshes caused by a completed
    /// mutation. Initial loads establish a baseline without touring the camera.
    @State private var animatedPersistedTreePresentationRevision: Int = 0
    /// Prevents a slower initial fetch from overwriting a newer mutation-triggered refresh.
    @State private var persistedTreeLoadGeneration: Int = 0
    @State private var isModelActionErrorPresented: Bool = false
    @State private var pendingModelActionRetry: (() -> Void)? = nil
    /// The selected Insight stays selected beneath this overlay, so Exit can restore the exact
    /// hover state the user entered from.
    @State private var studySubject: StudySubject?
    @State private var isExitingStudy: Bool = false
    /// The canvas's origin in `InsightTreeStackSpace`, to hand it the Study slot in its own
    /// coordinates.
    @State private var canvasOriginInStack: CGPoint = .zero
    /// The Node Concept Study slot in `InsightTreeStackSpace`, laid out by `StudyModeView`.
    @State private var studySlotInStack: CGRect?
    /// Study's tools are open: the tool card replaces the hover card and previews run. Opened
    /// and closed by the dock's Tools button or by swiping the card down; moving around the
    /// node doesn't close it.
    @State private var showsStudyToolCard = false
    @State private var studyToolCardDragY: CGFloat = 0
    @State private var studyBranchSource: InsightModel?
    @State private var studyBranchIsPromoted = false
    @State private var studyBranchBusy = false
    @State private var studyBranchSessionID = UUID()
    @State private var studyBranchTask: Task<Void, Never>?

    /// Branch is the only launch tool; ignore any previously saved prototype selection.
    private let studyTool: StudyTool = .branch
    /// Kept separate from `studySubject` so the hovered card is reinserted with its normal
    /// dock transition after Study clears, rather than merely becoming visible underneath it.
    @State private var showsDockedCardAfterStudy: Bool = true

    init(
        insights: [ConceptDefinition],
        conversationID: UUID? = nil,
        selectionRequest: Int = 0,
        persistedTreeRefreshRequest: Int = 0,
        clearSelectionRequest: Int = 0,
        dismissHoverRequest: Int = 0,
        createConceptRequest: Int = 0,
        studyRequest: Int = 0,
        studyExitRequest: Int = 0,
        studyToolsToggleRequest: Int = 0,
        studyBranchCount: Int = 2,
        studyBranchConfirmRequest: Int = 0,
        onStudyModeChange: ((Bool) -> Void)? = nil,
        onStudyToolsActiveChange: ((Bool) -> Void)? = nil,
        onStudyBranchCountChange: ((Int) -> Void)? = nil,
        restoreSelectedInsightID: UUID? = nil,
        restoreSelectedNodeID: UUID? = nil,
        nodeSelectionRequest: Int = 0,
        promotedInsightIDs: [UUID] = [],
        onClose: (() -> Void)? = nil,
        onRemoveInsight:  ((ConceptDefinition) -> Void)? = nil,
        onRestoreInsight: ((ConceptDefinition) -> Void)? = nil,
        onForkInsight:    ((ConceptDefinition) -> Void)? = nil,
        onQuoteInsight:   ((ConceptDefinition?) -> Void)? = nil,
        onSelectionStateChange: ((Bool) -> Void)? = nil,
        onInsightSelectionStateChange: ((Bool) -> Void)? = nil,
        onSelectedCanvasItemCountChange: ((Int) -> Void)? = nil,
        onPromotedInsightIDsChange: (([UUID]) -> Void)? = nil,
        savedConceptIDs: Set<UUID> = [],
        onToggleSavedConcept: ((ConceptDefinition) -> Void)? = nil,
        onBookmarkConcepts: (([ConceptDefinition]) -> Void)? = nil,
        inquireConnectionRequest: Int = 0,
        onInquireConnectionConcepts: (([ConceptDefinition]) -> Void)? = nil,
        midpointEnterRequest: Int = 0,
        midpointCenterRequest: Int = 0,
        midpointPlaceRequest: Int = 0,
        searchQuery: String = "",
        searchPreviousRequest: Int = 0,
        searchNextRequest: Int = 0,
        onSearchResultsChange: ((_ current: Int, _ total: Int) -> Void)? = nil,
        highlightedInsightPair: (UUID, UUID)? = nil,
        highlightPairRequest: Int = 0,
        startsMidpointForHighlightedPair: Bool = false,
        onMidpointModeChange: ((Bool) -> Void)? = nil,
        onMidpointGeneratingChange: ((Bool) -> Void)? = nil,
        onUndiscoveredInsightCountChange: ((Int) -> Void)? = nil,
        onPersistedTreeRefreshCompleted: (() -> Void)? = nil,
        inputFont: ConversationFontOption = .serif,
        conversationFontSize: ConversationFontSizeOption = .medium,
        showQuestionBar: Bool = true,
        modelTasks: ModelTaskQueue? = nil,
        modelTaskOriginPage: ModelTaskOriginPage = .insights,
        model: AngroveModel = MockAngroveModel(),
        embeddingProvider: EmbeddingProvider = NLEmbeddingProvider()
    ) {
        self.insights              = insights
        self.conversationID        = conversationID
        self.model                 = model
        self.embeddingProvider     = embeddingProvider
        self.selectionRequest      = selectionRequest
        self.persistedTreeRefreshRequest = persistedTreeRefreshRequest
        self.clearSelectionRequest = clearSelectionRequest
        self.dismissHoverRequest   = dismissHoverRequest
        self.createConceptRequest  = createConceptRequest
        self.studyRequest          = studyRequest
        self.studyExitRequest      = studyExitRequest
        self.studyToolsToggleRequest = studyToolsToggleRequest
        self.onStudyToolsActiveChange = onStudyToolsActiveChange
        self.studyBranchCount      = studyBranchCount
        self.studyBranchConfirmRequest = studyBranchConfirmRequest
        self.onStudyModeChange     = onStudyModeChange
        self.onStudyBranchCountChange = onStudyBranchCountChange
        self.restoreSelectedInsightID = restoreSelectedInsightID
        self.restoreSelectedNodeID = restoreSelectedNodeID
        self.nodeSelectionRequest  = nodeSelectionRequest
        self.promotedInsightIDs    = promotedInsightIDs
        self.onClose               = onClose
        self.onRemoveInsight       = onRemoveInsight
        self.onRestoreInsight      = onRestoreInsight
        self.onForkInsight         = onForkInsight
        self.onQuoteInsight        = onQuoteInsight
        self.onSelectionStateChange = onSelectionStateChange
        self.onInsightSelectionStateChange = onInsightSelectionStateChange
        self.onSelectedCanvasItemCountChange = onSelectedCanvasItemCountChange
        self.onPromotedInsightIDsChange    = onPromotedInsightIDsChange
        self.savedConceptIDs               = savedConceptIDs
        self.onToggleSavedConcept          = onToggleSavedConcept
        self.onBookmarkConcepts            = onBookmarkConcepts
        self.inquireConnectionRequest      = inquireConnectionRequest
        self.onInquireConnectionConcepts   = onInquireConnectionConcepts
        self.midpointEnterRequest          = midpointEnterRequest
        self.midpointCenterRequest         = midpointCenterRequest
        self.midpointPlaceRequest          = midpointPlaceRequest
        self.searchQuery                   = searchQuery
        self.searchPreviousRequest         = searchPreviousRequest
        self.searchNextRequest             = searchNextRequest
        self.onSearchResultsChange         = onSearchResultsChange
        self.highlightedInsightPair        = highlightedInsightPair
        self.highlightPairRequest          = highlightPairRequest
        self.startsMidpointForHighlightedPair = startsMidpointForHighlightedPair
        self.onMidpointModeChange          = onMidpointModeChange
        self.onMidpointGeneratingChange    = onMidpointGeneratingChange
        self.onUndiscoveredInsightCountChange = onUndiscoveredInsightCountChange
        self.onPersistedTreeRefreshCompleted = onPersistedTreeRefreshCompleted
        self.inputFont             = inputFont
        self.conversationFontSize  = conversationFontSize
        self.showQuestionBar       = showQuestionBar
        self.modelTasks            = modelTasks
        self.modelTaskOriginPage   = modelTaskOriginPage
        // A synchronous UserDefaults read, not something that needs to wait for the async
        // `.task`-driven load — passing it in at construction avoids a guaranteed blank-then-
        // populated flash on every tree open (the view model otherwise builds its first tree
        // with zero anchors, then rebuilds moments later once `setLocalSeedAnchors` runs).
        let initialLocalSeedAnchors = conversationID.map(LocalInsightTreeSeedStore.seeds(for:)) ?? []
        _viewModel = StateObject(wrappedValue: InsightTreeViewModel(
            insights: insights,
            promotedInsightIDs: promotedInsightIDs,
            showsAllClusterInsights: conversationID == nil,
            model: model,
            modelTasks: modelTasks,
            modelTaskOriginPage: modelTaskOriginPage,
            embeddingProvider: embeddingProvider,
            localSeedAnchors: initialLocalSeedAnchors,
            midpointStoreScope: conversationID
        ))
    }

    private var canvasTertiary: Color {
        AngroveTheme.Colors.deepSurface
    }

    @ViewBuilder
    private var undoButtonView: some View {
        Button {
            guard let concept = undoInsight else { return }
            undoTask?.cancel()
            onRestoreInsight?(concept)
            withAnimation(.springQuick) {
                undoInsight = nil
            }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Text("Undo")
                    .font(.custom("Figtree-Bold", size: 16))
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(AngroveTheme.Colors.onAccent)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(canvasTertiary)
            .cornerRadius(12)
            .shadow(color: canvasTertiary.opacity(0.2), radius: 8, x: 0, y: 8)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .inset(by: 0.5)
                    .stroke(canvasTertiary.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }


    /// Cards docked above the shell's Model Controls pill. Published into the shared controls
    /// stack (not laid out here) so they always stack directly above the pill with the stack's
    /// own spacing, instead of guessing the pill's height from a separate layout.
    @ViewBuilder private var dockedStackContent: some View {
        VStack(spacing: 8) {
            if undoInsight != nil {
                undoButtonView
                    .transition(.scale(scale: 0.88).combined(with: .opacity))
                    .opacity(studySubject == nil ? 1 : 0)
            }

            if showsStudyToolCard {
                StudyToolCard()
                .offset(y: studyToolCardDragY)
                .simultaneousGesture(studyToolCardDismissGesture)
                .transition(.bottomDockCard)
                .padding(.horizontal, 10)
            } else if isMidpointMode {
                MidpointPercentCard(
                    concepts: selectedCanvasTargets.compactMap { concept(for: $0) },
                    weights: midpointWeights,
                    onSetPercent: { index, percent in
                        midpointTargetIndex = index
                        midpointTargetWeight = Double(percent) / 100.0
                        midpointPercentRequest += 1
                    }
                )
                .transition(.scale(scale: 0.35, anchor: .bottom).combined(with: .opacity))
                .padding(.horizontal, 10)
            } else if !cardShouldHide {
                if !showQuestionBar, showsDockedCardAfterStudy, let concept = hoveredConcept {
                    DockedConceptCard(
                        concept: concept,
                        isSaved: savedConceptIDs.contains(concept.id),
                        onToggleSaved: { onToggleSavedConcept?(concept) },
                        onFork: {
                            dismissDockedInsight()
                            onForkInsight?(concept)
                        }
                    )
                    .id(concept.id)
                    .growsWhileTouched()
                    .offset(y: dockedCardDragY)
                    .gesture(dockedCardDismissGesture)
                    .transition(.bottomDockCard)
                    .padding(.horizontal, 10)
                } else if showsDockedCardAfterStudy, let selectedInsight {
                    DockedInsightTreeCard(
                        insight: selectedInsight,
                        isSaved: savedConceptIDs.contains(selectedInsight.id),
                        animateIn: animateMidpointCardText,
                        linkedInsights: makeNodeLinkInsights,
                        onToggleSaved: {
                            onToggleSavedConcept?(concept(for: selectedInsight))
                        },
                        onRemove: { pendingRemoveInsight = selectedInsight },
                        onFork:   { performForkInsight(selectedInsight) },
                        onSelectLinkedInsight: { insight in
                            focusedInsightID = insight.id
                            showInsightCard(insight)
                        }
                    )
                    .id(selectedInsight.id)
                    .growsWhileTouched()
                    .offset(y: dockedCardDragY)
                    .gesture(dockedCardDismissGesture)
                    .transition(.bottomDockCard)
                    .padding(.horizontal, 10)
                } else if showsDockedCardAfterStudy, let selectedNode {
                    let makeNodeSourceID = viewModel.promotedSourceInsightID(
                        forNodeID: selectedNode.id
                    )
                    DockedNodeTreeCard(
                        node: selectedNode,
                        isSaved: makeNodeSourceID.map(savedConceptIDs.contains) ?? false,
                        onSelectInsight: { insight in
                            focusedInsightID = insight.id
                            showInsightCard(insight)
                        },
                        onToggleSaved: makeNodeSourceID == nil ? nil : {
                            toggleMakeNodeBookmark(selectedNode)
                        },
                        onFork: { performForkNode(selectedNode) }
                    )
                    .id(selectedNode.id)
                    .growsWhileTouched()
                    .offset(y: dockedCardDragY)
                    .gesture(dockedCardDismissGesture)
                    .transition(.bottomDockCard)
                    .padding(.horizontal, 10)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .global).minY
        } action: { top in
            withAnimation(.springStandard) { dockedCardTopInGlobal = top }
        }
        .onDisappear { dockedCardTopInGlobal = nil }
    }

    /// How much of the canvas's bottom the docked cards cover. The canvas ends at the cards'
    /// top edge, so a hovered target centers in the space above them and the Study ring sits
    /// clear of them. In the landscape split the cards dock beside the tree, not over it.
    private func dockedCardObstruction(in geometry: GeometryProxy) -> CGFloat {
        guard !usesLandscapeSplitLayout, !dockedCardKey.isEmpty,
              let dockedCardTopInGlobal else { return 0 }
        let covered = geometry.frame(in: .global).maxY - dockedCardTopInGlobal
        // A card grown tall with Insight links still leaves the tree a workable area.
        return min(max(covered, 0), geometry.size.height * 0.6)
    }

    /// Identifies what `dockedStackContent` shows; a change animates the shared stack.
    private var dockedCardKey: String {
        var parts: [String] = []
        if undoInsight != nil { parts.append("undo") }
        if showsStudyToolCard {
            parts.append("study-tool-\(studyTool)")
        } else if isMidpointMode {
            parts.append("midpoint")
        } else if !cardShouldHide, showsDockedCardAfterStudy {
            if !showQuestionBar, let concept = hoveredConcept {
                parts.append("concept-\(concept.id)")
            } else if let selectedInsight {
                parts.append("insight-\(selectedInsight.id)-\(makeNodeLinkInsights.count)")
            } else if let selectedNode {
                parts.append("node-\(selectedNode.id)")
            }
        }
        return parts.joined(separator: "|")
    }

    var body: some View {
        treeAlerts(treeRequestObservers(treeScreen))
            .canvasAppearance(insightTreeBackground)
    }

    /// The tree, its overlays, and the docked bottom area. The observers and alerts are split
    /// out so `body`'s modifier chain stays within the type checker's limits on older toolchains.
    private var treeScreen: some View {
        GeometryReader { geometry in
            let treePaneWidth = usesLandscapeSplitLayout ? geometry.size.width / 2 : geometry.size.width
            ZStack(alignment: .leading) {
                if usesLandscapeSplitLayout {
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: treePaneWidth)

                        AngroveTheme.Colors.canvas
                            .overlay(alignment: .leading) {
                                Rectangle()
                                    .fill(AngroveTheme.Colors.quietBorder)
                                    .frame(width: 1)
                            }
                    }
                    .ignoresSafeArea()
                }

            InsightTreeCanvasView(
                nodes: viewModel.nodes,
                edges: viewModel.edges,
                restoreFocusedCameraRequest: restoreFocusedCameraRequest,
                focusedInsightID: focusedInsightID,
                focusedSearchNodeID: focusedNodeID,
                pulsingInsightID: questionBarContextInsight?.id,
                pulsingNodeID: selectedNode?.id,
                selectedCanvasTargets: selectedCanvasTargets,
                selectionPulseRequest: selectionPulseRequest,
                makeNodeChildIDs: viewModel.makeNodeChildIDs,
                generatedMakeNodeChildIDs: viewModel.generatedMakeNodeChildIDs,
                placedMidpointNodeIDs: viewModel.placedMidpointNodeIDs,
                placedMidpointSources: viewModel.placedMidpointSources,
                insightBondLengths: viewModel.insightBondLengths,
                layoutTargets: viewModel.layoutTargets,
                nodeDepths: viewModel.nodeDepths,
                showsAllClusterInsights: conversationID == nil,
                defersEntranceUntilPersistedTree: conversationID != nil,
                persistedTreePresentationRevision: persistedTreePresentationRevision,
                animatedPersistedTreePresentationRevision:
                    animatedPersistedTreePresentationRevision,
                isHoveringTarget: selectedInsight != nil || selectedNode != nil || hoveredConcept != nil,
                isMidpointMode: isMidpointMode,
                midpointCenterRequest: midpointCenterRequest,
                midpointPlaceRequest: midpointPlaceRequest,
                midpointTargetIndex: midpointTargetIndex,
                midpointTargetWeight: midpointTargetWeight,
                midpointPercentRequest: midpointPercentRequest,
                onMidpointWeightsChange: { midpointWeights = $0 },
                onNodeTapped: { node in
                    showNodeCard(node)
                },
                onInsightTapped: { insight in
                    showInsightCard(insight)
                },
                onCanvasMoved: {
                    dismissDockedInsight()
                },
                onSuggestConnection: { edge in
                    viewModel.suggestConnection(for: edge)
                },
                onDismissSuggestedNode: { node in
                    viewModel.dismissSuggestedNode(node)
                },
                onMidpointPlaced: { worldPosition, nearestTarget, weights in
                    placeMidpointInsight(at: worldPosition, nearestTarget: nearestTarget, weights: weights)
                },
                midpointPlacedInsightID: midpointPlacedInsightID,
                midpointGeneratedInsightID: midpointGeneratedInsightID,
                onMidpointInsightLoaded: { insightID in
                    revealPlacedMidpointCard(insightID)
                },
                onGeneratingChange: { generating in
                    onMidpointGeneratingChange?(generating)
                    // Once every child has been revealed, unlock the parent card (its Insight
                    // links remain until the user dismisses or navigates away).
                    if !generating { makeNodeGenerating = false }
                },
                onMakeNodeChildRevealed: { childID in
                    appendMakeNodeChildLink(childID)
                },
                onPositionsSettled: { positions in
                    viewModel.commitLivePositions(positions)
                },
                onRequestDismissHover: {
                    // Keep the parent card up while its Make Node children generate — it's
                    // growing an Insight link per child.
                    guard !makeNodeGenerating else { return }
                    dismissDockedInsight()
                },
                onUndiscoveredInsightCountChange: { count in
                    onUndiscoveredInsightCountChange?(count)
                },
                studyNodeID: studiedNodeID,
                studyInitialHoverInsightID: studyInitialHoverID,
                studySelectionIDs: studiedSelectionIDs,
                studySlot: studySlotInStack?.offsetBy(dx: -canvasOriginInStack.x, dy: -canvasOriginInStack.y),
                studyBranchSource: studyBranchSource,
                studyBranchNodeID: studyBranchSource.map { viewModel.promotedNodeID(for: $0.id) },
                studyBranchIsPromoted: studyBranchIsPromoted,
                onStudyBranchFinished: {
                    studyBranchBusy = false
                    onMidpointGeneratingChange?(false)
                    setStudyToolsOpen(false)
                    if let source = studyBranchSource,
                       let node = viewModel.nodes.first(where: { $0.id == viewModel.promotedNodeID(for: source.id) }) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            studySubject = .node(node)
                            studyBranchSource = nil
                        }
                        showNodeCard(node)
                    }
                }
            )
            .frame(
                width: treePaneWidth,
                height: geometry.size.height - dockedCardObstruction(in: geometry),
                alignment: .leading
            )
            .frame(height: geometry.size.height, alignment: .top)
            .background(insightTreeCanvasColor)
            .onGeometryChange(for: CGPoint.self) { proxy in
                proxy.frame(in: .named(InsightTreeStackSpace.name)).origin
            } action: { origin in
                canvasOriginInStack = origin
            }
            // A studied Node Concept or Insight selection stays in the canvas, which handles
            // Study's gestures (including rotating the ring).
            .allowsHitTesting(studyBranchSource != nil || studySubject == nil || studiedNodeID != nil || studiedSelectionIDs != nil)

            if viewModel.nodes.isEmpty {
                EmptyInsightTreeView()
            }

            VStack {
                HStack {
                    if let onClose {
                        Button(action: { studySubject == nil ? onClose() : exitStudy() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .sfSymbolDrawOn()
                                .angroveIconControl()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close insights")
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)

                Spacer()
            }
            .zIndex(11)

            if let studySubject {
                StudyModeView(
                    subject: studySubject,
                    tool: studyTool,
                    branchCount: studyBranchCount,
                    isExiting: isExitingStudy,
                    animatesCenterIconEntrance: false,
                    onBranchCountChange: onStudyBranchCountChange ?? { _ in },
                    onNodeSlotChange: { studySlotInStack = $0 }
                )
                .opacity(studyBranchSource == nil ? 1 : 0)
                .allowsHitTesting(studyBranchSource == nil)
                    .transition(.opacity)
                    .zIndex(10)
            }
            }
            // Shared by the canvas and the Study overlay so a Node Concept can leave the tree
            // from exactly where the canvas drew it.
            .coordinateSpace(.named(InsightTreeStackSpace.name))
        }
        .modelControlsDockedCard(key: dockedCardKey) { dockedStackContent }
        // safeAreaInset moves with the keyboard automatically — no manual observation needed.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                // Insight chip — appears above the bar when keyboard is open, mirrors card dismiss animation
                if showQuestionBar, chipShouldShow, studySubject == nil, let insight = questionBarContextInsight {
                    BranchContextChip(
                        title: insight.title,
                        icon: "text.bubble.fill",
                        isFilled: true,
                        fillColor: AngroveTheme.Colors.canvasSecondary,
                        animatesAppearance: false,
                        showRemove: true,
                        onRemove: {
                            withAnimation(.springLively) {
                                chipShouldShow = false
                                questionBarContextInsight = nil
                            }
                        }
                    )
                    .transition(.scale(scale: 0.35, anchor: .bottom).combined(with: .opacity))
                    // Swipe up → dismiss keyboard → card reappears
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onEnded { value in
                                let isUpward = value.translation.height < -20
                                let isVertical = abs(value.translation.width) < abs(value.translation.height)
                                if isUpward && isVertical {
                                    UIApplication.shared.sendAction(
                                        #selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil
                                    )
                                }
                            }
                    )
                }

                if showQuestionBar {
                    InsightQuestionBar(
                        contextInsight: $questionBarContextInsight,
                        inputFont: inputFont,
                        conversationFontSize: conversationFontSize,
                        onOpen: {},
                        onKeyboardActiveChange: { active in
                            questionBarKeyboardActive = active
                            if active {
                                if let insight = selectedInsight {
                                    withAnimation(.springLively) {
                                        questionBarContextInsight = insight
                                    }
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    guard questionBarKeyboardActive else { return }
                                    withAnimation(.springLively) {
                                        cardShouldHide = true
                                        chipShouldShow = true
                                    }
                                }
                            } else {
                                withAnimation(.springLively) {
                                    chipShouldShow = false
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    guard !questionBarKeyboardActive else { return }
                                    withAnimation(.springStandard) {
                                        cardShouldHide = false
                                    }
                                }
                            }
                        },
                        onCollapse: {
                            questionBarKeyboardActive = false
                            withAnimation(.springStandard) {
                                cardShouldHide = false
                                chipShouldShow = false
                            }
                        },
                        focusTrigger: questionBarFocusTrigger
                    )
                    .padding(.horizontal, 16)
                    .opacity(studySubject == nil ? 1 : 0)
                }
            }
            .padding(.bottom, 16)
            .frame(maxWidth: usesLandscapeSplitLayout ? 420 : .infinity)
            .frame(maxWidth: .infinity, alignment: usesLandscapeSplitLayout ? .trailing : .center)
            .animation(.springStandard, value: selectedInsight?.id)
            .animation(.springStandard, value: selectedNode?.id)
            .animation(.springStandard, value: hoveredConcept?.id)
            .animation(.springStandard, value: isMidpointMode)
            .animation(.springQuick, value: undoInsight != nil)
            .animation(.springStandard, value: showsStudyToolCard)
            .animation(.springStandard, value: showsDockedCardAfterStudy)
        }
    }

    private func treeRequestObservers<Content: View>(_ content: Content) -> some View {
        treeNavigationObservers(treeContentObservers(content))
    }

    /// Insight, bookmark, and selection-request observers (half of `treeRequestObservers`,
    /// split again for Xcode 26.6's type checker).
    private func treeContentObservers<Content: View>(_ content: Content) -> some View {
        content
        .onChange(of: insights) { oldValue, newValue in
            viewModel.updateInsights(newValue, promotedInsightIDs: promotedInsightIDs)
            enqueuePersistedTreeLoad(animateChanges: true)
            restoreRequestedInsightSelection()
            if let selectedInsight,
               !newValue.contains(where: { $0.id == selectedInsight.id }) {
                dismissDockedInsight()
            }
        }
        .onChange(of: promotedInsightIDs) { _, newValue in
            viewModel.updateInsights(insights, promotedInsightIDs: newValue)
        }
        // A placed Midpoint is auto-bookmarked and has nothing else anchoring it to the tree, so
        // un-saving it from ANY bookmark toggle — not just the docked card on this canvas — must
        // remove its node too. `savedConceptIDs` is fed by whatever saved-insights store the host
        // (global tree or a conversation) owns, so this reacts uniformly regardless of where the
        // un-save happened (e.g. the Insight Library popup, which mutates that store directly).
        //
        // Must only react to an actual save -> unsave transition (present in `oldValue`, gone
        // from `newValue`) rather than "just not currently saved" — a Midpoint's placeholder
        // node exists and is generating for a few seconds *before* it gets auto-bookmarked, so
        // it's legitimately absent from `savedConceptIDs` during that window. Reacting to mere
        // absence tore down still-generating placeholders out from under their own generation
        // task the moment anything else touched the saved-insights set.
        .onChange(of: savedConceptIDs) { oldValue, newValue in
            for placedID in viewModel.placedMidpointNodeIDs
            where oldValue.contains(placedID) && !newValue.contains(placedID) {
                viewModel.removePlacedMidpoint(id: placedID)
                if selectedInsight?.id == placedID {
                    dismissDockedInsight()
                }
            }
            for childID in viewModel.generatedMakeNodeChildIDs
            where oldValue.contains(childID) && !newValue.contains(childID) {
                viewModel.removeMakeNodeChild(id: childID)
                if selectedInsight?.id == childID {
                    dismissDockedInsight()
                }
            }
        }
        .onChange(of: selectionRequest) { _, _ in
            selectHoveredCanvasTarget()
        }
        .onChange(of: clearSelectionRequest) { _, _ in
            clearSelectedCanvasTargets()
        }
        .onChange(of: dismissHoverRequest) { _, _ in
            dismissDockedInsight()
        }
        .onChange(of: createConceptRequest) { _, _ in
            promoteHoveredInsightToConcept()
        }
        .onChange(of: studyRequest) { _, _ in
            enterStudy()
        }
        .onChange(of: studyToolsToggleRequest) { _, _ in
            guard studySubject != nil, !isExitingStudy, !studyBranchBusy else { return }
            if showsStudyToolCard {
                setStudyToolsOpen(false)
                studyBranchSource = nil
            } else if let selectedInsight, !promotedInsightIDs.contains(selectedInsight.id) {
                studyBranchSessionID = UUID()
                studyBranchSource = selectedInsight
                studyBranchIsPromoted = false
                setStudyToolsOpen(true)
            }
        }
        .onChange(of: studyBranchConfirmRequest) { _, _ in
            confirmStudyBranch()
        }
        .onChange(of: showsStudyToolCard) { _, isOpen in
            onStudyToolsActiveChange?(isOpen)
        }
        .onChange(of: studyExitRequest) { _, _ in
            guard studySubject != nil else { return }
            exitStudy()
        }
        .onChange(of: restoreSelectedInsightID) { _, _ in
            restoreRequestedInsightSelection()
        }
        .onChange(of: nodeSelectionRequest) { _, _ in
            restoreRequestedNodeSelection()
        }
    }

    /// Search, persistence, and lifecycle observers (the other half).
    private func treeNavigationObservers<Content: View>(_ content: Content) -> some View {
        content
        .onChange(of: inquireConnectionRequest) { _, _ in
            performInquireConnection()
        }
        .onChange(of: midpointEnterRequest) { _, _ in
            enterMidpointMode()
        }
        .onChange(of: searchQuery) { _, _ in
            refreshSearchResults(resetIndex: true)
        }
        .onChange(of: searchPreviousRequest) { _, _ in
            stepSearchResult(by: -1)
        }
        .onChange(of: searchNextRequest) { _, _ in
            stepSearchResult(by: 1)
        }
        .onChange(of: persistedTreePresentationRevision) { _, _ in
            guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            refreshSearchResults(resetIndex: false)
        }
        .onChange(of: highlightPairRequest) { _, _ in
            highlightInsightPair()
        }
        .onAppear {
            if highlightedInsightPair != nil {
                highlightInsightPair()
            }
            restoreRequestedInsightSelection()
            restoreRequestedNodeSelection()
        }
        .task(id: conversationID) {
            viewModel.startModelWork()
            enqueuePersistedTreeLoad(animateChanges: false)
        }
        .onChange(of: persistedTreeRefreshRequest) { _, _ in
            enqueuePersistedTreeLoad(animateChanges: true)
        }
        .onDisappear {
            studyBranchSessionID = UUID()
            studyBranchTask?.cancel()
            if studyBranchBusy { onMidpointGeneratingChange?(false) }
            onStudyToolsActiveChange?(false)
            midpointGenerationTask?.cancel()
            if midpointPlacedInsightID != nil {
                onMidpointGeneratingChange?(false)
            }
        }
    }

    private func treeAlerts<Content: View>(_ content: Content) -> some View {
        content
        .alert("Remove from conversation?", isPresented: Binding(
            get: { pendingRemoveInsight != nil },
            set: { if !$0 { pendingRemoveInsight = nil } }
        )) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                if let insight = pendingRemoveInsight {
                    performRemoveInsight(insight)
                }
                pendingRemoveInsight = nil
            }
        } message: {
            Text("This insight will be removed from this conversation’s tree. Its global bookmark is unchanged.")
        }
        .alert("Unbookmark attached Insights?", isPresented: Binding(
            get: { pendingUnbookmarkMakeNode != nil },
            set: { if !$0 { pendingUnbookmarkMakeNode = nil } }
        )) {
            Button("No") {
                resolveMakeNodeUnbookmark(removingAttachedInsights: false)
            }
            Button("Yes", role: .destructive) {
                resolveMakeNodeUnbookmark(removingAttachedInsights: true)
            }
        } message: {
            Text("Would you also like to unbookmark the Insights attached to this node?")
        }
        .alert(
            "Couldn’t complete that model action",
            isPresented: $isModelActionErrorPresented
        ) {
            Button("Cancel", role: .cancel) {
                pendingModelActionRetry = nil
            }
            Button("Try Again") {
                let retry = pendingModelActionRetry
                pendingModelActionRetry = nil
                retry?()
            }
        } message: {
            Text("The Insight Tree was left unchanged. The on-device model couldn’t finish; please try again.")
        }
        .sheet(item: $viewModel.selectedSuggestedNode) { node in
            SuggestedInsightSheet(node: node) {
                viewModel.dismissSuggestedNode(node)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(AngroveTheme.Colors.canvas)
        }
    }

    private func restoreRequestedInsightSelection() {
        guard let restoreSelectedInsightID,
              selectedInsight?.id != restoreSelectedInsightID,
              let insight = viewModel.nodes
                .lazy
                .flatMap(\.insights)
                .first(where: { $0.id == restoreSelectedInsightID }) else {
            return
        }
        showInsightCard(insight)
    }

    private func restoreRequestedNodeSelection() {
        guard let restoreSelectedNodeID,
              let node = viewModel.nodes.first(where: { $0.id == restoreSelectedNodeID }) else {
            return
        }
        showNodeCard(node)
        if let firstInsight = node.insights.first {
            focusedInsightID = firstInsight.id
        }
    }

    private func showInsightCard(_ insight: InsightModel, animateText: Bool = false, moveCamera: Bool = true) {
        // Navigating to any other insight ends the Make Node card growth.
        if insight.id != makeNodeParentInsightID { clearMakeNodeCardGrowth() }
        animateMidpointCardText = animateText
        // Keyboard is open — update the chip and ensure it's visible
        if questionBarKeyboardActive {
            withAnimation(.springLively) {
                questionBarContextInsight = insight
                chipShouldShow = true
            }
            return
        }

        playDockedCardHaptic()
        onSelectionStateChange?(true)
        onInsightSelectionStateChange?(true)
        // The placed-midpoint reveal lets the canvas own the camera (so user input can cancel
        // it); other taps recenter on the insight as usual.
        if moveCamera {
            focusedInsightID = insight.id
        }
        onQuoteInsight?(concept(for: insight))

        withAnimation(.springStandard) {
            dockedCardDragY = 0
            selectedNode = nil
            selectedInsight = insight
            hoveredConcept = showQuestionBar ? nil : concept(for: insight)
            questionBarContextInsight = insight
        }
    }

    /// The Node Concept being studied, until its exit begins, so the canvas shifts back in
    /// time for the tree to be whole when Study closes.
    private var studiedNodeID: UUID? {
        guard !isExitingStudy, case .node(let node, _) = studySubject else { return nil }
        return node.id
    }

    /// Selected Insights being studied together, until the exit begins (like `studiedNodeID`).
    private var studiedSelectionIDs: [UUID]? {
        guard !isExitingStudy, case .selection(let insights) = studySubject else { return nil }
        return insights.map(\.id)
    }

    /// The Insight a node Study opens hovered, if Study was pressed on one.
    private var studyInitialHoverID: UUID? {
        guard case .node(_, let insightID) = studySubject else { return nil }
        return insightID
    }

    private func enterStudy() {
        // The dock offers Study again as soon as an exit starts; wait for the exit to finish.
        guard !isMidpointMode, !isExitingStudy else { return }
        let subject: StudySubject
        if !selectedCanvasTargets.isEmpty {
            // Study on a selection studies just its Insights. The selection stays, so leaving
            // Study returns to it (ready to Midpoint).
            let insights = selectedCanvasTargets.compactMap { target -> InsightModel? in
                guard case .insight(let id) = target else { return nil }
                return viewModel.nodes.lazy.flatMap(\.insights).first { $0.id == id }
            }
            guard !insights.isEmpty else { return }
            subject = .selection(insights)
        } else if let selectedInsight {
            // Study on an Insight opens its Node Concept with the Insight hovered. The dot
            // matrix Study remains for Insights without an ordinary parent (placed midpoints).
            if let parent = viewModel.nodes.first(where: { node in
                !viewModel.placedMidpointNodeIDs.contains(node.id)
                    && node.insights.contains { $0.id == selectedInsight.id }
            }) {
                subject = .node(parent, hoveredInsightID: selectedInsight.id)
            } else {
                subject = .insight(selectedInsight)
            }
        } else if let selectedNode {
            subject = .node(selectedNode)
        } else {
            return
        }
        studyBranchSource = nil
        studyBranchIsPromoted = false
        isExitingStudy = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.72)
        // The hovered Insight's card stays up; the tools open from the dock's Tools button.
        withAnimation(.easeOut(duration: 0.3)) {
            studySubject = subject
        }
        setStudyToolsOpen(false)
        onStudyModeChange?(true)
    }

    private func exitStudy() {
        guard studySubject != nil, !isExitingStudy else { return }
        studyBranchSource = nil
        studyBranchSessionID = UUID()
        studyBranchBusy = false
        onMidpointGeneratingChange?(false)
        withAnimation(.springStandard) {
            isExitingStudy = true
        }
        // Tell the host now, so the dock and Exit change back while the camera moves.
        onStudyModeChange?(false)
        // Leaving a selection's Study returns to the selection itself, not an Insight hovered
        // in Study, so the dock offers the selection's actions (Midpoint) again.
        if case .selection = studySubject { dismissDockedInsight() }
        setStudyToolsOpen(false)
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            withAnimation(.springStandard) {
                showsDockedCardAfterStudy = true
            }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                studySubject = nil
                isExitingStudy = false
            }
        }
    }

    private func showNodeCard(_ node: NodeModel) {
        clearMakeNodeCardGrowth()
        playDockedCardHaptic()
        onSelectionStateChange?(true)
        onInsightSelectionStateChange?(false)
        onQuoteInsight?(quoteTarget(for: node))

        withAnimation(.springStandard) {
            dockedCardDragY = 0
            selectedInsight = nil
            selectedNode = node
            hoveredConcept = showQuestionBar ? nil : quoteTarget(for: node)
            questionBarContextInsight = nil
        }
    }

    private func setStudyToolsOpen(_ isOpen: Bool) {
        studyToolCardDragY = 0
        withAnimation(.springStandard) {
            showsStudyToolCard = isOpen
        }
    }

    /// Swiping the tool card down closes the tools, like swiping an Insight card away.
    private var studyToolCardDismissGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // Only a downward swipe dismisses Branch.
                guard value.translation.height > abs(value.translation.width) || studyToolCardDragY > 0 else { return }
                studyToolCardDragY = max(0, value.translation.height)
            }
            .onEnded { value in
                guard studyToolCardDragY > 0 else { return }
                if value.translation.height > 100 || value.predictedEndTranslation.height > 180 {
                    guard !studyBranchBusy else {
                        withAnimation(.springStandard) { studyToolCardDragY = 0 }
                        return
                    }
                    setStudyToolsOpen(false)
                    studyBranchSource = nil
                } else {
                    withAnimation(.springLively) {
                        studyToolCardDragY = 0
                    }
                }
            }
    }

    private var dockedCardDismissGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                dockedCardDragY = max(0, value.translation.height)
            }
            .onEnded { value in
                let h = value.translation.height
                let predicted = value.predictedEndTranslation.height
                if h > 100 || predicted > 180 {
                    // Large swipe → full dismiss
                    dismissDockedInsight()
                } else if h > 28 {
                    // Small swipe down → collapse to chip (focus question bar)
                    withAnimation(.springLively) {
                        dockedCardDragY = 0
                    }
                    questionBarFocusTrigger += 1
                } else {
                    withAnimation(.springLively) {
                        dockedCardDragY = 0
                    }
                }
            }
    }

    private func performRemoveInsight(_ insight: InsightModel) {
        let concept = concept(for: insight)
        onRemoveInsight?(concept)   // triggers onChange → dismissDockedInsight
        undoTask?.cancel()
        withAnimation(.springStandard) {
            undoInsight = concept
        }
        undoTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.springQuick) {
                undoInsight = nil
            }
        }
    }

    private func performForkInsight(_ insight: InsightModel) {
        guard let concept = insights.first(where: { $0.id == insight.id }) else { return }
        dismissDockedInsight()
        onForkInsight?(concept)
    }

    /// Branches a new inquiry from a node concept. Prefers a member insight's saved concept, else
    /// synthesizes one from the node's own label + definition.
    private func performForkNode(_ node: NodeModel) {
        let concept = node.insights.compactMap { insight in insights.first(where: { $0.id == insight.id }) }.first
            ?? ConceptDefinition(
                word: node.conceptLabel,
                partOfSpeech: "",
                pronunciation: "",
                meaning: node.definition,
                example: ""
            )
        dismissDockedInsight()
        onForkInsight?(concept)
    }

    private func dismissDockedInsight() {
        guard selectedInsight != nil || selectedNode != nil || hoveredConcept != nil else { return }

        clearMakeNodeCardGrowth()
        playDockedCardHaptic()
        onSelectionStateChange?(false)
        onInsightSelectionStateChange?(false)
        onQuoteInsight?(nil)

        withAnimation(.springQuick) {
            dockedCardDragY = 0
            selectedInsight = nil
            selectedNode = nil
            hoveredConcept = nil
            questionBarContextInsight = nil
        }
    }

    // Dismisses the docked card without clearing the question bar chip.
    // Called when the question bar keyboard opens so the card slides away
    // but the quoted insight remains available in the bar.
    private func dismissDockedCard() {
        guard selectedInsight != nil || selectedNode != nil || hoveredConcept != nil else { return }

        clearMakeNodeCardGrowth()
        playDockedCardHaptic()
        onSelectionStateChange?(false)
        onInsightSelectionStateChange?(false)
        onQuoteInsight?(nil)

        withAnimation(.springQuick) {
            dockedCardDragY = 0
            selectedInsight = nil
            selectedNode = nil
            hoveredConcept = nil
        }
    }

    private func clearCanvasSelectionSilently() {
        guard selectedInsight != nil || selectedNode != nil || questionBarContextInsight != nil || hoveredConcept != nil else { return }

        clearMakeNodeCardGrowth()
        onSelectionStateChange?(false)
        onInsightSelectionStateChange?(false)
        onQuoteInsight?(nil)

        withAnimation(.springQuick) {
            dockedCardDragY = 0
            selectedInsight = nil
            selectedNode = nil
            hoveredConcept = nil
            questionBarContextInsight = nil
        }
    }

    private func clearSelectedCanvasTargets() {
        guard !selectedCanvasTargets.isEmpty else {
            if isMidpointMode { exitMidpointMode() }
            return
        }
        let firstTarget = selectedCanvasTargets[0]
        if isMidpointMode { exitMidpointMode() }
        selectedCanvasTargets.removeAll()
        onSelectedCanvasItemCountChange?(0)
        rehoverTarget(firstTarget)
    }

    private func rehoverTarget(_ target: CanvasSelectionTarget) {
        // Clear the focus id first, then re-hover on the next runloop. Canceling a selection
        // often re-targets the insight that's *already* focused (e.g. a single-item selection),
        // and the canvas only re-centers on a genuine focusedInsightID change — so without the
        // nil→id transition the camera wouldn't return to hovering the first selected item.
        focusedInsightID = nil
        DispatchQueue.main.async {
            switch target {
            case .insight(let id):
                guard let insight = viewModel.nodes.flatMap(\.insights).first(where: { $0.id == id }) else { return }
                showInsightCard(insight)
            case .node(let id):
                guard let node = viewModel.nodes.first(where: { $0.id == id }) else { return }
                showNodeCard(node)
                if let firstInsight = node.insights.first {
                    focusedInsightID = firstInsight.id
                }
            }
        }
    }

    private func refreshSearchResults(resetIndex: Bool) {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            let hadResults = !searchResults.isEmpty
            searchResults = []
            searchResultIndex = 0
            focusedInsightID = nil
            focusedNodeID = nil
            onSearchResultsChange?(0, 0)
            if hadResults {
                restoreFocusedCameraRequest += 1
            }
            return
        }

        let rankedInsights = viewModel.nodes
            .flatMap(\.insights)
            .compactMap { insight -> (target: CanvasSelectionTarget, title: String, score: Double)? in
                guard let score = searchScore(query: query, title: insight.title) else {
                    return nil
                }
                return (.insight(insight.id), insight.title, score)
            }

        let rankedNodes = viewModel.nodes.compactMap {
            node -> (target: CanvasSelectionTarget, title: String, score: Double)? in
            guard !viewModel.placedMidpointNodeIDs.contains(node.id),
                  let score = searchScore(
                    query: query,
                    title: node.conceptLabel
                  ) else {
                return nil
            }
            return (.node(node.id), node.conceptLabel, score)
        }

        let ranked = (rankedInsights + rankedNodes)
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }

        let previousResult = searchResults.indices.contains(searchResultIndex)
            ? searchResults[searchResultIndex]
            : nil
        searchResults = ranked.map(\.target)
        if resetIndex {
            searchResultIndex = 0
        } else if let previousResult,
                  let retainedIndex = searchResults.firstIndex(of: previousResult) {
            searchResultIndex = retainedIndex
        } else {
            searchResultIndex = min(searchResultIndex, max(searchResults.count - 1, 0))
        }
        focusCurrentSearchResult()
    }

    private func stepSearchResult(by offset: Int) {
        guard !searchResults.isEmpty else { return }
        searchResultIndex =
            (searchResultIndex + offset + searchResults.count)
            % searchResults.count
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
        focusCurrentSearchResult()
    }

    private func focusCurrentSearchResult() {
        guard searchResults.indices.contains(searchResultIndex) else {
            focusedInsightID = nil
            focusedNodeID = nil
            onSearchResultsChange?(0, 0)
            return
        }
        let result = searchResults[searchResultIndex]
        onSearchResultsChange?(searchResultIndex + 1, searchResults.count)

        switch result {
        case .insight(let insightID):
            focusedNodeID = nil
            if focusedInsightID == insightID {
                focusedInsightID = nil
                DispatchQueue.main.async {
                    focusedInsightID = insightID
                }
            } else {
                focusedInsightID = insightID
            }

        case .node(let nodeID):
            focusedInsightID = nil
            if focusedNodeID == nodeID {
                focusedNodeID = nil
                DispatchQueue.main.async {
                    focusedNodeID = nodeID
                }
            } else {
                focusedNodeID = nodeID
            }
        }
    }

    private func searchScore(query: String, title: String) -> Double? {
        let needle = query.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        let haystack = title.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        guard !needle.isEmpty else { return nil }

        if haystack == needle { return 10_000 }
        if haystack.hasPrefix(needle) {
            return 8_000 - Double(haystack.count - needle.count)
        }
        if let range = haystack.range(of: needle) {
            return 6_000 - Double(haystack.distance(from: haystack.startIndex, to: range.lowerBound))
        }

        let queryTokens = needle.split(whereSeparator: \.isWhitespace)
        if !queryTokens.isEmpty, queryTokens.allSatisfy({ haystack.contains($0) }) {
            return 4_000 + Double(queryTokens.count * 10)
        }

        let similarity = normalizedEditSimilarity(needle, haystack)
        guard similarity >= 0.45 else { return nil }
        return similarity * 1_000
    }

    private func normalizedEditSimilarity(_ left: String, _ right: String) -> Double {
        let leftCharacters = Array(left)
        let rightCharacters = Array(right)
        guard !leftCharacters.isEmpty || !rightCharacters.isEmpty else { return 1 }

        var previous = Array(0...rightCharacters.count)
        for (leftIndex, leftCharacter) in leftCharacters.enumerated() {
            var current = [leftIndex + 1]
            for (rightIndex, rightCharacter) in rightCharacters.enumerated() {
                current.append(
                    min(
                        current[rightIndex] + 1,
                        previous[rightIndex + 1] + 1,
                        previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                    )
                )
            }
            previous = current
        }
        let distance = previous[rightCharacters.count]
        return 1 - (Double(distance) / Double(max(leftCharacters.count, rightCharacters.count)))
    }

    private func playDockedCardHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.65)
    }

    private func playSelectionHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            generator.impactOccurred(intensity: 0.8)
        }
    }

    private func selectHoveredCanvasTarget() {
        guard selectedCanvasTargets.count < CanvasSelectionPolicy.maximumCount else { return }

        let target: CanvasSelectionTarget?
        if let selectedInsight {
            target = .insight(selectedInsight.id)
        } else if let selectedNode {
            target = .node(selectedNode.id)
        } else {
            target = nil
        }

        guard let target else { return }

        guard !selectedCanvasTargets.contains(target) else { return }

        selectedCanvasTargets.append(target)
        playSelectionHaptic()
        if selectedCanvasTargets.count > 1 {
            selectionPulseRequest += 1
        }
        onSelectedCanvasItemCountChange?(selectedCanvasTargets.count)
        // Clear the hover so the dock immediately reflects the selection state
        // (e.g. shows the "Tap another Insight" hint) instead of waiting for a tap/drag.
        clearCanvasSelectionSilently()
    }

    private func highlightInsightPair() {
        guard let highlightedInsightPair else { return }
        let firstTarget = CanvasSelectionTarget.insight(highlightedInsightPair.0)
        let secondTarget = CanvasSelectionTarget.insight(highlightedInsightPair.1)
        let availableInsightIDs = Set(viewModel.nodes.flatMap(\.insights).map(\.id))
        guard availableInsightIDs.contains(highlightedInsightPair.0),
              availableInsightIDs.contains(highlightedInsightPair.1) else {
            return
        }

        if isMidpointMode { exitMidpointMode() }
        dismissDockedInsight()
        selectedCanvasTargets = [firstTarget, secondTarget]
        selectionPulseRequest += 1
        onSelectedCanvasItemCountChange?(selectedCanvasTargets.count)
        focusedInsightID = nil
        DispatchQueue.main.async {
            focusedInsightID = highlightedInsightPair.1
            if startsMidpointForHighlightedPair {
                enterMidpointMode()
            }
        }
    }

    private func confirmStudyBranch() {
        guard let source = studyBranchSource, showsStudyToolCard, !studyBranchBusy,
              !studyBranchIsPromoted, (2...6).contains(studyBranchCount) else { return }
        let count = studyBranchCount
        let sourceID = source.id
        let sessionID = studyBranchSessionID
        studyBranchBusy = true
        onMidpointGeneratingChange?(true)
        var hasReservedPromotion = false
        let begin = {
            guard studyBranchSessionID == sessionID,
                  studyBranchSource?.id == sourceID, studyBranchBusy else { return }
            if SettingsHaptics.isEnabled {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.8)
            }
            withAnimation(.easeInOut(duration: 0.3)) { studyBranchIsPromoted = true }
            hasReservedPromotion = true
            viewModel.reserveMakeNodeGeneration(for: sourceID, branchCount: count)
            onPromotedInsightIDsChange?(promotedInsightIDs.contains(sourceID) ? promotedInsightIDs : promotedInsightIDs + [sourceID])
        }
        let rollback = {
            if hasReservedPromotion {
                hasReservedPromotion = false
                viewModel.cancelMakeNodeGeneration(for: sourceID)
                onPromotedInsightIDsChange?(promotedInsightIDs.filter { $0 != sourceID })
            }
            if studyBranchSessionID == sessionID, studyBranchSource?.id == sourceID {
                studyBranchIsPromoted = false
                studyBranchBusy = false
                onMidpointGeneratingChange?(false)
            }
        }
        let generate: () async -> Void = {
            guard studyBranchSessionID == sessionID,
                  studyBranchIsPromoted, studyBranchSource?.id == sourceID else { return }
            do {
                try await viewModel.generateReservedMakeNodeChildren(for: source)
                try Task.checkCancellation()
                bookmarkMakeNodeOutput(for: sourceID)
            } catch {
                rollback()
                guard !Task.isCancelled, studyBranchSessionID == sessionID else { return }
                presentModelActionError { confirmStudyBranch() }
            }
        }
        if let modelTasks {
            modelTasks.enqueue(kind: .studyBranch, originPage: modelTaskOriginPage,
                               onStart: begin, onCancel: rollback, operation: generate)
        } else {
            begin()
            studyBranchTask = Task { await generate() }
        }
    }

    private func promoteHoveredInsightToConcept() {
        guard let selectedInsight else { return }
        guard !promotedInsightIDs.contains(selectedInsight.id) else { return }

        let insightID = selectedInsight.id
        let beginGeneration = {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.8)
            // Keep this insight's card docked while its children generate; it grows an Insight
            // link per child, each appended in sync with the child's reveal haptic.
            makeNodeParentInsightID = insightID
            makeNodeLinkInsightIDs = []
            makeNodeGenerating = true
            viewModel.reserveMakeNodeGeneration(for: insightID)
            onPromotedInsightIDsChange?(promotedInsightIDs + [insightID])
        }
        let cancelGeneration = {
            viewModel.cancelMakeNodeGeneration(for: insightID)
            onPromotedInsightIDsChange?(
                promotedInsightIDs.filter { $0 != insightID }
            )
            if makeNodeParentInsightID == insightID {
                clearMakeNodeCardGrowth()
                onMidpointGeneratingChange?(false)
            }
        }

        guard let modelTasks else {
            beginGeneration()
            Task {
                do {
                    try await viewModel.generateReservedMakeNodeChildren(
                        for: selectedInsight
                    )
                    bookmarkMakeNodeOutput(for: insightID)
                } catch {
                    guard !Task.isCancelled else { return }
                    cancelGeneration()
                    presentModelActionError {
                        promoteHoveredInsightToConcept()
                    }
                }
            }
            return
        }

        modelTasks.enqueue(
            kind: .makeNode,
            originPage: modelTaskOriginPage,
            onStart: beginGeneration,
            onCancel: cancelGeneration
        ) {
            do {
                try await viewModel.generateReservedMakeNodeChildren(
                    for: selectedInsight
                )
                bookmarkMakeNodeOutput(for: insightID)
            } catch {
                guard !Task.isCancelled else { return }
                cancelGeneration()
                presentModelActionError {
                    promoteHoveredInsightToConcept()
                }
            }
        }
    }

    private func bookmarkMakeNodeOutput(for insightID: UUID) {
        let concepts = viewModel.makeNodeBookmarkConcepts(for: insightID)
        guard !concepts.isEmpty else { return }
        if let onBookmarkConcepts {
            onBookmarkConcepts(concepts)
        } else {
            for concept in concepts where !savedConceptIDs.contains(concept.id) {
                onToggleSavedConcept?(concept)
            }
        }
    }

    private func toggleMakeNodeBookmark(_ node: NodeModel) {
        guard let sourceID = viewModel.promotedSourceInsightID(forNodeID: node.id),
              let nodeConcept = viewModel.makeNodeBookmarkConcepts(for: sourceID).first else {
            return
        }
        if savedConceptIDs.contains(sourceID) {
            pendingUnbookmarkMakeNode = node
        } else if let onBookmarkConcepts {
            onBookmarkConcepts([nodeConcept])
        } else {
            onToggleSavedConcept?(nodeConcept)
        }
    }

    private func resolveMakeNodeUnbookmark(removingAttachedInsights: Bool) {
        guard let node = pendingUnbookmarkMakeNode,
              let sourceID = viewModel.promotedSourceInsightID(forNodeID: node.id) else {
            pendingUnbookmarkMakeNode = nil
            return
        }
        let bookmarks = viewModel.makeNodeBookmarkConcepts(for: sourceID)
        viewModel.removeMakeNode(
            for: sourceID,
            keepingChildren: !removingAttachedInsights
        )
        onPromotedInsightIDsChange?(promotedInsightIDs.filter { $0 != sourceID })

        let conceptsToRemove = removingAttachedInsights ? bookmarks : Array(bookmarks.prefix(1))
        for concept in conceptsToRemove where savedConceptIDs.contains(concept.id) {
            onToggleSavedConcept?(concept)
        }
        pendingUnbookmarkMakeNode = nil
        dismissDockedInsight()
    }

    private func presentModelActionError(retry: @escaping () -> Void) {
        pendingModelActionRetry = retry
        isModelActionErrorPresented = true
    }

    /// Called by the canvas as each Make Node child is revealed (on its haptic). Appends an
    /// Insight link for it to the docked parent card, animated in with the reveal.
    private func appendMakeNodeChildLink(_ childID: UUID) {
        guard let parentID = makeNodeParentInsightID,
              selectedInsight?.id == parentID,
              !makeNodeLinkInsightIDs.contains(childID) else { return }
        withAnimation(.springRelaxed) {
            makeNodeLinkInsightIDs.append(childID)
        }
    }

    /// Resolved child insights for the links currently growing on the docked parent card.
    private var makeNodeLinkInsights: [InsightModel] {
        guard selectedInsight?.id == makeNodeParentInsightID else { return [] }
        let all = viewModel.nodes.flatMap(\.insights)
        return makeNodeLinkInsightIDs.compactMap { id in all.first(where: { $0.id == id }) }
    }

    private func clearMakeNodeCardGrowth() {
        makeNodeParentInsightID = nil
        makeNodeLinkInsightIDs = []
        makeNodeGenerating = false
    }

    private func performInquireConnection() {
        guard selectedCanvasTargets.count >= 2 else { return }
        let concepts = selectedCanvasTargets.compactMap { concept(for: $0) }
        guard concepts.count == selectedCanvasTargets.count else { return }
        clearSelectedCanvasTargets()
        dismissDockedInsight()
        onInquireConnectionConcepts?(concepts)
    }

    // MARK: - Midpoint Mode

    private func enterMidpointMode() {
        guard !showQuestionBar else { return }
        guard selectedCanvasTargets.count >= 2 else { return }
        dismissDockedInsight()
        isMidpointMode = true
        onMidpointModeChange?(true)
    }

    private func exitMidpointMode() {
        guard isMidpointMode else { return }
        isMidpointMode = false
        onMidpointModeChange?(false)
    }

    /// Commits the placed midpoint immediately so the loading icon can appear at the chosen
    /// position, then generates and swaps in its real content without changing its identity.
    private func placeMidpointInsight(at worldPosition: CGPoint, nearestTarget: CanvasSelectionTarget, weights: [Double]) {
        let sourceTargets = selectedCanvasTargets
        // `self.` because a local `concept` later in this function shadows the method on
        // older Swift toolchains.
        let sourceConcepts = sourceTargets.compactMap { self.concept(for: $0) }
        guard sourceConcepts.count >= 2, sourceConcepts.count == weights.count else { return }
        let cachedSourceEmbeddings = sourceTargets.map { cachedEmbedding(for: $0) }
        // Connect the placed midpoint to every source it was spawned from — to the insight chip
        // for a selected insight, or the node center for a selected node concept.
        let sources: [MidpointSource] = selectedCanvasTargets.compactMap { target in
            guard let id = insightID(for: target) else { return nil }
            if case .node = target { return MidpointSource(insightID: id, isNode: true) }
            return MidpointSource(insightID: id, isNode: false)
        }
        let concept = makeMidpointLoadingConcept()

        // The placed node and its single insight both share the concept id.
        midpointPlacedInsightID = concept.id
        midpointGeneratedInsightID = nil
        onMidpointGeneratingChange?(true)
        viewModel.addPlacedMidpoint(concept: concept, at: worldPosition, sources: sources)

        exitMidpointMode()
        selectedCanvasTargets.removeAll()
        onSelectedCanvasItemCountChange?(0)

        let placedID = concept.id
        midpointGenerationTask?.cancel()
        let generateMidpoint = {
            do {
                let generated = try await requestMidpointDefinition(
                    weights: weights,
                    targets: sourceConcepts,
                    cachedSourceEmbeddings: cachedSourceEmbeddings
                )
                guard !Task.isCancelled, midpointPlacedInsightID == placedID else { return }
                viewModel.replacePlacedMidpoint(id: placedID, with: generated)
                midpointGeneratedInsightID = placedID
                // Midpoint blends aren't the user's own saved research — they're synthesized on
                // the spot from sources the user already selected, so save it automatically
                // rather than making them separately hunt down and bookmark their own creation.
                // `onToggleSavedConcept` only adds (this id can't already be saved — it's fresh),
                // so this is the easy "unbookmark to get rid of it" the user asked for: the normal
                // save toggle already removes it from the tree like any other bookmark.
                if !savedConceptIDs.contains(placedID) {
                    onToggleSavedConcept?(
                        ConceptDefinition(
                            id: placedID,
                            word: generated.word,
                            partOfSpeech: generated.partOfSpeech,
                            pronunciation: generated.pronunciation,
                            meaning: generated.meaning,
                            example: generated.example
                        )
                    )
                }
            } catch {
                guard !Task.isCancelled, midpointPlacedInsightID == placedID else { return }
                viewModel.removePlacedMidpoint(id: placedID)
                midpointPlacedInsightID = nil
                midpointGeneratedInsightID = nil
                onMidpointGeneratingChange?(false)
                presentModelActionError {
                    selectedCanvasTargets = sourceTargets
                    placeMidpointInsight(
                        at: worldPosition,
                        nearestTarget: nearestTarget,
                        weights: weights
                    )
                }
            }
        }

        guard let modelTasks else {
            midpointGenerationTask = Task { @MainActor in
                await generateMidpoint()
            }
            return
        }

        modelTasks.enqueue(
            kind: .createMidpoint,
            originPage: modelTaskOriginPage,
            onCancel: {
                guard midpointPlacedInsightID == placedID else { return }
                viewModel.removePlacedMidpoint(id: placedID)
                midpointPlacedInsightID = nil
                midpointGeneratedInsightID = nil
                onMidpointGeneratingChange?(false)
            }
        ) {
            await generateMidpoint()
        }
    }

    /// Called by the canvas after generation and the loading-icon reveal sequence. Pops the
    /// generated Insight card with its body text animating in like a streamed model response.
    private func revealPlacedMidpointCard(_ insightID: UUID) {
        guard midpointPlacedInsightID == insightID else { return }
        midpointPlacedInsightID = nil
        midpointGeneratedInsightID = nil
        midpointGenerationTask = nil
        onMidpointGeneratingChange?(false)
        // If the user navigated to another insight/node while it generated, don't hijack their card.
        let viewingOther = (selectedInsight != nil && selectedInsight?.id != insightID) || selectedNode != nil
        guard !viewingOther else { return }
        guard let insight = viewModel.nodes.flatMap(\.insights).first(where: { $0.id == insightID }) else { return }
        showInsightCard(insight, animateText: true, moveCamera: false)
    }

    /// Empty, identity-bearing content used only while the loading icon is visible. It is never
    /// revealed as an Insight title; the generated definition replaces it in place first.
    private func makeMidpointLoadingConcept() -> ConceptDefinition {
        ConceptDefinition(
            word: "",
            partOfSpeech: "",
            pronunciation: "",
            meaning: "",
            example: ""
        )
    }

    private func requestMidpointDefinition(
        weights: [Double],
        targets: [ConceptDefinition],
        cachedSourceEmbeddings: [[Double]?]
    ) async throws -> ConceptDefinition {
        let candidates = try await model.blendConceptCandidates(
            targets,
            weights: weights
        )
        guard let fallback = candidates.first else {
            throw AngroveModelActionError.invalidResponse
        }

        var sourceEmbeddings: [[Double]] = []
        for index in targets.indices {
            if index < cachedSourceEmbeddings.count,
               let cached = cachedSourceEmbeddings[index],
               !cached.isEmpty {
                sourceEmbeddings.append(cached)
                continue
            }
            let target = targets[index]
            guard let embedded = await embeddingProvider.embed(
                "\(target.word). \(target.semanticDefinition)"
            ) else {
                return fallback
            }
            sourceEmbeddings.append(embedded)
        }
        guard let targetCentroid = normalizedWeightedCentroid(
            sourceEmbeddings,
            weights: weights
        ) else {
            return fallback
        }

        var nearest = fallback
        var nearestDistance = Double.infinity
        for candidate in candidates {
            guard let candidateEmbedding = await embeddingProvider.embed(
                "\(candidate.word). \(candidate.semanticDefinition)"
            ) else {
                continue
            }
            let distance = semanticDistance(candidateEmbedding, targetCentroid)
            if distance < nearestDistance {
                nearest = candidate
                nearestDistance = distance
            }
        }
        return nearest
    }

    private func cachedEmbedding(for target: CanvasSelectionTarget) -> [Double]? {
        switch target {
        case .insight(let id):
            return viewModel.nodes
                .flatMap(\.insights)
                .first(where: {
                    $0.id == id && $0.embeddingVersion == embeddingProvider.version
                })?
                .embedding
        case .node(let id):
            guard let embedding = viewModel.nodes
                .first(where: { $0.id == id })?
                .embedding,
                !embedding.isEmpty else {
                return nil
            }
            return embedding
        }
    }

    private func insightID(for target: CanvasSelectionTarget) -> UUID? {
        switch target {
        case .insight(let id):
            return id
        case .node(let id):
            return viewModel.nodes.first(where: { $0.id == id })?.insights.first?.id
        }
    }

    private func concept(for target: CanvasSelectionTarget) -> ConceptDefinition? {
        switch target {
        case .insight(let id):
            guard let insight = viewModel.nodes
                .flatMap(\.insights)
                .first(where: { $0.id == id }) else {
                return nil
            }
            return concept(for: insight)
        case .node(let id):
            guard let node = viewModel.nodes.first(where: { $0.id == id }) else { return nil }
            return quoteTarget(for: node)
        }
    }

    private func concept(for insight: InsightModel) -> ConceptDefinition {
        if let placedMidpoint = viewModel.placedMidpointConcept(for: insight.id) {
            return placedMidpoint
        }

        // A persisted tree Insight already carries the definition scoped to this conversation.
        // Resolving it through the global library can return the same term with definitions merged
        // from other conversations, which makes the tree card show unrelated meanings.
        if conversationID != nil {
            return ConceptDefinition(
                id: insight.id,
                word: insight.title,
                partOfSpeech: "",
                pronunciation: "",
                meaning: insight.definition,
                example: ""
            )
        }

        return insights.first(where: { $0.id == insight.id })
            ?? ConceptDefinition(
                id: insight.id,
                word: insight.title,
                partOfSpeech: "",
                pronunciation: "",
                meaning: insight.definition,
                example: ""
            )
    }

    private func loadPersistedTree(animateChanges: Bool) async {
        guard let conversationID else { return }
        persistedTreeLoadGeneration += 1
        let loadGeneration = persistedTreeLoadGeneration

        guard loadGeneration == persistedTreeLoadGeneration else { return }
        applyLocalSeedTreeIfAvailable(conversationID: conversationID)
        await viewModel.prepareSemanticTree()
        guard loadGeneration == persistedTreeLoadGeneration else { return }
        persistedTreePresentationRevision += 1
        if animateChanges {
            animatedPersistedTreePresentationRevision = persistedTreePresentationRevision
        }
        if animateChanges {
            onPersistedTreeRefreshCompleted?()
        }
    }

    /// On-device-labeled Nodes, one per turn the model judged as seeding or materially extending
    /// the subject (see `insightTreeSeedCandidate`), fed into the view model's own clustering pass
    /// as pre-existing anchor clusters (see `InsightTreeViewModel.setLocalSeedAnchors`). Feeding
    /// seeds and saved Insights into the same clustering pass lets a saved Insight attach under
    /// the seeded subject when related, instead of one replacing the other.
    private func applyLocalSeedTreeIfAvailable(conversationID: UUID) {
        let localSeeds = LocalInsightTreeSeedStore.seeds(for: conversationID)
#if DEBUG
        print("Angrove InsightTreeView: applyLocalSeedTreeIfAvailable found \(localSeeds.count) seed(s) for \(conversationID)")
#endif
        viewModel.setLocalSeedAnchors(localSeeds)
    }

    /// Loading saved seeds and preparing embeddings performs no generative model work. Apply
    /// bookmark changes immediately rather than waiting behind definition/label queue jobs.
    private func enqueuePersistedTreeLoad(animateChanges: Bool) {
        guard conversationID != nil else { return }
        Task { await loadPersistedTree(animateChanges: animateChanges) }
    }

    private func quoteTarget(for node: NodeModel) -> ConceptDefinition? {
        // Quote the Node Concept itself (its label + definition), so the whole grouping can be
        // pulled back into a conversation — not just one member insight. Promoted nodes carry
        // their own definition; auto-clustered nodes fall back to a summary of their members.
        let label = node.conceptLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return nil }

        let ownDefinition = node.definition.trimmingCharacters(in: .whitespacesAndNewlines)
        let meaning: String
        if !ownDefinition.isEmpty {
            meaning = ownDefinition
        } else {
            let titles = node.insights.prefix(6).map(\.title).filter { !$0.isEmpty }
            meaning = titles.isEmpty ? "" : "A grouping of related insights: " + titles.joined(separator: ", ") + "."
        }

        return ConceptDefinition(
            id: node.id,
            word: label,
            partOfSpeech: "",
            pronunciation: "",
            meaning: meaning,
            example: ""
        )
    }
}

/// A literal weighted centroid in the active cosine-embedding space. Source vectors are first
/// normalized so their magnitudes cannot distort the percentages, then the centroid is normalized
/// for direct cosine-distance comparison with generated candidates.
func normalizedWeightedCentroid(
    _ vectors: [[Double]],
    weights: [Double]
) -> [Double]? {
    guard let first = vectors.first,
          !first.isEmpty,
          vectors.count == weights.count,
          vectors.allSatisfy({ $0.count == first.count }),
          weights.allSatisfy(\.isFinite) else {
        return nil
    }

    let clippedWeights = weights.map { max($0, 0) }
    let totalWeight = clippedWeights.reduce(0, +)
    guard totalWeight > 0 else { return nil }

    var center = Array(repeating: 0.0, count: first.count)
    for (vector, weight) in zip(vectors, clippedWeights) where weight > 0 {
        let magnitude = sqrt(vector.map { $0 * $0 }.reduce(0, +))
        guard magnitude > 0 else { return nil }
        let normalizedWeight = weight / totalWeight
        for index in vector.indices {
            center[index] += vector[index] / magnitude * normalizedWeight
        }
    }

    let centerMagnitude = sqrt(center.map { $0 * $0 }.reduce(0, +))
    guard centerMagnitude > 0 else { return nil }
    return center.map { $0 / centerMagnitude }
}

private struct EmptyInsightTreeView: View {
    var body: some View {
        AngroveEmptyState(
            systemImage: "brain.head.profile",
            title: "Insights will gather here",
            message: "Save insights from conversations to begin forming Theo's map of connected ideas."
        )
    }
}
