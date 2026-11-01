import SwiftUI

/// Study Topics on the Mac: browse, create, rename and delete topics, and open or start
/// the conversations filed under each one, its reference images and its Insight Tree.
struct MacStudyTopicsView: View {
    let conversations: [InquiryConversation]
    let onOpenConversation: (UUID) -> Void
    let onNewConversation: (UUID) -> Void
    let onTopicsChanged: () -> Void
    var onAsk: (ConceptDefinition, UUID?) -> Void = { _, _ in }
    var queuePopup: ModelTasksPopupState? = nil

    @State private var state: MacStudyTopicsState
    @State private var searchText = ""
    @State private var pendingDelete: StudyTopic?
    @State private var treeTopicID: UUID?
    @State private var showsFilePicker = false
    @State private var showsPhotoPicker = false
    @State private var showsAddConversation = false
    @State private var ownQueuePopup = ModelTasksPopupState()
    private let creationRequest: UUID?
    private let runtime: MacApplicationRuntime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(conversations: [InquiryConversation], onOpenConversation: @escaping (UUID) -> Void,
         onNewConversation: @escaping (UUID) -> Void, onTopicsChanged: @escaping () -> Void,
         onAsk: @escaping (ConceptDefinition, UUID?) -> Void = { _, _ in }, queuePopup: ModelTasksPopupState? = nil,
         topics: [StudyTopic] = StudyTopicStore.load(), selectedTopicID: UUID? = nil, creationRequest: UUID? = nil,
         state: MacStudyTopicsState? = nil, runtime: MacApplicationRuntime = .shared) {
        self.conversations = conversations
        self.onOpenConversation = onOpenConversation
        self.onNewConversation = onNewConversation
        self.onTopicsChanged = onTopicsChanged
        self.onAsk = onAsk
        self.queuePopup = queuePopup
        self.runtime = runtime
        self.creationRequest = creationRequest
        _state = State(initialValue: state ?? MacStudyTopicsState(topics: topics, selectedTopicID: selectedTopicID) {
            StudyTopicStore.save($0)
            onTopicsChanged()
        })
    }

    private var topics: [StudyTopic] { state.topics }
    private var selectedTopicID: UUID? { state.selectedTopicID }
    private var conversationTopicIDs: Set<UUID> { Set(conversations.compactMap(\.studyTopicID)) }
    private var selectedTopic: StudyTopic? { topics.first { $0.id == selectedTopicID } }

    /// Model Controls hold this page's actions: New Study Topic on the list, and on a topic
    /// New Conversation plus Add Existing Conversation, as on iPhone.
    private var pageActions: [MacPageControlAction] {
        MacStudyTopicPageActions.make(state: state, onNewConversation: onNewConversation,
                                     onAddConversation: { showsAddConversation = true })
    }

    private var visibleTopics: [StudyTopic] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sorted = topics.sorted { $0.createdAt > $1.createdAt }
        guard !query.isEmpty else { return sorted }
        return sorted.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.description.localizedCaseInsensitiveContains(query)
                || members(of: $0).contains { Self.title(of: $0).localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        Group {
            if let treeTopicID, let topic = topics.first(where: { $0.id == treeTopicID }) {
                MacGlobalInsightWorkspace(queuePopup: queuePopup, onAsk: onAsk, topicID: topic.id)
                    .id(topic.id)
                    .overlay(alignment: .topLeading) {
                        MacBackCapsule(title: String(localized: "Study Topics")) { self.treeTopicID = nil }
                    }
            } else {
                topicPages
            }
        }
        .onChange(of: creationRequest) { _, request in
            guard request != nil else { return }
            treeTopicID = nil
            state.create()
        }
    }

    private var topicPages: some View {
        MacCollectionScrollPage(artwork: selectedTopic == nil ? .studyTopics : nil) {
            if let topic = selectedTopic {
                detail(topic).transition(.opacity)
            } else {
                list.transition(.opacity)
            }
        }
        .onDisappear { state.discardUntouchedDraft(conversationTopicIDs: conversationTopicIDs) }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .springStandard, value: selectedTopicID)
        .overlay(alignment: .topLeading) {
            if selectedTopic != nil {
                MacBackCapsule(title: String(localized: "Study Topics")) { state.close(conversationTopicIDs: conversationTopicIDs) }
            }
        }
        .alert("Delete Study Topic?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                if let topic = pendingDelete { delete(topic) }
                pendingDelete = nil
            }
        } message: {
            Text("Its conversations stay in Recents.")
        }
        .onExitCommand { if selectedTopicID != nil { state.close(conversationTopicIDs: conversationTopicIDs) } }
        .modifier(MacAttachmentPickers(showsFiles: $showsFilePicker, showsPhotos: $showsPhotoPicker) { files in
            guard let id = selectedTopicID else { return }
            state.update(id) { $0.files.append(contentsOf: files) }
        })
        .onReceive(NotificationCenter.default.publisher(for: .macConversationSaved)) { _ in state.reload(StudyTopicStore.load()) }
        .sheet(isPresented: $showsAddConversation) {
            if let topic = selectedTopic {
                MacAddExistingConversationSheet(topicID: topic.id, conversations: conversations) { showsAddConversation = false }
            }
        }
        .background {
            MacPageControls(actions: pageActions, modelTasks: runtime.modelTasks,
                            queuePopup: queuePopup ?? ownQueuePopup)
        }
    }

    // MARK: List

    private var filedConversationCount: Int {
        let ids = Set(topics.map(\.id))
        return conversations.filter { !$0.isStudyTopic && $0.studyTopicID.map(ids.contains) == true }.count
    }

    @ViewBuilder private var list: some View {
        MacCollectionHeader(title: "Study Topics",
            description: "Bring related conversations together and follow an idea as it develops.",
            stats: topics.isEmpty ? [] : [
                MacCollectionStat(topics.count, "Topic", "Topics"),
                MacCollectionStat(filedConversationCount, "Conversation", "Conversations")
            ])
            // New Study Topic is the dashed card in the grid; the shortcut stays with the page.
            .background {
                Button("New Study Topic") { state.create() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

        if topics.isEmpty {
            MacStudyTopicPlaceholderGrid { state.create() }
        } else {
            VStack(alignment: .leading, spacing: 24) {
                MacCollectionSearchBar(title: String(localized: "All Topics"), searchText: $searchText,
                                       prompt: Text("Search Study Topics"))
                if visibleTopics.isEmpty {
                    Text("No Study Topics match “\(searchText)”.")
                        .paragraphFont()
                        .foregroundStyle(AngroveTheme.Colors.paragraphText)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: MacCollectionLayout.gridSpacing, alignment: .top)],
                              spacing: MacCollectionLayout.gridSpacing) {
                        ForEach(visibleTopics) { topic in
                            MacStudyTopicCard(topic: topic, members: members(of: topic), memberTitle: Self.title(of:),
                                onSelect: { state.open(topic.id) },
                                onRename: { state.open(topic.id, focusTitle: true) },
                                onDelete: { pendingDelete = topic },
                                onOpenConversation: { onOpenConversation($0.id) })
                                .macTopicConversationDrop(topicID: topic.id, onFiled: onTopicsChanged)
                        }
                    }
                }
            }
        }
    }

    // MARK: Detail

    @ViewBuilder private func detail(_ topic: StudyTopic) -> some View {
        let members = members(of: topic)
        MacStudyTopicDetailHeader(title: textBinding(topic.id, \.title), description: textBinding(topic.id, \.description),
            titleFocusRequest: state.titleFocusRequest, conversationCount: members.count) {
            Button("Insight Tree", systemImage: "point.3.connected.trianglepath.dotted") { state.retain(topic.id); treeTopicID = topic.id }
                .buttonStyle(MacSecondaryCapsuleButtonStyle())
                .help("Open the Insight Tree gathered from this topic’s conversations")
            // Add Images is hidden for now; the pickers and Reference Images section remain.
            MacActionMenu(entries: { [
                MacMenuEntry("Rename", symbol: "pencil.line") { state.open(topic.id, focusTitle: true) }, .divider,
                MacMenuEntry("Delete", symbol: "trash", destructive: true) { pendingDelete = topic }
            ] }) { MacCollectionOptionsLabel() }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityLabel("Topic options")
        }
        .id(topic.id)

        VStack(alignment: .leading, spacing: 20) {
            MacCollectionSectionTitle(title: String(localized: "Conversations"),
                detail: members.isEmpty ? nil : String(localized: "\(members.count) filed"))
            if members.isEmpty {
                MacTopicEmptyConversations { startConversation(in: topic.id) }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: MacCollectionLayout.gridSpacing, alignment: .top)],
                          spacing: MacCollectionLayout.gridSpacing) {
                    ForEach(members) { conversation in
                        MacConversationCardContent(
                            title: Self.title(of: conversation),
                            preview: MacConversationSummary.preview(of: conversation),
                            createdAt: conversation.createdAt,
                            topicTitle: nil,
                            answerCount: MacConversationSummary.answerCount(in: conversation),
                            isPinned: conversation.isPinned
                        ) {
                            // No options here yet; keep the strip the same height as the collection's cards.
                            Color.clear.frame(width: 0, height: AngroveTheme.Spacing.controlHeight)
                        }
                        .onTapGesture { onOpenConversation(conversation.id) }
                        .macCardHover()
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { onOpenConversation(conversation.id) }
                    }
                }
            }
        }
        // Drop a conversation anywhere in the section to file it here.
        .macTopicConversationDrop(topicID: topic.id, onFiled: onTopicsChanged)

        if !topic.files.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                MacCollectionSectionTitle(title: String(localized: "Reference Images"),
                    detail: String(localized: "\(topic.files.count) saved"))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)], alignment: .leading, spacing: 16) {
                    ForEach(topic.files) { file in
                        MacTopicImageTile(file: file) { removeFile(file.id, from: topic.id) }
                    }
                }
            }
        }
    }

    private func removeFile(_ fileID: UUID, from topicID: UUID) {
        state.update(topicID) { $0.files.removeAll { $0.id == fileID } }
    }

    private func members(of topic: StudyTopic) -> [InquiryConversation] {
        conversations.filter { $0.studyTopicID == topic.id && !$0.isStudyTopic }.reversed()
    }

    private func textBinding(_ topicID: UUID, _ keyPath: WritableKeyPath<StudyTopic, String>) -> Binding<String> {
        Binding(get: { state.topics.first { $0.id == topicID }?[keyPath: keyPath] ?? "" },
                set: { value in state.update(topicID) { $0[keyPath: keyPath] = value } })
    }

    private func startConversation(in topicID: UUID) {
        state.retain(topicID)
        onNewConversation(topicID)
    }

    private func delete(_ topic: StudyTopic) {
        state.remove(topic.id)
        var snapshots = StudyTopicInsightTreeStore.load()
        if snapshots.removeValue(forKey: topic.id.uuidString) != nil { StudyTopicInsightTreeStore.save(snapshots) }
        if let snapshot = CurrentConversationsStore.load(),
           let updated = MacSidebarConversationActions.unfiling(topic: topic.id, in: snapshot) {
            CurrentConversationsStore.save(updated)
        }
        onTopicsChanged()
        if selectedTopicID == topic.id { state.close(conversationTopicIDs: conversationTopicIDs) }
    }

    static func displayTitle(_ topic: StudyTopic) -> String {
        let title = topic.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Untitled Study Topic" : title
    }

    static func title(of conversation: InquiryConversation) -> String {
        let title = conversation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title != "New Conversation", !title.isEmpty { return title }
        for branch in conversation.branches {
            let candidate = branch.generatedBranchTitle ?? branch.topQuestionText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty { return candidate }
        }
        return title
    }
}

/// Files existing conversations that are not yet in a Study Topic into this one.
private struct MacAddExistingConversationSheet: View {
    let topicID: UUID
    let conversations: [InquiryConversation]
    let onDone: () -> Void
    @State private var query = ""
    @State private var selectedIDs: Set<UUID> = []

    private var candidates: [InquiryConversation] {
        let unfiled = MacSidebarConversationActions.sorted(conversations.filter { !$0.isStudyTopic && $0.studyTopicID == nil })
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? unfiled : unfiled.filter { MacStudyTopicsView.title(of: $0).localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MacPageHeading(title: "Add Existing Conversation")
            StudyTopicsSearchField(searchText: $query, prompt: Text("Search Conversations"))
            if candidates.isEmpty {
                Text("There are no conversations outside Study Topics.")
                    .paragraphFont()
                    .foregroundStyle(AngroveTheme.Colors.placeholderText)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(candidates) { conversation in
                            Button {
                                if selectedIDs.contains(conversation.id) { selectedIDs.remove(conversation.id) }
                                else { selectedIDs.insert(conversation.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    Text(MacStudyTopicsView.title(of: conversation))
                                        .font(AngroveTheme.Typography.bodyLarge)
                                        .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                                        .lineLimit(1)
                                    Spacer(minLength: 12)
                                    if selectedIDs.contains(conversation.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(AngroveTheme.Colors.lightGreen)
                                    }
                                }
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onDone() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedIDs.isEmpty)
            }
        }
        .padding(28)
        .frame(width: 460)
        .background(AngroveTheme.Colors.canvas)
    }

    private func add() {
        guard var snapshot = CurrentConversationsStore.load() else { return onDone() }
        for id in selectedIDs {
            if let updated = MacSidebarConversationActions.applying(.assignTopic(topicID), to: id, in: snapshot) { snapshot = updated }
        }
        CurrentConversationsStore.save(snapshot)
        NotificationCenter.default.post(name: .macConversationSaved, object: nil)
        onDone()
    }
}

/// The same actions are used from a blank topic onward; a name is never required to begin.
@MainActor enum MacStudyTopicPageActions {
    static func make(state: MacStudyTopicsState, onNewConversation: @escaping (UUID) -> Void,
                     onAddConversation: @escaping () -> Void) -> [MacPageControlAction] {
        guard let topic = state.topics.first(where: { $0.id == state.selectedTopicID }) else {
            return [MacPageControlAction(title: String(localized: "New Study Topic"), symbol: "plus") { state.create() }]
        }
        return [
            MacPageControlAction(title: String(localized: "New Conversation"), symbol: "plus") {
                state.retain(topic.id)
                onNewConversation(topic.id)
            },
            MacPageControlAction(title: String(localized: "Add Existing Conversation"), symbol: "bubble.left.and.bubble.right") {
                state.retain(topic.id)
                onAddConversation()
            }
        ]
    }
}
