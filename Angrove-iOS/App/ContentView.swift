//  Angrove-iOS
//
//  Created by Ryan on 4/11/26.
//

import Combine
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - App Shell

struct ContentView: View {
    // MARK: - State

    @Environment(\.angroveModel) private var angroveModel
    @Environment(\.embeddingProvider) private var embeddingProvider
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var isStartupReady = false
    @State private var questionText: String = ""
    @State private var isAtBottom: Bool = false
    @FocusState private var isKeyboardVisible: Bool
    @State private var uploadedFiles: [UploadedFile] = []
    @State private var showFilePicker: Bool = false
    @State private var showPhotoPicker: Bool = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showCamera: Bool = false
    @State private var collectedDefinitions: [ConceptDefinition] = []
    @State private var globalTreeInsights: [ConceptDefinition] =
        GlobalInsightTreeStore.load()
    @State private var isGlobalTreeUpdatePromptVisible: Bool = false
    /// The saved Insights the user last answered the Global Insight Tree update prompt for.
    @State private var globalTreeAcknowledgedLibraryIDs: Set<UUID>? =
        GlobalInsightTreeUpdatePrompt.loadAcknowledgedLibraryIDs()
    @State private var isGlobalTreeReconciling: Bool = false
    /// After accepting an update, Global Insights stays quiet until model work originating on a
    /// different page completes. Global-page actions must not repeatedly re-offer the same sync.
    @State private var suppressGlobalTreePromptUntilExternalModelCompletion: Bool = false
    @State private var activePage: AppPage = .home
    @State private var displayedPage: AppPage = .home
    @State private var isLibraryReaderVisible = false
    /// Measured height of the shell's single Model Controls bar, reserved as bottom inset.
    @State private var modelControlsHeight: CGFloat = 0
    @State private var libraryNavigationRequest: LibraryNavigationRequest?
    @State private var hasAppliedStartupDestination = false
    @State private var hasPendingDailyQuestionLink = false
    @State private var appLockController = AppLockController()
    @State private var isPageContentVisible: Bool = true
    @State private var pageContentOffsetY: CGFloat = 0
    @State private var pendingPageTransitionWorkItem: DispatchWorkItem? = nil
    @State private var pageTransitionID = UUID()
    /// Keep controls measurement changes from reflowing the departing scroll view.
    @State private var departingPageControlsHeight: CGFloat? = nil
    @State private var isGlobalSideMenuOpen: Bool = false
    // Set while a Study Topic's detail view is open, so the global edge-swipe
    // gesture below yields to that screen's own swipe-to-go-back gesture.
    @State private var isStudyTopicDetailVisible: Bool = false
    @State private var isInsightLibraryVisible: Bool = false
    @State private var isSettingsDetailVisible: Bool = false
    @State private var isConversationCanvasMode: Bool = false
    @State private var globalInsightsContextCardState = ContextCardState()
    @State private var sideMenuConversations: [InquiryConversation] = []
    @State private var sideMenuActiveConversationID: UUID? = nil
    @State private var sideMenuCurrentTitle: String = "New Conversation"
    /// Changes only when sidebar content changes. The live drag offset must not
    /// force the menu's complete row hierarchy to be rebuilt every frame.
    @State private var sideMenuRenderVersion = 0
    @State private var requestedConversationID: UUID? = nil
    @State private var requestedTopicID: UUID? = nil
    @State private var selectedStudyTopicID: UUID? = nil
    @State private var insightConversationQuoteRequest: InsightConversationQuoteRequest? = nil
    @State private var studyTopicTreeSelectionRequest: StudyTopicTreeSelectionRequest? = nil
    /// Consumed requests stay consumed when the conversation page is recreated.
    @State private var newConversationRequests = NewConversationRequests()
    @State private var deletedConversationID: UUID? = nil
    @State private var colorSchemeOverride: ColorScheme? = nil
    @AppStorage(SettingsStorageKey.conversationBackground) private var conversationBackground: CanvasBackgroundOption = .system
    @AppStorage(SettingsStorageKey.insightTreeBackground) private var insightTreeBackground: CanvasBackgroundOption = .system
    @State private var requestedForkConcept: ConceptDefinition? = nil
    @EncryptedStringStorage("aquinas.settings.userName") private var userName: String = ""
    @EncryptedStringStorage(SettingsStorageKey.customInstructions) private var customInstructions: String = ""
    @AppStorage(SettingsStorageKey.defaultStartScreen)
    private var defaultStartScreen: DefaultStartScreenOption = .home
    @AppStorage(SettingsStorageKey.appLock) private var appLockEnabled = false
    @AppStorage(SettingsStorageKey.appLockGracePeriod)
    private var appLockGracePeriod: AppLockGracePeriodOption = .immediately
    @AppStorage(SettingsStorageKey.conversationTitles)
    private var conversationTitlePolicy: ConversationTitleOption = .automatic
    @State private var globalInsightSelectionRequest: Int = 0
    /// Set when returning to the global Insight Tree after removing a quoted Insight's chip
    /// from a conversation's composer — the tree hovers/selects this Insight on appear.
    @State private var globalInsightRestoreSelectionID: UUID? = nil
    @State private var globalInsightClearSelectionRequest: Int = 0
    @State private var globalInsightDismissHoverRequest: Int = 0
    @State private var globalInsightCreateConceptRequest: Int = 0
    @State private var globalInsightStudyRequest: Int = 0
    @State private var globalInsightStudyExitRequest: Int = 0
    @State private var globalInsightIsStudyMode: Bool = false
    @State private var globalInsightStudyToolsToggleRequest: Int = 0
    @State private var globalInsightStudyToolsActive: Bool = false
    @State private var globalInsightStudyBranchCount: Int = 2
    @State private var globalInsightStudyBranchConfirmRequest: Int = 0
    @State private var globalInsightPromotedIDs: [UUID] =
        GlobalInsightPromotedIDsStore.load()
    @State private var globalInsightInquireConnectionRequest: Int = 0
    @State private var globalInsightMidpointEnterRequest: Int = 0
    @State private var globalInsightMidpointCenterRequest: Int = 0
    @State private var globalInsightMidpointPlaceRequest: Int = 0
    @State private var globalInsightHasCanvasHover: Bool = false
    @State private var globalInsightHasInsightHover: Bool = false
    @State private var globalInsightSelectedItemCount: Int = 0
    @State private var globalInsightQuoteTarget: ConceptDefinition? = nil
    @State private var isGlobalInsightAskMode: Bool = false
    @State private var globalInsightExistingConversationTarget: ConceptDefinition? = nil
    @State private var libraryExistingConversationTarget: ConceptDefinition? = nil
    @State private var clippedPassages: [ConceptDefinition] = ClippedPassageStore.load()
    @State private var globalInsightIsMidpointMode: Bool = false
    @State private var globalInsightIsGenerating: Bool = false
    @State private var globalInsightSelectedPersonality: String = "Balanced"
    @State private var globalInsightIsPersonalityMenuOpen: Bool = false
    @State private var globalInsightHighlightedBridge: (UUID, UUID)? = nil
    @State private var globalInsightHighlightRequest: Int = 0
    @State private var globalInsightIsSearchActive: Bool = false
    @State private var globalInsightSearchQuery: String = ""
    @State private var globalInsightSearchResultIndex: Int = 0
    @State private var globalInsightSearchResultCount: Int = 0
    @State private var globalInsightSearchPreviousRequest: Int = 0
    @State private var globalInsightSearchNextRequest: Int = 0
    /// Shell-owned so model work and its popup survive page navigation.
    @State private var modelTasks: ModelTaskQueue
    @State private var modelTasksPopupState = ModelTasksPopupState()
    /// Reported up by `StudyTopicsView` so the global Model Controls bar can render its pill
    /// while that page's own selection/canvas/confirmation state stays owned locally there.
    @State private var studyTopicsControls = StudyTopicsPageControls()
    @State private var modelCompletionNotifications = ModelCompletionNotificationCenter()
    @State private var pendingPageReturnAction: (() -> Void)?
    @State private var questionOfTheDay = HomeQuestionOfTheDayStore.loadPending()
    @State private var homeLooseThread: LooseThreadCard? = nil
    @State private var homeTodayInHistory: TodayInHistoryCard? = nil
    @State private var homeGlossedTerm: GlossedTermCard? = nil
    @State private var homeYourQuote: YourQuoteCard? = nil
    @State private var conversationNodeFocusRequest: ConversationNodeFocusRequest? = nil
    @State private var dailyQuestionRefreshTask: Task<Void, Never>? = nil
    @State private var dailyQuestionGenerationRetryNotBefore = Date.distantPast
    @State private var isDailyQuestionGenerationErrorPresented: Bool = false
    @AppStorage("aquinas.settings.conversationFontSize") private var conversationFontSize: ConversationFontSizeOption = .medium
    @AppStorage(SettingsStorageKey.conversationTextAlignment) private var conversationTextAlignment: ConversationTextAlignmentOption = .left
    @AppStorage("aquinas.settings.inputFont") private var inputFont: ConversationFontOption = .serif
    @AppStorage("aquinas.settings.responseFont") private var responseFont: ConversationFontOption = .serif
    @AppStorage("aquinas.settings.conversationPersonality") private var conversationPersonality: ConversationPersonality = .default

    // MARK: - Constants

    let canvasColor = AngroveTheme.Colors.canvas
    private let pageFadeDuration: TimeInterval = 0.25
    private let pageFadePauseDuration: TimeInterval = 0.15
    private let pageTransitionOffset: CGFloat = 8

    init() {
        Self.migrateConversationTextAlignmentPreferenceIfNeeded()
        _modelTasks = State(initialValue: ModelTaskQueue())
    }

    init(modelTasks: ModelTaskQueue) {
        Self.migrateConversationTextAlignmentPreferenceIfNeeded()
        _modelTasks = State(initialValue: modelTasks)
    }

    private static func migrateConversationTextAlignmentPreferenceIfNeeded() {
        let defaults = PrivatePreferences.standard
        guard defaults.object(forKey: SettingsStorageKey.conversationTextAlignment) == nil,
              let legacyRawValue = defaults.string(forKey: SettingsStorageKey.legacyResponseTextAlignment),
              let legacyAlignment = ConversationTextAlignmentOption(rawValue: legacyRawValue) else {
            return
        }
        defaults.set(legacyAlignment.rawValue, forKey: SettingsStorageKey.conversationTextAlignment)
    }

    // MARK: - Derived State

    private var rootSafeAreaColor: Color {
        activePage == .conversation && isConversationCanvasMode
            ? AngroveTheme.Colors.canvas
            : canvasColor
    }

    private var newInsightsCount: Int {
        let seenIDs = InsightDiscoveryStore.loadSeenInsightIDs()
        return collectedDefinitions.filter { !seenIDs.contains($0.id) }.count
    }

    private var globalInsightContextWordCount: Int {
        let text = globalTreeInsights
            .flatMap { [$0.word, $0.meaning, $0.example] }
            .joined(separator: " ")
        return AngroveContextBudget.estimatedTokenCount(in: text)
    }

    private var usesLandscapeInsightSplit: Bool {
        displayedPage == .insights && verticalSizeClass == .compact
    }

    // MARK: - Navigation Actions

    private func presentGlobalSideMenu() {
        dismissKeyboard()
        SideMenuEntrance.prepareOpening()
        withAnimation(.springStandard) {
            isGlobalSideMenuOpen = true
        }
    }

    /// Content links can take the reader away from their current page. Keep one explicit
    /// return action, independent of the destination page's own confirmation controls.
    private func redirect(to page: AppPage) {
        guard activePage != page else { return }
        // Home is a hub: its entry points do not need a return notification.
        guard activePage != .home else {
            navigateWithoutReturn(to: page)
            return
        }
        let origin = activePage
        let conversationID = sideMenuActiveConversationID
        let topicID = selectedStudyTopicID
        let libraryRequest = libraryNavigationRequest
        modelCompletionNotifications.dismissPageReturn()
        pendingPageReturnAction = {
            guard activePage == page else { return }
            modelCompletionNotifications.schedulePageReturn(
                title: String(localized: "Return to \(origin.returnTitle)"),
                returnPage: origin
            ) {
                if origin == .conversation { requestedConversationID = conversationID }
                if origin == .studyTopics { requestedTopicID = topicID }
                if origin == .library { libraryNavigationRequest = libraryRequest }
                navigateWithoutReturn(to: origin)
            }
        }
        activePage = page
    }

    private func navigateWithoutReturn(to page: AppPage) {
        pendingPageReturnAction = nil
        modelCompletionNotifications.dismissPageReturn()
        activePage = page
    }

    private func schedulePendingPageReturn() {
        let action = pendingPageReturnAction
        pendingPageReturnAction = nil
        action?()
    }

    private func openModelTaskPage(_ task: ModelTaskSnapshot) {
        let page: AppPage
        switch task.originPage {
        case .home:
            page = .home
        case .conversation:
            page = .conversation
        case .openConversations:
            page = .openConversations
        case .settings:
            page = .settings
        case .insights:
            page = .insights
        case .studyTopics:
            page = .studyTopics
        }

        modelTasksPopupState.reset()
        if page == .conversation, let conversationID = task.conversationID {
            requestedConversationID = conversationID
        }
        guard activePage != page else { return }
        redirect(to: page)
    }

    private func postConversationCompletionNotificationIfNeeded(
        for task: ModelTaskSnapshot
    ) {
        guard case .userQuestion(let branchID, let responseIndex) = task.kind,
              let conversationID = task.conversationID else {
            return
        }

        let isViewingCompletedConversation = activePage == .conversation
            && sideMenuActiveConversationID == conversationID
        guard !isViewingCompletedConversation else { return }

        let conversation = CurrentConversationsStore.load()?.conversations.first(where: {
            $0.id == conversationID
        }) ?? sideMenuConversations.first(where: { $0.id == conversationID })
        let completedQuestion = conversation?
            .branches
            .first(where: { $0.id == branchID })
            .flatMap { branch in
                branch.activeChatBlocks
                    .prefix(min(responseIndex, branch.activeChatBlocks.count))
                    .reversed()
                    .compactMap { block -> String? in
                        guard case .user(let question, _, _) = block else { return nil }
                        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? nil : trimmed
                    }
                    .first
                    ?? {
                        let trimmed = branch.topQuestionText.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        return trimmed.isEmpty ? nil : trimmed
                    }()
            }
        let completedResponse = conversation?
            .branches
            .first(where: { $0.id == branchID })
            .flatMap { branch -> String? in
                guard branch.activeChatBlocks.indices.contains(responseIndex),
                      case .text(let response) = branch.activeChatBlocks[responseIndex] else {
                    return nil
                }
                let preview = AngroveSystemNotifications.responsePreview(from: response)
                return preview.isEmpty ? nil : preview
            }
        let fallbackTitle = conversation?.title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let notificationTitle = completedQuestion
            ?? fallbackTitle.flatMap { $0.isEmpty ? nil : $0 }
            ?? "Answer ready"
        let conversationTitle = fallbackTitle.flatMap { $0.isEmpty ? nil : $0 }
            ?? "Angrove"

        modelCompletionNotifications.post(
            title: notificationTitle,
            systemNotificationTitle: conversationTitle,
            systemNotificationBody: completedResponse ?? notificationTitle
        ) {
            requestedConversationID = conversationID
            redirect(to: .conversation)
        }
    }

    // MARK: - Page Views

    /// Publishes the shell-owned pages' controls to the app's single `ModelControlsHost`. These
    /// views render nothing themselves; the conversation, the Library reader, and Study Topic
    /// trees publish their own (higher-priority) controls from inside their pages.
    @ViewBuilder private func globalModelControlsBar(
        usesLandscapeInsightSplit: Bool
    ) -> some View {
        switch displayedPage {
        case .home:
            PageModelControls(
                modelTasks: modelTasks,
                popupState: modelTasksPopupState,
                actionTitle: "New Conversation",
                action: {
                    newConversationRequests.submit()
                    redirect(to: .conversation)
                },
                surfaceID: "home",
                extraFade: (height: 350, opacity: 1)
            )
        case .conversation:
            EmptyView()
        case .library:
            if !isLibraryReaderVisible {
                PageModelControls(
                    modelTasks: modelTasks,
                    popupState: modelTasksPopupState,
                    surfaceID: "library"
                )
            }
        case .openConversations:
            PageModelControls(
                modelTasks: modelTasks,
                popupState: modelTasksPopupState,
                actionTitle: "New Conversation",
                action: {
                    newConversationRequests.submit()
                    redirect(to: .conversation)
                },
                surfaceID: "open-conversations"
            )
        case .settings:
            PageModelControls(
                modelTasks: modelTasks,
                popupState: modelTasksPopupState,
                surfaceID: "settings"
            )
        case .insights:
            GlobalInsightsModelControls(
                showFilePicker: $showFilePicker,
                showPhotoPicker: $showPhotoPicker,
                showCamera: $showCamera,
                selectedPersonality: $globalInsightSelectedPersonality,
                isPersonalityMenuOpen: $globalInsightIsPersonalityMenuOpen,
                hasCanvasHover: globalInsightHasCanvasHover,
                hasCanvasInsightHover: globalInsightHasInsightHover,
                hasSelectedCanvasItems: globalInsightSelectedItemCount > 0,
                selectedCanvasItemCount: globalInsightSelectedItemCount,
                isMidpointMode: globalInsightIsMidpointMode,
                isStudyMode: globalInsightIsStudyMode,
                isStudyToolsActive: globalInsightStudyToolsActive,
                onToggleStudyTools: { globalInsightStudyToolsToggleRequest += 1 },
                studyBranchCount: globalInsightStudyBranchCount,
                onStudyBranchCountChange: { globalInsightStudyBranchCount = $0 },
                onStudyBranchConfirm: { globalInsightStudyBranchConfirmRequest += 1 },
                isCanvasInsightLoading: globalInsightIsGenerating,
                modelStatusOverride: isGlobalTreeReconciling
                    ? String(localized: "Mapping...")
                    : nil,
                contextWordCount: globalInsightContextWordCount,
                modelTasks: modelTasks,
                modelTasksPopupState: modelTasksPopupState,
                searchText: $globalInsightSearchQuery,
                isSearchActive: $globalInsightIsSearchActive,
                searchResultIndex: globalInsightSearchResultIndex,
                searchResultCount: globalInsightSearchResultCount,
                onSelectCanvasItem: { globalInsightSelectionRequest += 1 },
                onCreateCanvasConcept: { globalInsightCreateConceptRequest += 1 },
                onStudyCanvasInsight: { globalInsightStudyRequest += 1 },
                onInquireConnection: { globalInsightInquireConnectionRequest += 1 },
                onQuoteCanvasItem: {
                    guard globalInsightQuoteTarget != nil else { return }
                    withAnimation(.springQuick) {
                        isGlobalInsightAskMode = true
                    }
                },
                usesCanvasAskFlow: true,
                isCanvasAskMode: isGlobalInsightAskMode,
                onAskInNewConversation: askGlobalInsightInNewConversation,
                onAskInExistingConversation: {
                    guard let target = globalInsightQuoteTarget else { return }
                    globalInsightExistingConversationTarget = target
                },
                onCancelCanvasAsk: {
                    withAnimation(.springQuick) {
                        isGlobalInsightAskMode = false
                    }
                },
                onMidpointConcepts: { globalInsightMidpointEnterRequest += 1 },
                onMidpointCenter: { globalInsightMidpointCenterRequest += 1 },
                onMidpointPlace: { globalInsightMidpointPlaceRequest += 1 },
                onSearchPrevious: { globalInsightSearchPreviousRequest += 1 },
                onSearchNext: { globalInsightSearchNextRequest += 1 },
                onSearchActivated: {
                    globalInsightsContextCardState.reset()
                    modelTasksPopupState.reset()
                    globalInsightDismissHoverRequest += 1
                },
                onClearCanvasSelection: { globalInsightClearSelectionRequest += 1 },
                onContextWillOpen: { globalInsightDismissHoverRequest += 1 },
                confirmationTitle: isGlobalTreeUpdatePromptVisible
                    ? "Update Global Insights Tree?"
                    : nil,
                onConfirmUpdate: updateGlobalInsightTree,
                onDeclineUpdate: dismissGlobalInsightTreeUpdate,
                contextCard: globalInsightsContextCardState,
                maxWidth: usesLandscapeInsightSplit ? 420 : nil,
                alignment: usesLandscapeInsightSplit ? .trailing : .center
            )
        case .studyTopics:
            if studyTopicsControls.isVisible {
                PageModelControls(
                    modelTasks: modelTasks,
                    popupState: modelTasksPopupState,
                    actionTitle: studyTopicsControls.actionTitle,
                    secondaryActionTitle: studyTopicsControls.secondaryActionTitle,
                    secondaryAction: studyTopicsControls.secondaryAction,
                    confirmationTitle: studyTopicsControls.confirmationTitle,
                    onConfirm: studyTopicsControls.onConfirm,
                    onDecline: studyTopicsControls.onDecline,
                    action: studyTopicsControls.action,
                    surfaceID: "study-topics"
                )
            }
        }
    }

    /// Kept out of `body`'s modifier chain, which is at the type checker's limit.
    private func handleGlobalInsightHoverChange(_ isHoveringInsight: Bool) {
        guard isHoveringInsight else { return }
        withAnimation(.springStandard) {
            modelTasksPopupState.reset()
        }
    }

    /// The Insights page's side-menu button; in Study it grows an Exit back to the tree.
    private var globalInsightMenuControls: some View {
        HStack(spacing: 8) {
            SideMenuTriggerButton {
                dismissKeyboard()
                SideMenuEntrance.prepareOpening()
                withAnimation(.springStandard) {
                    isGlobalSideMenuOpen = true
                }
            }
            if globalInsightIsStudyMode {
                StudyExitButton { globalInsightStudyExitRequest += 1 }
                    .transition(.studyExitGrow)
            }
        }
        .animation(.springStandard, value: globalInsightIsStudyMode)
    }

    @ViewBuilder private var insightTreePage: some View {
        InsightTreeView(
            insights: globalTreeInsights,
            selectionRequest: globalInsightSelectionRequest,
            clearSelectionRequest: globalInsightClearSelectionRequest,
            dismissHoverRequest: globalInsightDismissHoverRequest,
            createConceptRequest: globalInsightCreateConceptRequest,
            studyRequest: globalInsightStudyRequest,
            studyExitRequest: globalInsightStudyExitRequest,
            studyToolsToggleRequest: globalInsightStudyToolsToggleRequest,
            studyBranchCount: globalInsightStudyBranchCount,
            studyBranchConfirmRequest: globalInsightStudyBranchConfirmRequest,
            onStudyModeChange: { globalInsightIsStudyMode = $0 },
            onStudyToolsActiveChange: { globalInsightStudyToolsActive = $0 },
            onStudyBranchCountChange: { globalInsightStudyBranchCount = $0 },
            restoreSelectedInsightID: globalInsightRestoreSelectionID,
            promotedInsightIDs: globalInsightPromotedIDs,
            onRemoveInsight: { def in
                withAnimation {
                    collectedDefinitions.removeAll { $0.id == def.id }
                    globalTreeInsights.removeAll { $0.id == def.id }
                }
                GlobalInsightTreeStore.save(globalTreeInsights)
                acknowledgeGlobalTreeEdit(removing: [def.id])
            },
            onRestoreInsight: { def in
                withAnimation {
                    if !collectedDefinitions.contains(where: { $0.id == def.id }) {
                        collectedDefinitions.append(def)
                    }
                    if !globalTreeInsights.contains(where: { $0.id == def.id }) {
                        globalTreeInsights.append(def)
                    }
                }
                GlobalInsightTreeStore.save(globalTreeInsights)
                acknowledgeGlobalTreeEdit(adding: [def.id])
            },
            onForkInsight: { def in
                requestedForkConcept = def
                withAnimation(.springStandard) {
                    redirect(to: .conversation)
                }
            },
            onQuoteInsight: { insight in
                globalInsightQuoteTarget = insight
                if insight == nil { isGlobalInsightAskMode = false }
            },
            onSelectionStateChange: { globalInsightHasCanvasHover = $0 },
            onInsightSelectionStateChange: { globalInsightHasInsightHover = $0 },
            onSelectedCanvasItemCountChange: { globalInsightSelectedItemCount = $0 },
            onPromotedInsightIDsChange: {
                globalInsightPromotedIDs = $0
                GlobalInsightPromotedIDsStore.save($0)
            },
            // Every item in the Global Insight Tree is, by definition, something the user chose
            // to save. Keep the bookmark state tied to the tree snapshot rather than the broader
            // collected-definition cache, which can also contain pending updates.
            savedConceptIDs: Set(globalTreeInsights.map(\.id)),
            onToggleSavedConcept: { concept in
                withAnimation(.springBouncy) {
                    collectedDefinitions.removeAll { $0.id == concept.id }
                    // Un-saving must disappear from the global tree's persisted snapshot too;
                    // otherwise relaunching reloads the stale insight and the bookmark returns.
                    globalTreeInsights.removeAll { $0.id == concept.id }
                }
                GlobalInsightTreeStore.save(globalTreeInsights)
                acknowledgeGlobalTreeEdit(removing: [concept.id])
            },
            onBookmarkConcepts: { concepts in
                withAnimation(.springBouncy) {
                    for concept in concepts {
                        if !collectedDefinitions.contains(where: { $0.id == concept.id }) {
                            collectedDefinitions.append(concept)
                        }
                        if !globalTreeInsights.contains(where: { $0.id == concept.id }) {
                            globalTreeInsights.append(concept)
                        }
                    }
                }
                GlobalInsightTreeStore.save(globalTreeInsights)
                acknowledgeGlobalTreeEdit(adding: concepts.map(\.id))
            },
            inquireConnectionRequest: globalInsightInquireConnectionRequest,
            onInquireConnectionConcepts: { concepts in
                guard let first = concepts.first else { return }
                requestedForkConcept = first
                withAnimation(.springStandard) {
                    redirect(to: .conversation)
                }
            },
            midpointEnterRequest: globalInsightMidpointEnterRequest,
            midpointCenterRequest: globalInsightMidpointCenterRequest,
            midpointPlaceRequest: globalInsightMidpointPlaceRequest,
            searchQuery: globalInsightSearchQuery,
            searchPreviousRequest: globalInsightSearchPreviousRequest,
            searchNextRequest: globalInsightSearchNextRequest,
            onSearchResultsChange: { current, total in
                globalInsightSearchResultIndex = current
                globalInsightSearchResultCount = total
            },
            highlightedInsightPair: globalInsightHighlightedBridge,
            highlightPairRequest: globalInsightHighlightRequest,
            startsMidpointForHighlightedPair: true,
            onMidpointModeChange: { globalInsightIsMidpointMode = $0 },
            onMidpointGeneratingChange: { globalInsightIsGenerating = $0 },
            inputFont: inputFont,
            conversationFontSize: conversationFontSize,
            showQuestionBar: false,
            modelTasks: modelTasks,
            model: angroveModel,
            embeddingProvider: embeddingProvider
        )
        .background(canvasColor)
        .canvasAppearance(insightTreeBackground)
        // Top/side notch bleed only — keyboard safe area and the global Model Controls bar's
        // bottom inset (applied on an ancestor container) must still be respected, or the
        // docked Insight card renders behind the bar instead of stacking above it.
        .ignoresSafeArea(.container, edges: [.top, .horizontal])
        .sheet(item: $globalInsightExistingConversationTarget) { insight in
            InsightConversationPickerSheet(
                title: "Existing Conversations",
                searchPrompt: "Search Conversations",
                emptyMessage: "There are no matching conversations yet.",
                conversations: sideMenuConversations,
                activeConversationID: sideMenuActiveConversationID,
                savedInsights: collectedDefinitions,
                onSelect: { conversation in
                    globalInsightExistingConversationTarget = nil
                    isGlobalInsightAskMode = false
                    insightConversationQuoteRequest = InsightConversationQuoteRequest(
                        conversationID: conversation.id,
                        insight: insight
                    )
                    redirect(to: .conversation)
                },
                onCancel: {
                    globalInsightExistingConversationTarget = nil
                }
            )
            .presentationDetents([.height(520), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(AngroveTheme.Colors.canvas)
        }
        .sheet(item: $libraryExistingConversationTarget) { quote in
            InsightConversationPickerSheet(
                title: "Existing Conversations",
                searchPrompt: "Search Conversations",
                emptyMessage: "There are no matching conversations yet.",
                conversations: sideMenuConversations,
                activeConversationID: sideMenuActiveConversationID,
                savedInsights: collectedDefinitions,
                onSelect: { conversation in
                    libraryExistingConversationTarget = nil
                    insightConversationQuoteRequest = InsightConversationQuoteRequest(
                        conversationID: conversation.id,
                        insight: quote
                    )
                    activePage = .conversation
                },
                onCancel: { libraryExistingConversationTarget = nil }
            )
            .presentationDetents([.height(520), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(AngroveTheme.Colors.canvas)
        }
    }

    /// Extracted so the compiler doesn't time out type-checking a single large expression.
    @ViewBuilder private var conversationView: some View {
        CurrentConversationView(
            onOpenMenu: presentGlobalSideMenu,
            onCanvasModeChange: { isConversationCanvasMode = $0 },
            onInsightLibraryVisibilityChange: { isInsightLibraryVisible = $0 },
            onRequestConversationPage: {
                redirect(to: .conversation)
            },
            onReturnToStudyTopicTree: { request in
                requestedTopicID = request.topicID
                studyTopicTreeSelectionRequest = request
                navigateWithoutReturn(to: .studyTopics)
            },
            onReturnToGlobalInsights: { insight in
                globalInsightRestoreSelectionID = insight.id
                navigateWithoutReturn(to: .insights)
            },
            onQuestionOfTheDayAnswered: markQuestionOfTheDayAnswered,
            onTodayInHistoryAnswered: markTodayInHistoryAnswered,
            collectedDefinitions: $collectedDefinitions,
            clippedPassages: $clippedPassages,
            sideMenuConversations: $sideMenuConversations,
            sideMenuCurrentTitle: $sideMenuCurrentTitle,
            sideMenuActiveConversationID: $sideMenuActiveConversationID,
            requestedConversationID: $requestedConversationID,
            newConversationRequests: newConversationRequests,
            deletedConversationID: $deletedConversationID,
            requestedForkConcept: $requestedForkConcept,
            insightConversationQuoteRequest: $insightConversationQuoteRequest,
            conversationNodeFocusRequest: $conversationNodeFocusRequest,
            conversationFontSize: conversationFontSize,
            conversationTextAlignment: conversationTextAlignment,
            inputFont: inputFont,
            responseFont: responseFont,
            conversationTitlePolicy: conversationTitlePolicy,
            conversationPersonality: $conversationPersonality,
            isPageVisible: activePage == .conversation,
            modelTasks: modelTasks,
            modelTasksPopupState: modelTasksPopupState,
            uploadedFiles: $uploadedFiles,
            showFilePicker: $showFilePicker
        )
    }

    private var globalSideMenu: AnyView {
        AnyView(AngroveSideMenu(
            currentTitle: sideMenuCurrentTitle,
            conversations: sideMenuConversations,
            activeConversationID: sideMenuActiveConversationID,
            activePage: activePage,
            modelTasks: modelTasks,
            selectedPersonality: conversationPersonality.displayName,
            isPresented: isGlobalSideMenuOpen,
            renderVersion: sideMenuRenderVersion,
            onNewChat: { dismissGlobalSideMenu { newConversationRequests.submit(); navigateWithoutReturn(to: .conversation) } },
            onSelectConversation: { conversation in dismissGlobalSideMenu { requestedConversationID = conversation.id; navigateWithoutReturn(to: .conversation) } },
            onRenameConversation: { conversation, title in renameConversation(conversation, to: title) },
            onPinConversation: { pinConversation($0) },
            onUnpinConversation: { unpinConversation($0) },
            onAddConversationToStudyTopic: { attachConversation($0, toStudyTopic: $1) },
            onRemoveConversationFromStudyTopic: { detachConversationFromStudyTopic($0) },
            onDeleteConversation: { deleteConversation($0) },
            newInsightsCount: newInsightsCount,
            onOpenHome: { dismissGlobalSideMenu { navigateWithoutReturn(to: .home) } },
            onOpenLibrary: { dismissGlobalSideMenu { navigateWithoutReturn(to: .library) } },
            onOpenConversations: { dismissGlobalSideMenu { navigateWithoutReturn(to: .openConversations) } },
            onOpenInsights: { dismissGlobalSideMenu { navigateWithoutReturn(to: .insights) } },
            onOpenStudyTopics: { dismissGlobalSideMenu { requestedTopicID = nil; navigateWithoutReturn(to: .studyTopics) } },
            onSelectStudyTopic: { topic in dismissGlobalSideMenu { requestedTopicID = topic.id; navigateWithoutReturn(to: .studyTopics) } },
            onOpenSettings: { dismissGlobalSideMenu { navigateWithoutReturn(to: .settings) } },
            onClose: { dismissGlobalSideMenu() }
        )
        .equatable())
    }

    // MARK: - Body

    private var visibleCanvasBackground: CanvasBackgroundOption {
        switch displayedPage {
        case .conversation: isConversationCanvasMode ? insightTreeBackground : conversationBackground
        case .insights: insightTreeBackground
        case .studyTopics: studyTopicsControls.isCanvasVisible ? insightTreeBackground : .system
        default: .system
        }
    }

    var body: some View {
        BootPresentation(isReady: isStartupReady) {
            shellObservers(shellBody)
        }
        .preferredColorScheme(colorSchemeOverride)
    }

    /// The trailing observers, split out of the main modifier chain, which is past the type
    /// checker's limit in one piece.
    private func shellObservers<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in handleScenePhaseChange(phase) }
            .onChange(of: appLockEnabled) { _, isEnabled in
                appLockController.settingDidChange(isEnabled: isEnabled)
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.didReceiveMemoryWarningNotification
                )
            ) { _ in
                modelTasks.handleMemoryPressure()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: ProcessInfo.thermalStateDidChangeNotification
                )
            ) { _ in
                modelTasks.updateThermalPressure(
                    ProcessInfo.processInfo.thermalState.modelRuntimePressure
                )
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .angroveConversationStoreDidImport
                )
            ) { _ in
                loadShellConversationState()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .openGroundingSourceInLibrary)
                    .compactMap { $0.object as? LibraryNavigationRequest }
            ) { request in
                redirect(to: .library)
                libraryNavigationRequest = request
            }
            .onChange(of: collectedDefinitions) { _, newValue in handleCollectedDefinitionsChange(newValue) }
    }

    private var shellBody: some View {
        AnyView(GeometryReader { _ in
            ZStack(alignment: .top) {
                rootSafeAreaColor
                    .canvasAppearance(visibleCanvasBackground)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.2), value: isConversationCanvasMode)

                VStack(spacing: 0) {
                    ZStack {
                        // Do not keep the UIKit-backed editor and its geometry preferences in the
                        // layout tree while another page is visible. An opacity-only hiding path
                        // left that tree active and could drive a runaway AttributeGraph update
                        // loop on device. Model work itself is owned by the shell-level queue.
                        if displayedPage == .conversation {
                            conversationView
                            .environment(\.isConversationPageDeparting, activePage != .conversation)
                            .transaction { transaction in
                                if activePage != .conversation {
                                    transaction.animation = nil
                                    transaction.disablesAnimations = true
                                }
                            }
                            .compositingGroup()
                            .opacity(isPageContentVisible ? 1 : 0)
                            .offset(y: pageContentOffsetY)
                        }

                        Group {
                            switch displayedPage {
                            case .home:
                                HomeDashboardView(
                                    conversations: sideMenuConversations,
                                    activeConversationID: sideMenuActiveConversationID,
                                    savedInsights: collectedDefinitions,
                                    userName: userName,
                                    questionOfTheDay: questionOfTheDay,
                                    looseThread: homeLooseThread,
                                    todayInHistory: homeTodayInHistory,
                                    glossedTerm: homeGlossedTerm,
                                    yourQuote: homeYourQuote,
                                    onOpenMenu: presentGlobalSideMenu,
                                    onSelectConversation: { conversation in
                                        requestedConversationID = conversation.id
                                        redirect(to: .conversation)
                                    },
                                    onStartQuestion: startQuestionOfTheDay,
                                    onOpenInsightBridge: { firstID, secondID in
                                        globalInsightHighlightedBridge = (firstID, secondID)
                                        globalInsightHighlightRequest += 1
                                        redirect(to: .insights)
                                    },
                                    onFocusNode: { nodeID in
                                        guard let card = homeLooseThread,
                                              card.nodeID == nodeID else { return }
                                        conversationNodeFocusRequest = ConversationNodeFocusRequest(
                                            conversationID: card.conversationID,
                                            nodeID: nodeID
                                        )
                                        redirect(to: .conversation)
                                    },
                                    onStartTodayInHistory: { card in
                                        newConversationRequests.submit(NewConversationRequest(
                                            question: card.title,
                                            eyebrow: "TODAY IN HISTORY",
                                            promptContext: card.taggedPromptContext,
                                            subtitle: card.description
                                        ))
                                        redirect(to: .conversation)
                                    },
                                    onRefresh: refreshPersistedContent,
                                    onLoadHomeSections: {
                                        Task { await refreshHomeSections() }
                                    }
                                )
                            case .conversation:
                                Color.clear
                                    .allowsHitTesting(false)
                            case .library:
                                libraryPage
                            case .openConversations:
                                OpenConversationsView(
                                    conversations: sideMenuConversations,
                                    activeConversationID: sideMenuActiveConversationID,
                                    savedInsights: $collectedDefinitions,
                                    modelTasks: modelTasks,
                                    modelTasksPopupState: modelTasksPopupState,
                                    onOpenMenu: presentGlobalSideMenu,
                                    onSelectConversation: { conversation in
                                        requestedConversationID = conversation.id
                                        redirect(to: .conversation)
                                    },
                                    onNewChat: {
                                        newConversationRequests.submit()
                                        redirect(to: .conversation)
                                    },
                                    onRenameConversation: { conversation, title in
                                        renameConversation(conversation, to: title)
                                    },
                                    onPinConversation: { conversation in
                                        pinConversation(conversation)
                                    },
                                    onUnpinConversation: { conversation in
                                        unpinConversation(conversation)
                                    },
                                    onAddConversationToStudyTopic: { conversation, topicID in
                                        attachConversation(conversation, toStudyTopic: topicID)
                                    },
                                    onRemoveConversationFromStudyTopic: { conversation in
                                        detachConversationFromStudyTopic(conversation)
                                    },
                                    onDeleteConversation: { conversation in
                                        deleteConversation(conversation)
                                    },
                                    onRefresh: refreshPersistedContent
                                )
                            case .settings:
                                SettingsView(
                                    colorSchemeOverride: $colorSchemeOverride,
                                    userName: $userName,
                                    customInstructions: $customInstructions,
                                    conversationFontSize: $conversationFontSize,
                                    conversationTextAlignment: $conversationTextAlignment,
                                    inputFont: $inputFont,
                                    responseFont: $responseFont,
                                    conversationPersonality: $conversationPersonality,
                                    collectedDefinitions: $collectedDefinitions,
                                    onOpenMenu: presentGlobalSideMenu,
                                    onDetailVisibilityChange: { isSettingsDetailVisible = $0 },
                                    onClearInsightTree: clearInsightTree
                                )
                            case .insights:
                                insightTreePage
                            case .studyTopics:
                                StudyTopicsView(
                                    conversations: sideMenuConversations,
                                    activeConversationID: sideMenuActiveConversationID,
                                    savedInsights: $collectedDefinitions,
                                    modelTasks: modelTasks,
                                    modelTasksPopupState: modelTasksPopupState,
                                    onOpenMenu: presentGlobalSideMenu,
                                    onSelectConversation: { conversation in
                                        requestedConversationID = conversation.id
                                        redirect(to: .conversation)
                                    },
                                    onNewChat: {
                                        newConversationRequests.submit()
                                        redirect(to: .conversation)
                                    },
                                    onNewChatInTopic: { topicID in
                                        newConversationRequests.submit(NewConversationRequest(topicID: topicID))
                                        redirect(to: .conversation)
                                    },
                                    onQuoteInsightIntoNewConversation: { insight, topicID in
                                        newConversationRequests.submit(NewConversationRequest(
                                            topicID: topicID,
                                            quote: NewConversationInsightQuoteRequest(insight: insight, topicID: topicID)
                                        ))
                                        redirect(to: .conversation)
                                    },
                                    onQuoteInsightIntoConversation: { conversation, insight, topicID in
                                        insightConversationQuoteRequest = InsightConversationQuoteRequest(
                                            topicID: topicID,
                                            conversationID: conversation.id,
                                            insight: insight
                                        )
                                        redirect(to: .conversation)
                                    },
                                    onAttachConversationToTopic: { conversation, topicID in
                                        attachConversation(conversation, toStudyTopic: topicID)
                                    },
                                    onRenameConversation: { conversation, title in
                                        renameConversation(conversation, to: title)
                                    },
                                    onPinConversation: { conversation in
                                        pinConversation(conversation)
                                    },
                                    onUnpinConversation: { conversation in
                                        unpinConversation(conversation)
                                    },
                                    onRemoveConversationFromStudyTopic: { conversation in
                                        detachConversationFromStudyTopic(conversation)
                                    },
                                    onDeleteConversation: { conversation in
                                        deleteConversation(conversation)
                                    },
                                    requestedTopicID: requestedTopicID,
                                    requestedTreeSelection: studyTopicTreeSelectionRequest,
                                    onConsumeTreeSelectionRequest: {
                                        studyTopicTreeSelectionRequest = nil
                                    },
                                    onRefresh: refreshPersistedContent,
                                    onDetailVisibilityChange: { isVisible in
                                        isStudyTopicDetailVisible = isVisible
                                    },
                                    onSelectedTopicChange: { selectedStudyTopicID = $0 },
                                    onControlsChange: { studyTopicsControls = $0 }
                                )
                            }
                        }
                        .opacity(displayedPage == .conversation ? 0 : 1)
                        .allowsHitTesting(displayedPage != .conversation)
                        .accessibilityHidden(displayedPage == .conversation)
                        .opacity(isPageContentVisible ? 1 : 0)
                        .offset(y: pageContentOffsetY)
                    }
                    // Matches the pages' canvas so the slide offset during page transitions
                    // doesn't reveal a differently tinted strip behind the page.
                    .background {
                        CanvasBackground(option: visibleCanvasBackground)
                            .canvasAppearance(visibleCanvasBackground)
                            .ignoresSafeArea()
                    }
                    .background {
                        globalModelControlsBar(usesLandscapeInsightSplit: usesLandscapeInsightSplit)
                    }
                    // The app's one Model Controls bar. It lives here — outside every page and the
                    // fade/offset applied to them — so it never swaps out; only the buttons the
                    // visible page publishes change inside it. The inset reserves its measured
                    // height so every page's content keeps the same bottom clearance.
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        Color.clear.frame(height: departingPageControlsHeight ?? modelControlsHeight)
                    }
                    .overlayPreferenceValue(ModelControlsPreferenceKey.self, alignment: .bottom) { configuration in
                        ModelControlsHost(configuration: configuration)
                            .canvasAppearance(visibleCanvasBackground)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                modelControlsHeight = height
                            }
                    }
                    .eraseToAnyView()
                }
                .sideMenuDragPresentation(
                    isPresented: $isGlobalSideMenuOpen,
                    activePage: activePage,
                    isStudyTopicDetailVisible: isStudyTopicDetailVisible,
                    isSettingsDetailVisible: isSettingsDetailVisible,
                    isBlocked: isInsightLibraryVisible,
                    onBeginDrag: dismissKeyboard,
                    onDismiss: { dismissGlobalSideMenu() },
                    menu: globalSideMenu
                )

                // Shared document picker used by the bottom plus button.
                .fileImporter(
                    isPresented: $showFilePicker,
                    allowedContentTypes: [.image, .pdf, .audio, .plainText],
                    allowsMultipleSelection: true
                ) { result in
                    switch result {
                    case .success(let urls):
                        withAnimation(.springLively) {
                            for url in urls {
                                let hasAccess = url.startAccessingSecurityScopedResource()
                                defer {
                                    if hasAccess {
                                        url.stopAccessingSecurityScopedResource()
                                    }
                                }

                                let data = try? Data(contentsOf: url)
                                let imageData = data.flatMap { UploadedFile.isImageData($0) ? $0 : nil }

                                uploadedFiles.append(
                                    UploadedFile(
                                        name: url.lastPathComponent,
                                        imageData: imageData,
                                        rotationDegrees: Double.random(in: -5...5)
                                    )
                                )
                            }
                        }
                    case .failure(let error):
                        print("Failed to select file: \(error.localizedDescription)")
                    }
                }
                // Shared photo picker used by the attachment menu.
                .photosPicker(
                    isPresented: $showPhotoPicker,
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 8,
                    matching: .images
                )
                .onChange(of: selectedPhotoItems) { oldValue, newValue in
                    guard !newValue.isEmpty else { return }

                    Task {
                        for item in newValue {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               UploadedFile.isImageData(data) {
                                await MainActor.run {
                                    withAnimation(.springLively) {
                                        uploadedFiles.append(
                                            UploadedFile(
                                                name: "Photo",
                                                imageData: data,
                                                rotationDegrees: Double.random(in: -5...5)
                                            )
                                        )
                                    }
                                }
                            }
                        }

                        await MainActor.run {
                            selectedPhotoItems.removeAll()
                        }
                    }
                }
                // Camera capture flow. Falls back gracefully if a camera is unavailable.
                .fullScreenCover(isPresented: $showCamera) {
                    CameraCaptureView { image in
                        if let data = image.jpegData(compressionQuality: 0.86) {
                            withAnimation(.springLively) {
                                uploadedFiles.append(
                                    UploadedFile(
                                        name: "Camera Photo",
                                        imageData: data,
                                        rotationDegrees: Double.random(in: -5...5)
                                    )
                                )
                            }
                        }
                    }
                    .ignoresSafeArea()
                }

                // ── Side-menu trigger, backdrop, and panel ────────────────────
                // These are direct ZStack siblings (not nested `.overlay()` calls)
                // so their zIndex is compared against the page content directly —
                // guarantees the panel renders above everything, including page
                // content that ignores the safe area (e.g. fade gradients).
                if activePage == .insights && !isGlobalSideMenuOpen {
                    globalInsightMenuControls
                        .canvasAppearance(insightTreeBackground)
                    .padding(.leading, 24)
                    .padding(.top, 24)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .zIndex(2)
                }

                if appLockEnabled,
                   appLockController.isLocked || scenePhase != .active {
                    AppLockGate(
                        isAuthenticating: appLockController.isAuthenticating,
                        errorMessage: appLockController.errorMessage,
                        onUnlock: appLockController.lockAndAuthenticate
                    )
                    .zIndex(2000)
                }

            }
            .ignoresSafeArea(.container, edges: .bottom)
        })
        .environment(
            \.modelCompletionNotifications,
            modelCompletionNotifications
        )
        .environment(\.openModelTaskPage, openModelTaskPage)
        .preferredColorScheme(colorSchemeOverride)
        .eraseToAnyView()
        .dailyQuestionGenerationAlert(
            isPresented: $isDailyQuestionGenerationErrorPresented,
            retry: {
                dailyQuestionGenerationRetryNotBefore = .distantPast
                scheduleDailyQuestionRefreshIfNeeded(minimumDelay: 0)
            }
        )
        .onAppear {
            // Personality selection is post-launch; without a control, keep every install on
            // the default voice rather than a value stored by an earlier build.
            conversationPersonality = .balanced
            modelTasks.setPersonality(conversationPersonality)
            modelTasks.setApplicationActive(scenePhase == .active)
            modelTasks.updateThermalPressure(
                ProcessInfo.processInfo.thermalState.modelRuntimePressure
            )
            loadShellConversationState()
            applyStartupDestinationIfNeeded()
            displayedPage = activePage
            isPageContentVisible = true
            pageContentOffsetY = 0
            appLockController.prepare(isEnabled: appLockEnabled)
            let savedInsights = InsightLibraryStore.load()
            if !savedInsights.isEmpty {
                collectedDefinitions = savedInsights
            }
            questionOfTheDay = HomeQuestionOfTheDayStore.loadPending()
            HomeQuestionOfTheDayStore.reloadWidgetTimeline()
            Task { @MainActor in
                await Task.yield()
                isStartupReady = true
                openPendingDailyQuestionLinkIfReady()
                scheduleDailyQuestionRefreshIfNeeded()
            }
        }
        .onOpenURL { url in
            guard DailyQuestionWidgetLink.matches(url) else { return }
            hasPendingDailyQuestionLink = true
            openPendingDailyQuestionLinkIfReady()
        }
        .onChange(of: activePage) { oldValue, newValue in handleActivePageChange(from: oldValue, to: newValue) }
        .onChange(of: modelTasks.isBusy) { _, _ in
            scheduleDailyQuestionRefreshIfNeeded()
        }
        // Mirrors CurrentConversationView's identical interlock for its own per-conversation
        // Insight Tree — the Global tree had the same "both open at once" gap since nothing here
        // reacted to a hover starting after the Model Tasks popup was already open.
        .onChange(of: globalInsightHasInsightHover) { _, isHoveringInsight in
            handleGlobalInsightHoverChange(isHoveringInsight)
        }
        .onChange(of: modelTasks.latestCompletedTask) { _, task in handleCompletedModelTask(task) }
        .onChange(of: conversationPersonality) { _, personality in
            modelTasks.setPersonality(personality)
        }
        .onChange(of: sideMenuConversations) { _, _ in handleSideMenuConversationsChange() }
        .onChange(of: collectedDefinitions) { _, _ in
            scheduleDailyQuestionRefreshIfNeeded()
        }
        .onChange(of: clippedPassages) { _, passages in
            ClippedPassageStore.save(passages)
        }
    }

    private var libraryPage: some View {
        LibraryView(
            onOpenMenu: presentGlobalSideMenu,
            modelTasks: modelTasks,
            modelTasksPopupState: modelTasksPopupState,
            onReaderVisibilityChange: { isLibraryReaderVisible = $0 },
            navigationRequest: libraryNavigationRequest,
            onAskInNewConversation: { quote in
                newConversationRequests.submit(NewConversationRequest(
                    quote: NewConversationInsightQuoteRequest(insight: quote)
                ))
                activePage = .conversation
            },
            onAskInExistingConversation: { libraryExistingConversationTarget = $0 },
            clippedPassages: clippedPassages,
            onRemoveClippedPassage: { passage in
                clippedPassages.removeAll { $0.id == passage.id }
            }
        )
    }

    // MARK: - Side Menu

    /// Closes the panel before changing the view behind it, so its contents
    /// remain visually stable for the full slide-out animation.
    private func dismissGlobalSideMenu(then action: @escaping () -> Void = {}) {
        guard isGlobalSideMenuOpen else {
            action()
            return
        }

        withAnimation(
            .springStandard,
            completionCriteria: .logicallyComplete
        ) {
            isGlobalSideMenuOpen = false
        } completion: {
            action()
        }
    }

    // MARK: - Daily Content

    private func startQuestionOfTheDay(_ dailyQuestion: HomeQuestionOfTheDay) {
        questionOfTheDay = dailyQuestion
        requestedConversationID = nil
        conversationNodeFocusRequest = nil
        newConversationRequests.submit(dailyQuestion.conversationRequest)
        dismissGlobalSideMenu {
            redirect(to: .conversation)
        }
    }

    private func openPendingDailyQuestionLinkIfReady() {
        guard isStartupReady, hasPendingDailyQuestionLink else { return }
        hasPendingDailyQuestionLink = false
        guard let savedQuestion = HomeQuestionOfTheDayStore.load(),
              HomeQuestionOfTheDay.isValidQuestionText(savedQuestion.question) else {
            activePage = .home
            return
        }
        startQuestionOfTheDay(savedQuestion)
    }

    private func markQuestionOfTheDayAnswered() {
        guard let questionOfTheDay else { return }
        HomeQuestionOfTheDayStore.save(questionOfTheDay.markingAnswered())
        withAnimation(.easeInOut(duration: 0.25)) {
            self.questionOfTheDay = nil
        }
        scheduleDailyQuestionRefreshIfNeeded()
    }

    private func markTodayInHistoryAnswered() {
        guard homeTodayInHistory != nil else { return }
        HomeTodayInHistoryStore.markAnswered()
        withAnimation(.easeInOut(duration: 0.25)) {
            homeTodayInHistory = nil
        }
    }

    private func scheduleDailyQuestionRefreshIfNeeded(
        minimumDelay: TimeInterval = 15
    ) {
        guard activePage != .conversation else {
            dailyQuestionRefreshTask?.cancel()
            dailyQuestionRefreshTask = nil
            return
        }
        guard scenePhase == .active,
              !modelTasks.isBusy else {
            dailyQuestionRefreshTask?.cancel()
            dailyQuestionRefreshTask = nil
            return
        }
        guard dailyQuestionRefreshTask == nil,
              !modelTasks.contains(where: {
                  $0.kind == .refreshQuestionOfTheDay
              }) else {
            return
        }

        let eligibilityDate = HomeQuestionOfTheDayStore.nextEligibleRefreshDate()
        let delay = max(
            minimumDelay,
            max(
                eligibilityDate.timeIntervalSinceNow,
                dailyQuestionGenerationRetryNotBefore.timeIntervalSinceNow
            )
        )
        dailyQuestionRefreshTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  activePage != .conversation,
                  scenePhase == .active,
                  !modelTasks.isBusy else {
                dailyQuestionRefreshTask = nil
                return
            }

            questionOfTheDay = HomeQuestionOfTheDayStore.loadPending()
            guard questionOfTheDay == nil,
                  HomeQuestionOfTheDayStore.isEligibleForRefresh() else {
                dailyQuestionRefreshTask = nil
                debugQuestionOfTheDayConsoleLog("refresh no longer eligible")
                return
            }
            guard let source = DailyQuestionSourceSelector.select(
                      conversations: sideMenuConversations,
                      savedInsights: collectedDefinitions
                  ) else {
                dailyQuestionRefreshTask = nil
                debugQuestionOfTheDayConsoleLog("no eligible source conversation")
                return
            }

            dailyQuestionRefreshTask = nil
            debugQuestionOfTheDayConsoleLog("enqueuing generation")
            modelTasks.enqueue(
                kind: .refreshQuestionOfTheDay,
                originPage: .home,
                priority: .background
            ) {
                let draft: DailyQuestionDraft
                do {
                    draft = try await angroveModel.generateQuestionOfTheDay(
                        from: source.context,
                        conversationTitle: source.conversation.title,
                        insights: Array(source.insights.prefix(4))
                    )
                } catch {
                    guard !Task.isCancelled else { return }
                    dailyQuestionGenerationRetryNotBefore = Date().addingTimeInterval(60 * 60)
                    debugQuestionOfTheDayConsoleLog(
                        "model boundary failed: \(String(reflecting: error))"
                    )
                    isDailyQuestionGenerationErrorPresented = true
                    return
                }
                guard !Task.isCancelled else { return }
                let trimmedQuestion = draft.question.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard HomeQuestionOfTheDay.isValidQuestionText(trimmedQuestion) else {
                    dailyQuestionGenerationRetryNotBefore = Date().addingTimeInterval(60 * 60)
                    isDailyQuestionGenerationErrorPresented = true
                    return
                }

                let citedInsight = draft.citedInsightTitle.flatMap { citedTitle in
                    source.insights.first {
                        $0.word.compare(
                            citedTitle,
                            options: [.caseInsensitive, .diacriticInsensitive]
                        ) == .orderedSame
                    }
                }
                let generated = HomeQuestionOfTheDay(
                    question: trimmedQuestion,
                    reasonForAsking: draft.reasonForAsking.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                    citedInsight: citedInsight,
                    sourceConversationID: source.conversation.id,
                    sourceConversationTitle: source.conversation.title
                )
                dailyQuestionGenerationRetryNotBefore = .distantPast
                HomeQuestionOfTheDayStore.save(generated)
                withAnimation(.easeInOut(duration: 0.35)) {
                    questionOfTheDay = generated
                }
            }
        }
    }

    // MARK: - Page Transitions

    private func transitionDisplayedPage(to nextPage: AppPage) {
        pendingPageTransitionWorkItem?.cancel()
        let transitionID = UUID()
        pageTransitionID = transitionID

        guard displayedPage != nextPage else {
            withAnimation(.easeInOut(duration: pageFadeDuration)) {
                isPageContentVisible = true
                pageContentOffsetY = 0
            } completion: {
                guard pageTransitionID == transitionID else { return }
                departingPageControlsHeight = nil
                schedulePendingPageReturn()
            }
            return
        }

        departingPageControlsHeight = departingPageControlsHeight ?? modelControlsHeight
        let startDelay: TimeInterval = isGlobalSideMenuOpen ? pageFadeDuration : 0

        let fadeOutWork = DispatchWorkItem {
            guard pageTransitionID == transitionID else { return }
            let fadeInWork = DispatchWorkItem {
                guard pageTransitionID == transitionID else { return }
                // Mount and lay out the destination while hidden. Its controls can now
                // reserve their own space without moving the departing conversation.
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    displayedPage = nextPage
                    departingPageControlsHeight = nil
                    pageContentOffsetY = pageTransitionOffset
                }
                let revealWork = DispatchWorkItem {
                    guard pageTransitionID == transitionID else { return }
                    withAnimation(.easeInOut(duration: pageFadeDuration)) {
                        isPageContentVisible = true
                        pageContentOffsetY = 0
                    } completion: {
                        guard pageTransitionID == transitionID else { return }
                        schedulePendingPageReturn()
                    }
                }
                pendingPageTransitionWorkItem = revealWork
                DispatchQueue.main.async(execute: revealWork)
            }

            withAnimation(.easeInOut(duration: pageFadeDuration), completionCriteria: .removed) {
                isPageContentVisible = false
                pageContentOffsetY = pageTransitionOffset
            } completion: {
                guard pageTransitionID == transitionID else { return }
                pendingPageTransitionWorkItem = fadeInWork
                DispatchQueue.main.asyncAfter(deadline: .now() + pageFadePauseDuration, execute: fadeInWork)
            }
        }

        pendingPageTransitionWorkItem = fadeOutWork
        DispatchQueue.main.asyncAfter(deadline: .now() + startDelay, execute: fadeOutWork)
    }

    private func dismissKeyboard() {
        isKeyboardVisible = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - Lifecycle and Change Handlers

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        appLockController.scenePhaseDidChange(
            phase,
            isEnabled: appLockEnabled,
            gracePeriod: appLockGracePeriod.duration
        )
        modelTasks.setApplicationActive(phase == .active)
        if phase == .background {
            BackgroundPersistenceFlush.begin()
        } else if phase == .active {
            BackgroundPersistenceFlush.retryDeferredWrites()
        }
        scheduleDailyQuestionRefreshIfNeeded()
    }

    private func handleActivePageChange(from oldValue: AppPage, to newValue: AppPage) {
        modelTasksPopupState.reset()
        if oldValue == .library, newValue != .library {
            // Consumed: reopening the Library from the menu should land on its home page.
            libraryNavigationRequest = nil
        }
        if oldValue == .insights, newValue != .insights {
            isGlobalTreeUpdatePromptVisible = false
            globalInsightIsSearchActive = false
            globalInsightSearchQuery = ""
            globalInsightSearchResultIndex = 0
            globalInsightSearchResultCount = 0
        }
        if newValue == .insights {
            refreshGlobalInsightTreeUpdatePrompt()
        }
        transitionDisplayedPage(to: newValue)
        scheduleDailyQuestionRefreshIfNeeded()
    }

    /// Clears in-memory state first so the change observers persist empty values, then wipes
    /// every stored Insight Tree artifact.
    private func clearInsightTree() {
        isGlobalTreeUpdatePromptVisible = false
        globalTreeAcknowledgedLibraryIDs = nil
        globalInsightPromotedIDs = []
        globalTreeInsights = []
        collectedDefinitions = []
        InsightTreeReset.clearPersistedData()
    }

    private func handleCollectedDefinitionsChange(_ definitions: [ConceptDefinition]) {
        InsightLibraryStore.save(definitions)
        guard activePage == .insights,
              !suppressGlobalTreePromptUntilExternalModelCompletion else { return }
        refreshGlobalInsightTreeUpdatePrompt()
    }

    private func handleSideMenuConversationsChange() {
        sideMenuRenderVersion &+= 1
        scheduleDailyQuestionRefreshIfNeeded()
    }

    private func handleCompletedModelTask(_ task: ModelTaskSnapshot?) {
        guard let task else { return }
        postConversationCompletionNotificationIfNeeded(for: task)
        guard task.originPage != .insights else { return }
        suppressGlobalTreePromptUntilExternalModelCompletion = false
        guard activePage == .insights else { return }
        refreshGlobalInsightTreeUpdatePrompt()
    }

    // MARK: - Loading

    private func loadShellConversationState() {
        guard let snapshot = CurrentConversationsStore.load(),
              !snapshot.conversations.isEmpty else { return }

        sideMenuConversations = snapshot.conversations
        let activeID = snapshot.activeConversationID ?? snapshot.conversations.first?.id
        sideMenuActiveConversationID = activeID
        sideMenuCurrentTitle = activeID.flatMap { id in
            snapshot.conversations.first { $0.id == id }?.title
        } ?? snapshot.conversations.first?.title ?? "New Conversation"
    }

    private func applyStartupDestinationIfNeeded() {
        guard !hasAppliedStartupDestination else { return }
        hasAppliedStartupDestination = true

        let action = AppStartupPolicy.resolve(
            preference: defaultStartScreen,
            conversationIDs: sideMenuConversations.map(\.id),
            activeConversationID: sideMenuActiveConversationID
        )
        switch action {
        case .home:
            activePage = .home
        case .openConversation(let conversationID):
            requestedConversationID = conversationID
            activePage = .conversation
        case .newConversation:
            newConversationRequests.submit()
            activePage = .conversation
        }
    }

    private func refreshPersistedContent() {
        if let snapshot = CurrentConversationsStore.load() {
            sideMenuConversations = snapshot.conversations
            let activeID = snapshot.activeConversationID ?? snapshot.conversations.first?.id
            sideMenuActiveConversationID = activeID
            sideMenuCurrentTitle = activeID.flatMap { id in
                snapshot.conversations.first { $0.id == id }?.title
            } ?? snapshot.conversations.first?.title ?? "New Conversation"
        }

        collectedDefinitions = InsightLibraryStore.load()
    }

    /// Selects the four on-device Home discovery sections. Each is fail-quiet: a `nil` result
    /// simply means that section doesn't render -- no error state, no placeholder.
    private func refreshHomeSections() async {
        let todayInHistory = HomeDiscovery.todayInHistory()
        guard let conversationID = HomeSectionSourceSelector.selectConversationID(
            conversations: sideMenuConversations,
            activeConversationID: sideMenuActiveConversationID
        ) else {
            withAnimation(.easeInOut(duration: 0.35)) {
                homeTodayInHistory = todayInHistory
                homeLooseThread = nil
                homeGlossedTerm = nil
                homeYourQuote = nil
            }
            return
        }

        let savedInsights = collectedDefinitions
        let glossedTerm = HomeDiscovery.glossedTerm(
            in: GlossedTermStore.records(for: conversationID),
            savedInsightIDs: Set(savedInsights.map(\.id))
        )
        let yourQuote = HomeDiscovery.yourQuote(in: conversationID)
        let looseThread = await HomeDiscovery.looseThread(
            in: conversationID,
            savedInsights: savedInsights,
            embeddingProvider: embeddingProvider
        )

        withAnimation(.easeInOut(duration: 0.35)) {
            homeTodayInHistory = todayInHistory
            homeLooseThread = looseThread
            homeGlossedTerm = glossedTerm
            homeYourQuote = yourQuote
        }
    }

    // MARK: - Global Insight Tree

    private func askGlobalInsightInNewConversation() {
        guard let insight = globalInsightQuoteTarget else { return }
        isGlobalInsightAskMode = false
        newConversationRequests.submit(NewConversationRequest(
            quote: NewConversationInsightQuoteRequest(insight: insight)
        ))
        redirect(to: .conversation)
    }

    private var globalTreeNeedsUpdate: Bool {
        Set(globalTreeInsights.uniquedByWord())
            != Set(collectedDefinitions.uniquedByWord())
    }

    private var globalTreeLibraryIDs: Set<UUID> {
        Set(collectedDefinitions.map(\.id))
    }

    /// Offers the update only when the saved Insights changed since the prompt was last
    /// answered, so reopening Global Insights doesn't ask again about the same library.
    private func refreshGlobalInsightTreeUpdatePrompt() {
        let needsUpdate = globalTreeNeedsUpdate
        // The tree already matches the library, so there is nothing left to ask about.
        if !needsUpdate { acknowledgeGlobalTreeLibrary(globalTreeLibraryIDs) }
        isGlobalTreeUpdatePromptVisible = !suppressGlobalTreePromptUntilExternalModelCompletion
            && GlobalInsightTreeUpdatePrompt.shouldOffer(
                libraryIDs: globalTreeLibraryIDs,
                acknowledgedLibraryIDs: globalTreeAcknowledgedLibraryIDs,
                treeNeedsUpdate: needsUpdate
            )
    }

    private func acknowledgeGlobalTreeLibrary(_ ids: Set<UUID>) {
        guard globalTreeAcknowledgedLibraryIDs != ids else { return }
        globalTreeAcknowledgedLibraryIDs = ids
        GlobalInsightTreeUpdatePrompt.saveAcknowledgedLibraryIDs(ids)
    }

    /// A bookmark added or removed inside Global Insights changes the tree and the library
    /// together, so it is already applied and must not raise the prompt by itself. A change
    /// still waiting on an answer stays pending.
    private func acknowledgeGlobalTreeEdit(adding added: [UUID] = [], removing removed: [UUID] = []) {
        guard let acknowledged = globalTreeAcknowledgedLibraryIDs else { return }
        acknowledgeGlobalTreeLibrary(acknowledged.union(added).subtracting(removed))
    }

    private func updateGlobalInsightTree() {
        let existingSnapshot = globalTreeInsights
        let incomingSnapshot = collectedDefinitions

        // Reconciliation calls into NaturalLanguage for every unique Insight. Keep that CPU work
        // outside the main actor so the canvas remains responsive to panning and zooming.
        withAnimation(.springStandard) {
            isGlobalTreeUpdatePromptVisible = false
            suppressGlobalTreePromptUntilExternalModelCompletion = true
            isGlobalTreeReconciling = true
        }

        Task { @MainActor in
            let reconciledInsights = await Task.detached(priority: .userInitiated) {
                GlobalInsightReconciliation.reconcile(
                    existing: existingSnapshot,
                    incoming: incomingSnapshot
                )
            }.value

            // Do not let a completed background pass overwrite edits made while it was running.
            guard globalTreeInsights == existingSnapshot,
                  collectedDefinitions == incomingSnapshot else {
                isGlobalTreeReconciling = false
                suppressGlobalTreePromptUntilExternalModelCompletion = false
                refreshGlobalInsightTreeUpdatePrompt()
                return
            }

            withAnimation(.springStandard) {
                globalTreeInsights = reconciledInsights
                isGlobalTreeReconciling = false
            }
            GlobalInsightTreeStore.save(reconciledInsights)
            acknowledgeGlobalTreeLibrary(Set(incomingSnapshot.map(\.id)))
            globalInsightsContextCardState.reset()
            modelTasksPopupState.reset()
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
        }
    }

    private func dismissGlobalInsightTreeUpdate() {
        acknowledgeGlobalTreeLibrary(globalTreeLibraryIDs)
        withAnimation(.springStandard) {
            isGlobalTreeUpdatePromptVisible = false
        }
    }

    // MARK: - Conversation Management

    private func deleteConversation(_ conversation: InquiryConversation) {
        // Remove from the side menu list immediately for snappy feedback.
        sideMenuConversations.removeAll { $0.id == conversation.id }

        if sideMenuActiveConversationID == conversation.id {
            sideMenuActiveConversationID = sideMenuConversations.first?.id
            sideMenuCurrentTitle = sideMenuConversations.first?.title ?? "New Conversation"
        }

        // Signal the canvas to remove the thread (and any forks).
        deletedConversationID = conversation.id
        CurrentConversationsStore.save(
            InquiryPersistenceSnapshot(
                conversations: sideMenuConversations,
                activeConversationID: sideMenuActiveConversationID
            )
        )

        // Stay on Open Conversations and let it show its own empty state — don't bounce
        // back to the canvas, since that auto-seeds a fresh blank conversation on appear.
    }

    private func renameConversation(_ conversation: InquiryConversation, to title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        if let index = sideMenuConversations.firstIndex(where: { $0.id == conversation.id }) {
            sideMenuConversations[index].title = trimmedTitle
        }

        if sideMenuActiveConversationID == conversation.id {
            sideMenuCurrentTitle = trimmedTitle
        }

        if var snapshot = InquiryPersistenceStore.load(),
           let index = snapshot.conversations.firstIndex(where: { $0.id == conversation.id }) {
            snapshot.conversations[index].title = trimmedTitle
            InquiryPersistenceStore.save(snapshot)
        }
    }

    private func pinConversation(_ conversation: InquiryConversation) {
        if let index = sideMenuConversations.firstIndex(where: { $0.id == conversation.id }) {
            sideMenuConversations[index].isPinned = true
        }
        if var snapshot = CurrentConversationsStore.load(),
           let index = snapshot.conversations.firstIndex(where: { $0.id == conversation.id }) {
            snapshot.conversations[index].isPinned = true
            CurrentConversationsStore.save(snapshot)
        }
    }

    private func unpinConversation(_ conversation: InquiryConversation) {
        if let index = sideMenuConversations.firstIndex(where: { $0.id == conversation.id }) {
            sideMenuConversations[index].isPinned = false
        }
        if var snapshot = CurrentConversationsStore.load(),
           let index = snapshot.conversations.firstIndex(where: { $0.id == conversation.id }) {
            snapshot.conversations[index].isPinned = false
            CurrentConversationsStore.save(snapshot)
        }
    }

    private func detachConversationFromStudyTopic(_ conversation: InquiryConversation) {
        if let index = sideMenuConversations.firstIndex(where: { $0.id == conversation.id }) {
            sideMenuConversations[index].studyTopicID = nil
        }
        if var snapshot = CurrentConversationsStore.load(),
           let index = snapshot.conversations.firstIndex(where: { $0.id == conversation.id }) {
            snapshot.conversations[index].studyTopicID = nil
            CurrentConversationsStore.save(snapshot)
        }
    }

    private func attachConversation(_ conversation: InquiryConversation, toStudyTopic topicID: UUID) {
        let wasAlreadyAttached = sideMenuConversations.first(where: { $0.id == conversation.id })?
            .studyTopicID == topicID
        if !wasAlreadyAttached {
            StudyTopicTreeUpdateRequests.request(for: topicID)
        }
        // Update in-memory — CurrentConversationView's onChange will pick this up
        // and call persistConversations() if it is currently mounted.
        if let index = sideMenuConversations.firstIndex(where: { $0.id == conversation.id }) {
            sideMenuConversations[index].studyTopicID = topicID
        }

        // Write directly to CurrentConversationsStore so the attachment survives the
        // next app launch even when CurrentConversationView is not mounted (e.g. the
        // user is on the Study Topics page). InquiryPersistenceStore uses a different
        // UserDefaults key and is never read by CurrentConversationView, so writing
        // only to that store was silently losing the attachment.
        if var snapshot = CurrentConversationsStore.load(),
           let index = snapshot.conversations.firstIndex(where: { $0.id == conversation.id }) {
            snapshot.conversations[index].studyTopicID = topicID
            CurrentConversationsStore.save(snapshot)
        }
    }
}

private extension ProcessInfo.ThermalState {
    var modelRuntimePressure: ModelRuntimeThermalPressure {
        switch self {
        case .nominal:
            return .nominal
        case .fair:
            return .fair
        case .serious:
            return .serious
        case .critical:
            return .critical
        @unknown default:
            return .serious
        }
    }
}

private extension View {
    func eraseToAnyView() -> AnyView {
        AnyView(self)
    }

    func dailyQuestionGenerationAlert(
        isPresented: Binding<Bool>,
        retry: @escaping () -> Void
    ) -> some View {
        modifier(DailyQuestionGenerationAlert(
            isPresented: isPresented,
            retry: retry
        ))
    }
}

private struct DailyQuestionGenerationAlert: ViewModifier {
    @Binding var isPresented: Bool
    let retry: () -> Void

    func body(content: Content) -> some View {
        content.alert("Couldn’t generate Question of the Day", isPresented: $isPresented) {
            Button("Cancel", role: .cancel) { }
            Button("Try Again", action: retry)
        } message: {
            Text("No placeholder question was created. The on-device model couldn’t finish; please try again.")
        }
    }
}

#Preview {
    ContentView()
}
