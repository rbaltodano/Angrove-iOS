import SwiftUI

enum MacWorkspaceIdentity {
    static func initialConversationID(isPreview: Bool, savedID: UUID?) -> UUID {
        isPreview ? UUID() : (savedID ?? UUID())
    }
}

enum MacDestination: String, CaseIterable, Identifiable {
    case home, insights, conversations, library, studyTopics, worktree, settings
    static let sidebarDestinations: [Self] = [.home, .insights, .conversations, .library, .studyTopics, .worktree]
    var id: Self { self }
    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .insights: "Insights"
        case .conversations: "Conversations"
        case .library: "Library"
        case .studyTopics: "Study Topics"
        case .worktree: "Worktree"
        case .settings: "Settings"
        }
    }
    var headingTitle: String {
        switch self {
        case .home: String(localized: "Home")
        case .insights: String(localized: "Insights")
        case .conversations: String(localized: "Conversations")
        case .library: String(localized: "Library")
        case .studyTopics: String(localized: "Study Topics")
        case .worktree: String(localized: "Worktree")
        case .settings: String(localized: "Settings")
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .insights: "leaf"
        case .conversations: "bubble.left.and.bubble.right"
        case .library: "books.vertical"
        case .studyTopics: "books.vertical"
        case .worktree: MacIcon.worktree.symbol
        case .settings: "gearshape"
        }
    }
    var asset: MacIcon {
        switch self {
        case .home: .home
        case .insights: .insights
        case .conversations: .conversations
        case .library: .library
        case .studyTopics: .topics
        case .worktree: .worktree
        case .settings: .settings
        }
    }
}

struct MacWorkspaceView: View {
    let support: MacHardwareSupport
    @State private var selection: MacDestination = MacDesignPreview.isEnabled ? .conversations : .home
    @State private var conversations = CurrentConversationsStore.load()?.conversations ?? []
    @State private var question = ""
    @State private var conversationID = MacWorkspaceIdentity.initialConversationID(isPreview: MacDesignPreview.isEnabled,
        savedID: MacDesignPreview.isEnabled ? nil : CurrentConversationsStore.load()?.activeConversationID)
    @State private var showFixture = MacDesignPreview.isEnabled
    @State private var pendingQuote: ConceptDefinition?
    @State private var sidebar = MacSidebarLayout()
    @State private var conversationMenuID: UUID?
    @State private var actionConversationID: UUID?
    @State private var renamingConversationID: UUID?
    @State private var showsDelete = false
    @State private var topicConversation: InquiryConversation?
    @State private var shortcutRequest: MacShortcutRequest?
    @State private var paneShortcut: MacShortcutRequest?
    @State private var queuePopup = ModelTasksPopupState()
    @State private var history = MacPageHistory()
    @State private var globalTreeShortcut = MacGlobalTreeShortcut()
    @State private var conversationDrafts: [UUID: String] = [:]
    @State private var opensSettingsGuide = false
    @State private var libraryRequest: LibraryNavigationRequest?
    @State private var hasAppliedStartScreen = false
    @State private var pageTransition = MacPageTransition()
    @State private var homeVinePlayback = HomeVinePlaybackController()
    @State private var worktree = WorktreeBoard()
    private var ownsPageFade: Bool { selection == .conversations || selection == .insights }
    @Environment(\.isBootPageRevealAnimating) private var bootPageReveal
    @Environment(\.isBootRevealComplete) private var bootRevealComplete
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsStorageKey.defaultStartScreen) private var startScreen: DefaultStartScreenOption = .home

    var body: some View {
        if support.isSupported {
            let modelTasks = MacApplicationRuntime.shared.modelTasks
            let pendingTasks = [modelTasks.currentTask].compactMap { $0 } + modelTasks.upcomingTasks
            let loadingBranchIDs = Set(pendingTasks.compactMap { $0.kind.userQuestionBranchID })
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    MacFloatingSidebar(selection: Binding(get: { selection }, set: { navigate(to: page(for: $0)) }), isCompact: sidebar.isCompact, showsFixture: showFixture,
                        conversations: conversations, loadingBranchIDs: loadingBranchIDs, openConversation: { id in
                        navigate(to: MacWorkspacePage(destination: .conversations, conversationID: id))
                    }, newConversation: {
                        navigate(to: MacWorkspacePage(destination: .conversations, conversationID: UUID()))
                    }, openPreview: {
                        navigate(to: MacWorkspacePage(destination: .conversations, conversationID: UUID(), isFixture: true))
                    }, activeConversationID: conversationID, openMenuID: conversationMenuID,
                        openMenu: { conversationMenuID = conversationMenuID == $0 ? nil : $0 },
                        renamingConversationID: renamingConversationID,
                        beginRename: { conversationMenuID = nil; renamingConversationID = $0 },
                        finishRename: { id, title in
                            if renamingConversationID == id { renamingConversationID = nil }
                            if let title { updateConversation(id, action: .rename(title)) }
                        }, menuAction: handleConversationAction)
                    .frame(width: sidebar.width(in: geometry.size.width))
                    .clipped()
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { worktree.sidebarFrame = $0 }
                    .overlay(alignment: .trailing) {
                        MacSidebarResizeHandle(layout: $sidebar, windowWidth: geometry.size.width)
                    }
                    .zIndex(3) // Navigation stays above workspace content and floating cards.

                    ZStack {
                        if selection == .conversations {
                            MacConversationWorkspace(showsFixture: showFixture, conversationID: conversationID, question: $question,
                                shortcutRequest: $paneShortcut, queuePopup: queuePopup, onActivity: recordPageActivity,
                                initialQuote: pendingQuote, onInitialQuoteHandled: { pendingQuote = nil },
                                onNewConversation: {
                                    navigate(to: MacWorkspacePage(destination: .conversations, conversationID: UUID()))
                                }, onOpenInsights: { navigate(to: page(for: .insights)) })
                                .id(conversationID)
                        } else if selection == .insights {
                            MacGlobalInsightWorkspace(queuePopup: queuePopup, onActivity: recordPageActivity, onAsk: quote)
                        } else if selection == .home {
                            MacHomeView(conversations: conversations, activeConversationID: conversationID,
                                onOpenConversation: { id in
                                    navigate(to: MacWorkspacePage(destination: .conversations, conversationID: id))
                                },
                                onStart: startConversation,
                                onOpenInsights: { navigate(to: page(for: .insights)) },
                                onQuoteInsight: { quote($0, in: nil) },
                                onOpenGuide: {
                                    navigate(to: page(for: .settings)) { opensSettingsGuide = true }
                                })
                        } else if selection == .library {
                            MacLibraryView(navigationRequest: libraryRequest, conversations: conversations, onAsk: quote)
                        } else if selection == .settings {
                            MacSettingsView(startsInGuide: opensSettingsGuide)
                                .onDisappear { opensSettingsGuide = false }
                        } else if selection == .studyTopics {
                            MacStudyTopicsView(conversations: conversations,
                                onOpenConversation: { id in
                                    navigate(to: MacWorkspacePage(destination: .conversations, conversationID: id))
                                },
                                onNewConversation: newConversation(inTopic:),
                                onTopicsChanged: {
                                    conversations = CurrentConversationsStore.load()?.conversations ?? []
                                    NotificationCenter.default.post(name: .macConversationSaved, object: nil)
                                },
                                onAsk: quote, queuePopup: queuePopup)
                        } else if selection == .worktree {
                            MacWorktreeView(board: worktree, queuePopup: queuePopup)
                        }
                    }
                    // The conversation and Insights pages fade their own content, leaving Model Controls
                    // free to animate on their own as the page changes.
                    .opacity(ownsPageFade || pageTransition.isVisible ? 1 : 0)
                    .offset(y: ownsPageFade || pageTransition.isVisible || reduceMotion ? 0 : MacPageTransition.offset)
                    .environment(\.macPageFade, ownsPageFade
                        ? MacPageFade(isVisible: pageTransition.isVisible,
                                      offset: pageTransition.isVisible || reduceMotion ? 0 : MacPageTransition.offset)
                        : MacPageFade())
                    .environment(\.macPageControlsVisible, pageTransition.showsControls)
                    .environment(\.isBootPageRevealAnimating, bootPageReveal && pageTransition.canRevealContent)
                    .environment(\.isBootRevealComplete, bootRevealComplete && pageTransition.canRevealContent)
                    .environment(\.homeVinePlayback, homeVinePlayback)
                    .allowsHitTesting(!pageTransition.isTransitioning)
                    .background(MacPageActivityObserver(onActivity: recordPageActivity))
                }
                .coordinateSpace(name: "MacWorkspace")
                .overlay(alignment: .topLeading) {
                    MacSidebarToggle(layout: $sidebar, windowWidth: geometry.size.width)
                }
                .overlayPreferenceValue(MacCompactSidebarHoverKey.self) { hover in
                    MacCompactSidebarLabelOverlay(hover: sidebar.isCompact ? hover : nil)
                }
                .overlay(alignment: .topLeading) { WorktreeSidebarDragChip(drag: worktree.sidebarDrag) }
                .overlayPreferenceValue(MacSidebarMenuAnchorKey.self) { anchors in
                    MacSidebarConversationMenuOverlay(conversations: conversations, menuID: $conversationMenuID,
                                                      anchors: anchors, onAction: handleConversationAction)
                }
            }
            .focusedSceneValue(\.macWorkspaceCommands, MacWorkspaceCommandTarget(
                request: $shortcutRequest,
                recentConversationIDs: MacWorkspaceCommandTarget.recentIDs(in: conversations),
                canGoBack: history.canGoBack, canGoForward: history.canGoForward,
                destination: pageTransition.destination?.destination ?? selection))
            .onAppear {
                applyStartScreen()
                history.visit(currentPage)
                MacApplicationRuntime.shared.modelTasks.onTaskCompleted = { task in
                    let isViewing: (UUID) -> Bool = { selection == .conversations && conversationID == $0 }
                    MacNotifications.postIfNeeded(for: task, isViewing: isViewing)
                    MacNotifications.readAloudIfFinishedElsewhere(task, isViewing: isViewing)
                }
            }
            .onDisappear { pageTransition.cancel() }
            .onReceive(NotificationCenter.default.publisher(for: .macOpenConversation)) { notification in
                guard let id = notification.object as? UUID else { return }
                navigate(to: MacWorkspacePage(destination: .conversations, conversationID: id))
            }
            .onReceive(NotificationCenter.default.publisher(for: .macOpenHome)) { _ in navigate(to: page(for: .home)) }
            .onChange(of: shortcutRequest) { _, request in
                guard let request else { return }
                handleShortcut(request)
                shortcutRequest = nil
            }
            .onExitCommand { conversationMenuID = nil }
            .onReceive(NotificationCenter.default.publisher(for: .macActionMenuWillOpen)) { _ in conversationMenuID = nil }
            .onChange(of: selection) { _, _ in conversationMenuID = nil }
            .onChange(of: sidebar.isCompact) { _, _ in conversationMenuID = nil }
            .onChange(of: conversationID) { _, _ in conversationMenuID = nil }
            .alert("Delete Conversation?", isPresented: $showsDelete) {
                Button("Cancel", role: .cancel) { actionConversationID = nil }
                Button("Delete", role: .destructive) {
                    if let id = actionConversationID { deleteConversation(id) }
                    actionConversationID = nil
                }
            } message: {
                Text("This removes the conversation and its history. Saved Insights remain in your library.")
            }
            .sheet(item: $topicConversation) { conversation in
                MacConversationTopicPicker(selectedID: conversation.studyTopicID) { topicID in
                    updateConversation(conversation.id, action: .assignTopic(topicID))
                    topicConversation = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .macConversationSaved)) { _ in
                conversations = CurrentConversationsStore.load()?.conversations ?? []
            }
            .onReceive(NotificationCenter.default.publisher(for: .openGroundingSourceInLibrary)) { notification in
                guard let request = notification.object as? LibraryNavigationRequest else { return }
                navigate(to: page(for: .library)) { libraryRequest = request }
            }
            .onReceive(NotificationCenter.default.publisher(for: .macConversationDeleted)) { notification in
                guard let id = notification.object as? UUID else { return }
                history.removeConversation(id)
                conversationDrafts[id] = nil
                let isPendingDestination = pageTransition.destination?.conversationID == id
                guard conversationID == id || isPendingDestination else { return }
                let nextID = MacSidebarConversationActions.sorted(conversations.filter { $0.id != id }).first?.id ?? UUID()
                if selection == .conversations || isPendingDestination {
                    navigate(to: MacWorkspacePage(destination: .conversations, conversationID: nextID))
                } else {
                    conversationID = nextID
                    question = conversationDrafts[nextID] ?? ""
                    pendingQuote = nil
                    showFixture = false
                }
                conversationDrafts[id] = nil
            }
            .environment(\.openModelTaskPage, { task in
                if let id = task.conversationID {
                    navigate(to: MacWorkspacePage(destination: .conversations, conversationID: id))
                } else { navigate(to: page(for: .insights)) }
            })
            .environment(\.openReadingConversation, { id in
                navigate(to: MacWorkspacePage(destination: .conversations, conversationID: id))
            })
            .ignoresSafeArea()
            .background(AngroveTheme.Colors.canvas)
            .tint(AngroveTheme.Colors.lightGreen)
            .navigationTitle(showFixture ? "Angrove – Design Preview" : "Angrove")
            .frame(minWidth: 760, minHeight: 540)
        } else {
            ContentUnavailableView {
                VStack(spacing: 16) {
                    Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                        .font(.system(size: 28, weight: .semibold))
                    MacPageHeading(title: "This Mac isn’t supported", font: MacPageHeading.pageFont)
                }
            } description: {
                Text("Angrove requires an Apple silicon Mac with at least 16 GB of memory running macOS 27 or later.")
                    .paragraphFont()
                    .settingsTextReveal()
            }
            .frame(minWidth: 600, minHeight: 400)
            .background(AngroveTheme.Colors.canvas)
        }
    }

    private var currentPage: MacWorkspacePage {
        MacWorkspacePage(destination: selection,
            conversationID: selection == .conversations ? conversationID : nil,
            isFixture: selection == .conversations && showFixture)
    }

    private func page(for destination: MacDestination) -> MacWorkspacePage {
        if let pending = pageTransition.destination, pending.destination == destination { return pending }
        return MacWorkspacePage(destination: destination,
            conversationID: destination == .conversations ? conversationID : nil,
            isFixture: destination == .conversations && showFixture)
    }

    private func navigate(to page: MacWorkspacePage, recordsVisit: Bool = true,
                          onArrival: @escaping @MainActor () -> Void = {}) {
        if recordsVisit { history.visit(page) }
        guard page != currentPage || pageTransition.isTransitioning else {
            onArrival()
            return
        }
        pageTransition.navigate(to: page) {
            applyNavigation(to: page)
            onArrival()
        }
    }

    private func applyNavigation(to page: MacWorkspacePage) {
        if page != currentPage {
            conversationDrafts[conversationID] = question
            pendingQuote = nil
            paneShortcut = nil
            queuePopup.reset()
            conversationMenuID = nil
            renamingConversationID = nil
            if let id = page.conversationID {
                conversationID = id
                question = conversationDrafts[id] ?? ""
                showFixture = page.isFixture
            }
            selection = page.destination
        }
    }

    private func recordPageActivity() {
        guard !pageTransition.isTransitioning else { return }
        history.visit(currentPage)
    }

    private func handleShortcut(_ request: MacShortcutRequest) {
        guard request.action != .openTree || (pageTransition.destination?.destination ?? selection) == .conversations else { return }
        conversationMenuID = nil
        renamingConversationID = nil
        switch request.action {
        case .goBack:
            if let page = history.back() { navigate(to: page, recordsVisit: false) }
        case .goForward:
            if let page = history.forward() { navigate(to: page, recordsVisit: false) }
        case .openSettings:
            if (pageTransition.destination?.destination ?? selection) == .settings {
                if let previous = history.back() { navigate(to: previous, recordsVisit: false) }
                else { navigate(to: page(for: .conversations)) }
            } else {
                navigate(to: page(for: .settings))
            }
        case .openHome:
            navigate(to: page(for: .home))
        case .openGlobalTree:
            toggleGlobalTree()
        case .newConversation:
            navigate(to: MacWorkspacePage(destination: .conversations, conversationID: UUID())) {
                paneShortcut = MacShortcutRequest(action: .focusQuestion)
            }
        case .recentConversation(let number):
            let ids = MacWorkspaceCommandTarget.recentIDs(in: conversations)
            guard number >= 1, number <= ids.count else { return }
            navigate(to: MacWorkspacePage(destination: .conversations, conversationID: ids[number - 1]))
        case .openQueue:
            // Pages with their own Model Tasks control open it in place.
            let current = pageTransition.destination?.destination ?? selection
            let destination = [.insights, .worktree].contains(current) ? page(for: current) : page(for: .conversations)
            navigate(to: destination) {
                withAnimation(.springStandard) { queuePopup.isOpen.toggle() }
            }
        case .openTree:
            navigate(to: page(for: .conversations)) { paneShortcut = request }
        case .focusQuestion, .swapPanes, .pinPanes, .toggleContext:
            navigate(to: page(for: .conversations)) { paneShortcut = request }
        }
    }

    /// Opens an existing conversation, or a new saved one, with the Insight quoted in its composer.
    private func quote(_ concept: ConceptDefinition, in existingID: UUID?) {
        var snapshot = CurrentConversationsStore.load() ?? InquiryPersistenceSnapshot(conversations: [], activeConversationID: nil)
        let targetID: UUID
        if let existingID { targetID = existingID }
        else {
            let conversation = InquiryConversation(branches: [ChatBranch(startingConcept: nil)])
            snapshot.conversations.append(conversation)
            targetID = conversation.id
        }
        snapshot.activeConversationID = targetID
        CurrentConversationsStore.save(snapshot)
        conversations = snapshot.conversations
        navigate(to: MacWorkspacePage(destination: .conversations, conversationID: targetID)) {
            pendingQuote = concept
        }
    }

    /// Settings › Open Angrove to. Last Conversation keeps the restored conversation, or falls
    /// back to Home when there is none, as on iPhone.
    private func applyStartScreen() {
        guard !hasAppliedStartScreen, !showFixture else { return }
        hasAppliedStartScreen = true
        switch startScreen {
        case .home:
            selection = .home
        case .newConversation:
            selection = .conversations
            conversationID = UUID()
            question = ""
            paneShortcut = MacShortcutRequest(action: .focusQuestion)
        case .lastConversation:
            selection = .conversations
            if !conversations.contains(where: { $0.id == conversationID }) {
                if let latest = MacSidebarConversationActions.sorted(conversations).first { conversationID = latest.id }
                else { selection = .home }
            }
        }
    }

    /// Home prompts are saved with their hidden context before the conversation opens.
    private func startConversation(_ request: NewConversationRequest) {
        guard !request.promptContext.isEmpty else {
            navigate(to: MacWorkspacePage(destination: .conversations, conversationID: UUID())) {
                paneShortcut = MacShortcutRequest(action: .focusQuestion)
            }
            return
        }
        let empty = InquiryPersistenceSnapshot(conversations: [], activeConversationID: nil)
        let snapshot = MacDailyPrompt.conversation(for: request, in: CurrentConversationsStore.load() ?? empty)
        CurrentConversationsStore.save(snapshot)
        conversations = snapshot.conversations
        guard let id = snapshot.activeConversationID else { return }
        navigate(to: MacWorkspacePage(destination: .conversations, conversationID: id)) {
            paneShortcut = MacShortcutRequest(action: .focusQuestion)
        }
    }

    /// A topic's conversation is saved before it opens so the topic lists it immediately.
    private func newConversation(inTopic topicID: UUID) {
        var snapshot = CurrentConversationsStore.load() ?? InquiryPersistenceSnapshot(conversations: [], activeConversationID: nil)
        var conversation = InquiryConversation(branches: [ChatBranch(startingConcept: nil)])
        conversation.studyTopicID = topicID
        snapshot.conversations.append(conversation)
        snapshot.activeConversationID = conversation.id
        CurrentConversationsStore.save(snapshot)
        conversations = snapshot.conversations
        navigate(to: MacWorkspacePage(destination: .conversations, conversationID: conversation.id)) {
            paneShortcut = MacShortcutRequest(action: .focusQuestion)
        }
    }

    private func toggleGlobalTree() {
        let destination = globalTreeShortcut.toggle(from: pageTransition.destination ?? currentPage,
                                                   fallback: page(for: .conversations))
        navigate(to: destination)
    }

    private func handleConversationAction(_ action: MacSidebarConversationMenuAction, _ conversation: InquiryConversation) {
        conversationMenuID = nil
        switch action {
        case .rename:
            renamingConversationID = conversation.id
        case .pin:
            updateConversation(conversation.id, action: .setPinned(!conversation.isPinned))
        case .topic:
            if conversation.studyTopicID != nil { updateConversation(conversation.id, action: .assignTopic(nil)) }
            else { topicConversation = conversation }
        case .delete:
            actionConversationID = conversation.id
            showsDelete = true
        }
    }

    private func updateConversation(_ id: UUID, action: MacSidebarConversationMutation) {
        guard let snapshot = CurrentConversationsStore.load(),
              let updated = MacSidebarConversationActions.applying(action, to: id, in: snapshot) else { return }
        CurrentConversationsStore.save(updated)
        conversations = updated.conversations
        NotificationCenter.default.post(name: .macConversationMetadataChanged,
                                        object: updated.conversations.first(where: { $0.id == id }))
        NotificationCenter.default.post(name: .macConversationSaved, object: nil)
    }

    private func deleteConversation(_ id: UUID) {
        guard let snapshot = CurrentConversationsStore.load() else { return }
        NotificationCenter.default.post(name: .macConversationDeleted, object: id)
        MacApplicationRuntime.shared.modelTasks.cancelTasks { $0.conversationID == id }
        let updated = MacSidebarConversationActions.deleting(id, in: snapshot)
        CurrentConversationsStore.save(updated)
        ConversationInsightMembershipStore.removeConversation(id)
        LocalInsightTreeSeedStore.removeConversation(id)
        conversations = updated.conversations
        if conversationID == id {
            navigate(to: MacWorkspacePage(destination: .conversations, conversationID: updated.activeConversationID ?? UUID()))
        }
        NotificationCenter.default.post(name: .macConversationSaved, object: nil)
    }
}
