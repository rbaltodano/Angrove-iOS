import SwiftUI

enum MacWorkspaceIdentity {
    static func initialConversationID(isPreview: Bool, savedID: UUID?) -> UUID {
        isPreview ? UUID() : (savedID ?? UUID())
    }
}

enum MacDestination: String, CaseIterable, Identifiable {
    case home, insights, conversations, studyTopics
    var id: Self { self }
    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .insights: "Insights"
        case .conversations: "Conversations"
        case .studyTopics: "Study Topics"
        }
    }
    var symbol: String {
        switch self {
        case .home: "house"
        case .insights: "leaf"
        case .conversations: "bubble.left.and.bubble.right"
        case .studyTopics: "books.vertical"
        }
    }
    var asset: MacIcon {
        switch self {
        case .home: .home
        case .insights: .insights
        case .conversations: .conversations
        case .studyTopics: .topics
        }
    }
}

struct MacWorkspaceView: View {
    let support: MacHardwareSupport
    @State private var selection: MacDestination = .conversations
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
    @State private var conversationDrafts: [UUID: String] = [:]

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
                        })
                    .frame(width: sidebar.width(in: geometry.size.width))
                    .clipped()
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
                            MacGlobalInsightWorkspace(queuePopup: queuePopup, onActivity: recordPageActivity) { concept, existingID in
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
                                navigate(to: MacWorkspacePage(destination: .conversations, conversationID: targetID))
                                pendingQuote = concept
                            }
                        } else {
                            MacDestinationView(destination: selection)
                        }
                    }
                    .background(MacPageActivityObserver(onActivity: recordPageActivity))
                }
                .coordinateSpace(name: "MacWorkspace")
                .overlay(alignment: .topLeading) {
                    MacSidebarToggle(layout: $sidebar, windowWidth: geometry.size.width)
                }
                .overlayPreferenceValue(MacCompactSidebarHoverKey.self) { hover in
                    MacCompactSidebarLabelOverlay(hover: sidebar.isCompact ? hover : nil)
                }
                .overlayPreferenceValue(MacSidebarMenuAnchorKey.self) { anchors in
                    MacSidebarConversationMenuOverlay(conversations: conversations, menuID: $conversationMenuID,
                                                      anchors: anchors, onAction: handleConversationAction)
                }
            }
            .focusedSceneValue(\.macWorkspaceCommands, MacWorkspaceCommandTarget(
                request: $shortcutRequest,
                recentConversationIDs: MacWorkspaceCommandTarget.recentIDs(in: conversations),
                canGoBack: history.canGoBack, canGoForward: history.canGoForward))
            .onAppear { history.visit(currentPage) }
            .onChange(of: shortcutRequest) { _, request in
                guard let request else { return }
                handleShortcut(request)
                shortcutRequest = nil
            }
            .onExitCommand { conversationMenuID = nil }
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
            .onReceive(NotificationCenter.default.publisher(for: .macConversationDeleted)) { notification in
                guard let id = notification.object as? UUID else { return }
                history.removeConversation(id)
                conversationDrafts[id] = nil
                guard conversationID == id else { return }
                let nextID = MacSidebarConversationActions.sorted(conversations.filter { $0.id != id }).first?.id ?? UUID()
                if selection == .conversations {
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
                Label("This Mac isn’t supported", systemImage: "desktopcomputer.trianglebadge.exclamationmark")
            } description: {
                Text("Angrove requires an Apple silicon Mac with at least 16 GB of memory running macOS 27 or later.")
            }
            .frame(minWidth: 600, minHeight: 400)
            .background(AngroveTheme.Colors.canvas)
        }
    }

    private var currentPage: MacWorkspacePage {
        page(for: selection)
    }

    private func page(for destination: MacDestination) -> MacWorkspacePage {
        MacWorkspacePage(destination: destination,
            conversationID: destination == .conversations ? conversationID : nil,
            isFixture: destination == .conversations && showFixture)
    }

    private func navigate(to page: MacWorkspacePage, recordsVisit: Bool = true) {
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
        if recordsVisit { history.visit(page) }
    }

    private func recordPageActivity() {
        history.visit(currentPage)
    }

    private func handleShortcut(_ request: MacShortcutRequest) {
        conversationMenuID = nil
        renamingConversationID = nil
        switch request.action {
        case .goBack:
            if let page = history.back() { navigate(to: page, recordsVisit: false) }
        case .goForward:
            if let page = history.forward() { navigate(to: page, recordsVisit: false) }
        case .openGlobalTree:
            navigate(to: page(for: .insights))
        case .newConversation:
            navigate(to: MacWorkspacePage(destination: .conversations, conversationID: UUID()))
            paneShortcut = MacShortcutRequest(action: .focusQuestion)
        case .recentConversation(let number):
            let ids = MacWorkspaceCommandTarget.recentIDs(in: conversations)
            guard number >= 1, number <= ids.count else { return }
            navigate(to: MacWorkspacePage(destination: .conversations, conversationID: ids[number - 1]))
        case .openQueue:
            if selection != .conversations && selection != .insights { navigate(to: page(for: .conversations)) }
            recordPageActivity()
            withAnimation(.springStandard) { queuePopup.isOpen = true }
        case .openTree:
            if selection == .insights { recordPageActivity(); return }
            navigate(to: page(for: .conversations))
            recordPageActivity()
            paneShortcut = request
        case .focusQuestion, .swapPanes, .pinPanes:
            navigate(to: page(for: .conversations))
            recordPageActivity()
            paneShortcut = request
        }
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

struct MacDestinationView: View {
    let destination: MacDestination

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AngroveTheme.Spacing.cardPadding) {
                Text(destination.title)
                    .font(AngroveTheme.Typography.titleHome)
                    .foregroundStyle(AngroveTheme.Colors.headingText)

                if destination == .home {
                    MacWelcomeCard()
                } else {
                    MacFeaturePreparation(destination: destination)
                }
            }
            .padding(AngroveTheme.Spacing.illustratedCardPadding)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AngroveTheme.Colors.canvas)
    }
}

private struct MacWelcomeCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AngroveTheme.Spacing.screenPadding) {
            Image(systemName: "leaf")
                .font(AngroveTheme.Typography.titleLarge)
                .foregroundStyle(AngroveTheme.Colors.lightGreen)
                .accessibilityHidden(true)
            Text("A place for deeper inquiry.")
                .font(AngroveTheme.Typography.titleLarge)
                .foregroundStyle(AngroveTheme.Colors.primaryReadable)
            Text("Angrove for Mac is taking root. Conversations, reading, and your Insight Tree will come together here.")
                .font(AngroveTheme.Typography.bodyLarge)
                .foregroundStyle(AngroveTheme.Colors.paragraphText)
            Text("Development preview · Features are still being connected.")
                .font(AngroveTheme.Typography.body)
                .foregroundStyle(AngroveTheme.Colors.placeholderText)
        }
        .padding(AngroveTheme.Spacing.illustratedCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AngroveTheme.Colors.canvasSecondary, in: RoundedRectangle(cornerRadius: AngroveTheme.Spacing.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AngroveTheme.Spacing.cardRadius)
                .strokeBorder(AngroveTheme.Colors.border, lineWidth: 1)
        }
    }
}

private struct MacFeaturePreparation: View {
    let destination: MacDestination

    var body: some View {
        ContentUnavailableView {
            Label(destination.title, systemImage: destination.symbol)
        } description: {
            Text("This part of the Mac edition is still being built.")
        }
        .foregroundStyle(AngroveTheme.Colors.paragraphText)
    }
}
