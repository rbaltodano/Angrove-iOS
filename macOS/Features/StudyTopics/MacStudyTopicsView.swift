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

    @State private var topics = StudyTopicStore.load()
    @State private var searchText = ""
    @State private var selectedTopicID: UUID?
    @State private var editor: MacStudyTopicEditor?
    @State private var pendingDelete: StudyTopic?
    @State private var treeTopicID: UUID?
    @State private var showsFilePicker = false
    @State private var showsPhotoPicker = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedTopic: StudyTopic? { topics.first { $0.id == selectedTopicID } }

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
        ScrollView {
            VStack(alignment: .leading, spacing: AngroveTheme.Spacing.cardPadding) {
                if let topic = selectedTopic { detail(topic) } else { list }
            }
            .frame(maxWidth: MacConversationStyle.pageContentMaxWidth, alignment: .leading)
            .padding(.top, MacConversationStyle.pageTopPadding)
            .padding(.bottom, AngroveTheme.Spacing.illustratedCardPadding)
            .padding(.horizontal, MacConversationStyle.pageHorizontalPadding)
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .springStandard, value: selectedTopicID)
        }
        .background(AngroveTheme.Colors.canvas)
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
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: AngroveTheme.Spacing.cardPadding) {
            HStack(alignment: .firstTextBaseline) {
                MacPageHeading(title: "Study Topics", font: MacPageHeading.pageFont)
                Spacer()
                Button("New Study Topic", systemImage: "plus") { editor = MacStudyTopicEditor(topic: nil) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .help("New Study Topic (⇧⌘N)")
            }
            if !topics.isEmpty {
                TextField("Search Study Topics", text: $searchText)
                    .macPlainField()
                    .frame(maxWidth: 320)
            }
            if topics.isEmpty {
                emptyState
            } else if visibleTopics.isEmpty {
                Text("No Study Topics match “\(searchText)”.").paragraphFont().settingsTextReveal()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 20, alignment: .top)], spacing: 20) {
                    ForEach(visibleTopics) { topic in
                        StudyTopicCard(topic: topic, subItems: members(of: topic), subItemTitle: Self.title(of:),
                            onSelect: { selectedTopicID = topic.id },
                            onRename: { editor = MacStudyTopicEditor(topic: topic) },
                            onDelete: { pendingDelete = topic },
                            onSelectSubItem: { onOpenConversation($0.id) })
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "square.stack")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AngroveTheme.Colors.lightGreen)
            Text("Group related conversations into a Study Topic to return to a subject over time.")
                .paragraphFont()
                .settingsTextReveal()
        }
        .padding(.top, 8)
    }

    private func detail(_ topic: StudyTopic) -> some View {
        let members = members(of: topic)
        return VStack(alignment: .leading, spacing: AngroveTheme.Spacing.cardPadding) {
            HStack(alignment: .firstTextBaseline) {
                MacPageHeading(title: Self.displayTitle(topic), font: MacPageHeading.pageFont)
                Spacer()
                MacActionMenu(entries: { [
                    MacMenuEntry("Rename", symbol: "pencil.line") { editor = MacStudyTopicEditor(topic: topic) }, .divider,
                    MacMenuEntry("Delete", symbol: "trash", destructive: true) { pendingDelete = topic }
                ] }) { Image(systemName: "ellipsis") }
                    .fixedSize()
                    .accessibilityLabel("Topic options")
            }
            if !topic.description.isEmpty {
                Text(topic.description).paragraphFont().settingsTextReveal()
            }
            HStack(spacing: 12) {
                Button("New Conversation", systemImage: "plus") { onNewConversation(topic.id) }
                Button("Insight Tree", systemImage: "leaf") { treeTopicID = topic.id }
                    .help("Open the Insight Tree gathered from this topic’s conversations")
                MacActionMenu(entries: { [
                    MacMenuEntry("Photos…", symbol: "photo.on.rectangle") { showsPhotoPicker = true },
                    MacMenuEntry("Image File…", symbol: "folder") { showsFilePicker = true }
                ] }) { Label("Add Images", systemImage: "photo.badge.plus") }
                .fixedSize()
            }
            if !topic.files.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Files")
                        .font(.custom("Figtree-Bold", size: 14))
                        .foregroundStyle(AngroveTheme.Colors.paragraphText)
                    ScrollView(.horizontal) {
                        MacAttachmentStrip(files: topic.files) { fileID in removeFile(fileID, from: topic.id) }
                            .padding(8)
                    }
                    .scrollIndicators(.automatic)
                }
            }
            if members.isEmpty {
                Text("No conversations yet. Start one here, or add one from its menu in the sidebar.")
                    .paragraphFont()
                    .settingsTextReveal()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(members) { conversation in
                        Button { onOpenConversation(conversation.id) } label: {
                            HStack {
                                Text(Self.title(of: conversation))
                                    .font(.custom("Figtree-Bold", size: 15))
                                    .foregroundStyle(AngroveTheme.Colors.headingText)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(AngroveTheme.Colors.placeholderText)
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if conversation.id != members.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 20)
                .background(AngroveTheme.Colors.canvasSecondary, in: RoundedRectangle(cornerRadius: AngroveTheme.Spacing.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: AngroveTheme.Spacing.cardRadius).strokeBorder(AngroveTheme.Colors.border, lineWidth: 1))
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
