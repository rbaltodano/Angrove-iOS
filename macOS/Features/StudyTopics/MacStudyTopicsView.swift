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

    @State private var topics: [StudyTopic]
    @State private var searchText = ""
    @State private var selectedTopicID: UUID?
    @State private var editor: MacStudyTopicEditor?
    @State private var pendingDelete: StudyTopic?
    @State private var treeTopicID: UUID?
    @State private var showsFilePicker = false
    @State private var showsPhotoPicker = false
    @State private var showsAddConversation = false
    @State private var ownQueuePopup = ModelTasksPopupState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(conversations: [InquiryConversation], onOpenConversation: @escaping (UUID) -> Void,
         onNewConversation: @escaping (UUID) -> Void, onTopicsChanged: @escaping () -> Void,
         onAsk: @escaping (ConceptDefinition, UUID?) -> Void = { _, _ in }, queuePopup: ModelTasksPopupState? = nil,
         topics: [StudyTopic] = StudyTopicStore.load(), selectedTopicID: UUID? = nil) {
        self.conversations = conversations
        self.onOpenConversation = onOpenConversation
        self.onNewConversation = onNewConversation
        self.onTopicsChanged = onTopicsChanged
        self.onAsk = onAsk
        self.queuePopup = queuePopup
        _topics = State(initialValue: topics)
        _selectedTopicID = State(initialValue: selectedTopicID)
    }

    private var selectedTopic: StudyTopic? { topics.first { $0.id == selectedTopicID } }

    /// Model Controls hold this page's actions: New Study Topic on the list, and on a topic
    /// New Conversation plus Add Existing Conversation, as on iPhone.
    private var pageActions: [MacPageControlAction] {
        guard let topic = selectedTopic else {
            return [MacPageControlAction(title: String(localized: "New Study Topic"), symbol: "plus") { editor = MacStudyTopicEditor(topic: nil) }]
        }
        return [
            MacPageControlAction(title: String(localized: "New Conversation"), symbol: "plus") { onNewConversation(topic.id) },
            MacPageControlAction(title: String(localized: "Add Existing Conversation"), symbol: "bubble.left.and.bubble.right") { showsAddConversation = true }
        ]
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

    private var topicPages: some View {
        MacCollectionScrollPage {
            if let topic = selectedTopic {
                detail(topic).transition(.opacity)
            } else {
                list.transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .springStandard, value: selectedTopicID)
        .overlay(alignment: .topLeading) {
            if selectedTopic != nil {
                MacBackCapsule(title: String(localized: "Study Topics")) { selectedTopicID = nil }
            }
        }
        .sheet(item: $editor) { editor in
            MacStudyTopicEditorSheet(editor: editor) { title, description in save(editor, title: title, description: description) }
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
        .onExitCommand { if selectedTopicID != nil { selectedTopicID = nil } }
        .modifier(MacAttachmentPickers(showsFiles: $showsFilePicker, showsPhotos: $showsPhotoPicker) { files in
            guard let id = selectedTopicID, let index = topics.firstIndex(where: { $0.id == id }) else { return }
            topics[index].files.append(contentsOf: files)
            StudyTopicStore.save(topics)
        })
        .onReceive(NotificationCenter.default.publisher(for: .macConversationSaved)) { _ in topics = StudyTopicStore.load() }
        .sheet(isPresented: $showsAddConversation) {
            if let topic = selectedTopic {
                MacAddExistingConversationSheet(topicID: topic.id, conversations: conversations) { showsAddConversation = false }
            }
        }
        .background {
            MacPageControls(actions: pageActions, modelTasks: MacApplicationRuntime.shared.modelTasks,
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
                MacCollectionStat(filedConversationCount, "Conversation", "Conversations"),
                MacCollectionStat(topics.reduce(0) { $0 + $1.files.count }, "Image", "Images")
            ])
            // New Study Topic is the dashed card in the grid; the shortcut stays with the page.
            .background {
                Button("New Study Topic") { editor = MacStudyTopicEditor(topic: nil) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

        if topics.isEmpty {
            MacStudyTopicPlaceholderGrid { editor = MacStudyTopicEditor(topic: nil) }
        } else {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    MacCollectionSectionTitle(title: String(localized: "All Topics"))
                        .fixedSize()
                    Spacer(minLength: 24)
                    StudyTopicsSearchField(searchText: $searchText, prompt: Text("Search Study Topics"))
                        .frame(maxWidth: 360)
                }
                if visibleTopics.isEmpty {
                    Text("No Study Topics match “\(searchText)”.")
                        .paragraphFont()
                        .foregroundStyle(AngroveTheme.Colors.paragraphText)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: MacCollectionLayout.gridSpacing, alignment: .top)],
                              spacing: MacCollectionLayout.gridSpacing) {
                        ForEach(visibleTopics) { topic in
                            MacStudyTopicCard(topic: topic, members: members(of: topic), memberTitle: Self.title(of:),
                                onSelect: { selectedTopicID = topic.id },
                                onRename: { editor = MacStudyTopicEditor(topic: topic) },
                                onDelete: { pendingDelete = topic },
                                onOpenConversation: { onOpenConversation($0.id) })
                        }
                    }
                }
            }
        }
    }

    // MARK: Detail

    @ViewBuilder private func detail(_ topic: StudyTopic) -> some View {
        let members = members(of: topic)
        MacCollectionHeader(eyebrow: "Study Topic", title: Self.displayTitle(topic),
            description: topic.description.isEmpty
                ? String(localized: "Start a conversation here, or file one from its menu in the sidebar.")
                : topic.description,
            stats: [
                MacCollectionStat(members.count, "Conversation", "Conversations"),
                MacCollectionStat(topic.files.count, "Image", "Images")
            ]) {
            Button("Insight Tree", systemImage: "leaf") { treeTopicID = topic.id }
                .buttonStyle(MacSecondaryCapsuleButtonStyle())
                .help("Open the Insight Tree gathered from this topic’s conversations")
            MacActionMenu(entries: { [
                MacMenuEntry("Photos…", symbol: "photo.on.rectangle") { showsPhotoPicker = true },
                MacMenuEntry("Image File…", symbol: "folder") { showsFilePicker = true }
            ] }) { Label("Add Images", systemImage: "photo.badge.plus") }
                .buttonStyle(MacSecondaryCapsuleButtonStyle())
                .fixedSize()
            MacActionMenu(entries: { [
                MacMenuEntry("Rename", symbol: "pencil.line") { editor = MacStudyTopicEditor(topic: topic) }, .divider,
                MacMenuEntry("Delete", symbol: "trash", destructive: true) { pendingDelete = topic }
            ] }) { MacCollectionOptionsLabel() }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityLabel("Topic options")
        }

        VStack(alignment: .leading, spacing: 20) {
            MacCollectionSectionTitle(title: String(localized: "Conversations"),
                detail: members.isEmpty ? nil : String(localized: "\(members.count) filed"))
            if members.isEmpty {
                MacTopicEmptyConversations { onNewConversation(topic.id) }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(members.enumerated()), id: \.element.id) { index, conversation in
                        if index > 0 {
                            Rectangle().fill(AngroveTheme.Colors.divider).frame(height: 1).padding(.horizontal, 28)
                        }
                        MacTopicConversationRow(index: index + 1, title: Self.title(of: conversation),
                            preview: MacHomePreviewText.plainText(from: HomeDashboardContent.latestText(in: conversation)),
                            date: conversation.createdAt, isPinned: conversation.isPinned) {
                            onOpenConversation(conversation.id)
                        }
                    }
                }
                .padding(.vertical, 8)
                .macCollectionCard()
            }
        }

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
        guard let index = topics.firstIndex(where: { $0.id == topicID }) else { return }
        topics[index].files.removeAll { $0.id == fileID }
        StudyTopicStore.save(topics)
    }

    private func members(of topic: StudyTopic) -> [InquiryConversation] {
        conversations.filter { $0.studyTopicID == topic.id && !$0.isStudyTopic }.reversed()
    }

    private func save(_ editor: MacStudyTopicEditor, title: String, description: String) {
        if let id = editor.topic?.id, let index = topics.firstIndex(where: { $0.id == id }) {
            topics[index].title = title
            topics[index].description = description
        } else {
            let topic = StudyTopic(title: title, description: description)
            topics.append(topic)
            selectedTopicID = topic.id
        }
        StudyTopicStore.save(topics)
        onTopicsChanged()
        self.editor = nil
    }

    private func delete(_ topic: StudyTopic) {
        topics.removeAll { $0.id == topic.id }
        StudyTopicStore.save(topics)
        var snapshots = StudyTopicInsightTreeStore.load()
        if snapshots.removeValue(forKey: topic.id.uuidString) != nil { StudyTopicInsightTreeStore.save(snapshots) }
        if let snapshot = CurrentConversationsStore.load(),
           let updated = MacSidebarConversationActions.unfiling(topic: topic.id, in: snapshot) {
            CurrentConversationsStore.save(updated)
        }
        onTopicsChanged()
        if selectedTopicID == topic.id { selectedTopicID = nil }
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

struct MacStudyTopicEditor: Identifiable {
    let id = UUID()
    let topic: StudyTopic?
}

private struct MacStudyTopicEditorSheet: View {
    let editor: MacStudyTopicEditor
    let onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @FocusState private var titleFocused: Bool

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            MacPageHeading(title: editor.topic == nil ? "New Study Topic" : "Rename Study Topic")
            Form {
                TextField("Name", text: $title, prompt: Text("e.g. Summer Bible Study"))
                    .macPlainField()
                    .focused($titleFocused)
                TextField("Description", text: $description, prompt: Text("Briefly describe this topic"), axis: .vertical)
                    .macPlainField()
                    .lineLimit(3...6)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    onSave(trimmedTitle, description.trimmingCharacters(in: .whitespacesAndNewlines))
                } label: { BlurSwapText(editor.topic == nil ? "Create" : "Save") }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedTitle.isEmpty)
            }
        }
        .padding(28)
        .frame(width: 420)
        .background(AngroveTheme.Colors.canvas)
        .onAppear {
            title = editor.topic?.title ?? ""
            description = editor.topic?.description ?? ""
            titleFocused = true
        }
    }
}
