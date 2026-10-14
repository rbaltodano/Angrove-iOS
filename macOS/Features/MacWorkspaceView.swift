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
    @State private var renameDraft = ""
    @State private var showsRename = false
    @State private var showsDelete = false
    @State private var topicConversation: InquiryConversation?

    var body: some View {
        if support.isSupported {
            let modelTasks = MacApplicationRuntime.shared.modelTasks
            let pendingTasks = [modelTasks.currentTask].compactMap { $0 } + modelTasks.upcomingTasks
            let loadingBranchIDs = Set(pendingTasks.compactMap { $0.kind.userQuestionBranchID })
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    MacFloatingSidebar(selection: $selection, isCompact: sidebar.isCompact, showsFixture: showFixture,
                        conversations: conversations, loadingBranchIDs: loadingBranchIDs, openConversation: { id in
                        pendingQuote = nil
                        showFixture = false; conversationID = id; selection = .conversations
                    }, newConversation: {
                        showFixture = false
                        pendingQuote = nil
                        question = ""
                        selection = .conversations
                        conversationID = UUID()
                    }, openPreview: {
                        showFixture = true
                        selection = .conversations
                        conversationID = UUID()
                    }, activeConversationID: conversationID, openMenuID: conversationMenuID,
                        openMenu: { conversationMenuID = conversationMenuID == $0 ? nil : $0 })
                    .frame(width: sidebar.width(in: geometry.size.width))
                    .clipped()
                    .overlay(alignment: .trailing) {
                        MacSidebarResizeHandle(layout: $sidebar, windowWidth: geometry.size.width)
                    }
                    .zIndex(3) // Navigation stays above workspace content and floating cards.

                    if selection == .conversations {
                        MacConversationWorkspace(showsFixture: showFixture, conversationID: conversationID, question: $question,
                            initialQuote: pendingQuote, onInitialQuoteHandled: { pendingQuote = nil },
                            onNewConversation: {
                                pendingQuote = nil; question = ""; showFixture = false; conversationID = UUID()
                            }, onOpenInsights: { selection = .insights })
                            .id(conversationID)
                    } else if selection == .insights {
                        MacGlobalInsightWorkspace { concept, existingID in
                            pendingQuote = concept
                            var snapshot = CurrentConversationsStore.load() ?? InquiryPersistenceSnapshot(conversations: [], activeConversationID: nil)
                            let targetID: UUID
                            if let existingID { targetID = existingID }
                            else {
                                let conversation = InquiryConversation(branches: [ChatBranch(startingConcept: nil)])
                                snapshot.conversations.append(conversation)
                                targetID = conversation.id
                                question = ""
                            }
                            snapshot.activeConversationID = targetID
                            CurrentConversationsStore.save(snapshot)
                            conversations = snapshot.conversations
                            conversationID = targetID
                            showFixture = false
                            selection = .conversations
                        }
                    } else {
                        MacDestinationView(destination: selection)
                    }
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
            .onExitCommand { conversationMenuID = nil }
            .onChange(of: selection) { _, _ in conversationMenuID = nil }
            .onChange(of: sidebar.isCompact) { _, _ in conversationMenuID = nil }
            .onChange(of: conversationID) { _, _ in conversationMenuID = nil }
            .alert("Rename Conversation", isPresented: $showsRename) {
                TextField("Conversation name", text: $renameDraft)
                Button("Cancel", role: .cancel) { actionConversationID = nil }
                Button("Rename") {
                    if let id = actionConversationID { updateConversation(id, action: .rename(renameDraft)) }
                    actionConversationID = nil
                }
            }
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
                guard let id = notification.object as? UUID, conversationID == id else { return }
                pendingQuote = nil
                question = ""
                showFixture = false
                conversationID = MacSidebarConversationActions.sorted(conversations.filter { $0.id != id }).first?.id ?? UUID()
            }
            .environment(\.openModelTaskPage, { task in
                if let id = task.conversationID {
                    conversationID = id; showFixture = false; selection = .conversations
                } else { selection = .insights }
            })
            .environment(\.openReadingConversation, { id in
                conversationID = id; showFixture = false; selection = .conversations
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

    private func handleConversationAction(_ action: MacSidebarConversationMenuAction, _ conversation: InquiryConversation) {
        conversationMenuID = nil
        switch action {
        case .rename:
            actionConversationID = conversation.id
            renameDraft = conversation.title
            showsRename = true
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
            pendingQuote = nil
            question = ""
            showFixture = false
            conversationID = updated.activeConversationID ?? UUID()
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
