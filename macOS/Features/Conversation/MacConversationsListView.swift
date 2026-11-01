import SwiftUI

/// Every saved conversation on one page: where you left off, then the rest as cards grouped by
/// when they began. Recents in the sidebar still open a conversation directly.
struct MacConversationsListView: View {
    let conversations: [InquiryConversation]
    let activeConversationID: UUID
    var onOpen: (UUID) -> Void
    var onNew: () -> Void
    var onAction: (MacSidebarConversationMenuAction, InquiryConversation) -> Void
    var queuePopup: ModelTasksPopupState? = nil
    @State private var ownQueuePopup = ModelTasksPopupState()

    @State private var searchText = ""
    @State private var filter: MacConversationFilter = .all
    @State private var topics: [StudyTopic]

    init(conversations: [InquiryConversation], activeConversationID: UUID, onOpen: @escaping (UUID) -> Void,
         onNew: @escaping () -> Void, onAction: @escaping (MacSidebarConversationMenuAction, InquiryConversation) -> Void,
         queuePopup: ModelTasksPopupState? = nil, topics: [StudyTopic] = StudyTopicStore.load()) {
        self.conversations = conversations
        self.activeConversationID = activeConversationID
        self.onOpen = onOpen
        self.onNew = onNew
        self.onAction = onAction
        self.queuePopup = queuePopup
        _topics = State(initialValue: topics)
    }

    private var saved: [InquiryConversation] {
        conversations.filter { !$0.isStudyTopic && HomeConversationResume.hasContent($0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var visible: [InquiryConversation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return saved.filter { conversation in
            guard filter.matches(conversation) else { return false }
            guard !query.isEmpty else { return true }
            return MacStudyTopicsView.title(of: conversation).localizedCaseInsensitiveContains(query)
                || HomeDashboardContent.latestText(in: conversation).localizedCaseInsensitiveContains(query)
                || topicTitle(for: conversation)?.localizedCaseInsensitiveContains(query) == true
        }
    }

    private var featured: InquiryConversation? {
        guard filter == .all, searchText.isEmpty else { return nil }
        return HomeConversationResume.featuredConversation(in: saved, activeConversationID: activeConversationID)
    }

    private var stats: [MacCollectionStat] {
        guard !saved.isEmpty else { return [] }
        return [
            MacCollectionStat(saved.count, "Conversation", "Conversations"),
            MacCollectionStat(saved.filter(\.isPinned).count, "Pinned", "Pinned"),
            MacCollectionStat(saved.filter { $0.studyTopicID != nil }.count, "In Study Topics", "In Study Topics")
        ]
    }

    var body: some View {
        MacCollectionScrollPage(artwork: .conversations) {
            // New Conversation lives in Model Controls; the space beside the heading is left
            // open for artwork.
            MacCollectionHeader(title: "Conversations",
                description: "Return to an inquiry, continue a thought, or start a new conversation.",
                stats: stats)

            if saved.isEmpty {
                MacFirstConversationCard(onStart: onNew)
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    MacCollectionSearchBar(title: String(localized: "All Conversations"), searchText: $searchText,
                                           prompt: Text("Search Conversations"))
                    MacCollectionTabs(tabs: MacConversationFilter.allCases.map { ($0, $0.label) }, selection: $filter)

                    VStack(alignment: .leading, spacing: 40) {
                        if let featured {
                            VStack(alignment: .leading, spacing: 20) {
                                MacCollectionSectionTitle(title: String(localized: "Where You Left Off"))
                                MacConversationCard(conversation: featured, topicTitle: topicTitle(for: featured),
                                    onOpen: { onOpen(featured.id) },
                                    onAction: { onAction($0, featured) })
                            }
                            .transition(.blurFade)
                        }
                        if visible.isEmpty {
                            Text(searchText.isEmpty ? filter.emptyMessage : String(localized: "No conversations match “\(searchText)”."))
                                .paragraphFont()
                                .foregroundStyle(AngroveTheme.Colors.paragraphText)
                        } else {
                            ForEach(MacConversationSection.grouping(visible)) { section in
                                VStack(alignment: .leading, spacing: 20) {
                                    MacCollectionSectionTitle(title: section.title,
                                        detail: section.conversations.count == 1 ? String(localized: "1 conversation")
                                            : String(localized: "\(section.conversations.count) conversations"))
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: MacCollectionLayout.gridSpacing, alignment: .top)],
                                              spacing: MacCollectionLayout.gridSpacing) {
                                        ForEach(section.conversations) { conversation in
                                            MacConversationCard(conversation: conversation, topicTitle: topicTitle(for: conversation),
                                                onOpen: { onOpen(conversation.id) },
                                                onAction: { onAction($0, conversation) })
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 16)
                }
                .animation(.springStandard, value: filter)
            }
        }
        .animation(.springStandard, value: featured?.id)
        .onReceive(NotificationCenter.default.publisher(for: .macConversationSaved)) { _ in topics = StudyTopicStore.load() }
        .background {
            MacPageControls(actions: [MacPageControlAction(title: String(localized: "New Conversation"), symbol: "plus", action: onNew)],
                modelTasks: MacApplicationRuntime.shared.modelTasks, queuePopup: queuePopup ?? ownQueuePopup)
        }
    }

    private func topicTitle(for conversation: InquiryConversation) -> String? {
        guard let id = conversation.studyTopicID, let topic = topics.first(where: { $0.id == id }) else { return nil }
        return MacStudyTopicsView.displayTitle(topic)
    }
}

enum MacConversationFilter: CaseIterable, Hashable {
    case all, pinned, filed

    var label: String {
        switch self {
        case .all: String(localized: "All")
        case .pinned: String(localized: "Pinned")
        case .filed: String(localized: "In Study Topics")
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: String(localized: "No conversations yet.")
        case .pinned: String(localized: "Pin a conversation from its menu to keep it here.")
        case .filed: String(localized: "File a conversation under a Study Topic from its menu.")
        }
    }

    func matches(_ conversation: InquiryConversation) -> Bool {
        switch self {
        case .all: true
        case .pinned: conversation.isPinned
        case .filed: conversation.studyTopicID != nil
        }
    }
}

/// Conversations bucketed by the day they began: Today, Yesterday, This Week, This Month, then
/// by calendar month.
struct MacConversationSection: Identifiable, Equatable {
    let title: String
    let conversations: [InquiryConversation]
    var id: String { title }

    static func grouping(_ conversations: [InquiryConversation], now: Date = .now,
                         calendar: Calendar = .current) -> [MacConversationSection] {
        let today = calendar.startOfDay(for: now)
        var order: [String] = []
        var buckets: [String: [InquiryConversation]] = [:]
        for conversation in conversations.sorted(by: { $0.createdAt > $1.createdAt }) {
            let day = calendar.startOfDay(for: conversation.createdAt)
            let age = calendar.dateComponents([.day], from: day, to: today).day ?? 0
            let title: String = switch age {
            case ..<1: String(localized: "Today")
            case 1: String(localized: "Yesterday")
            case 2..<7: String(localized: "This Week")
            case 7..<30: String(localized: "This Month")
            default: conversation.createdAt.formatted(.dateTime.month(.wide).year())
            }
            if buckets[title] == nil { order.append(title) }
            buckets[title, default: []].append(conversation)
        }
        return order.map { MacConversationSection(title: $0, conversations: buckets[$0] ?? []) }
    }
}

enum MacConversationSummary {
    static func answerCount(in conversation: InquiryConversation) -> Int {
        conversation.branches.reduce(0) { total, branch in
            total + branch.activeChatBlocks.filter { if case .text = $0 { true } else { false } }.count
        }
    }

    static func preview(of conversation: InquiryConversation) -> String {
        MacHomePreviewText.plainText(from: HomeDashboardContent.latestText(in: conversation))
    }
}

/// Editorial conversation card, retaining the collection’s existing actions.
private struct MacConversationCard: View {
    let conversation: InquiryConversation
    let topicTitle: String?
    var onOpen: () -> Void
    var onAction: (MacSidebarConversationMenuAction) -> Void

    private var menuEntries: [MacMenuEntry] {
        [MacMenuEntry("Open", symbol: "arrow.up.right", action: onOpen), .divider]
            + [MacSidebarConversationMenuAction.rename, .pin, .topic, .delete].flatMap { action -> [MacMenuEntry] in
                let entry = MacMenuEntry(action.title(for: conversation), symbol: action.symbol(for: conversation),
                                         destructive: action == .delete) { onAction(action) }
                return action == .delete ? [.divider, entry] : [entry]
            }
    }

    var body: some View {
        MacConversationCardContent(
            title: MacStudyTopicsView.title(of: conversation),
            preview: MacConversationSummary.preview(of: conversation),
            createdAt: conversation.createdAt,
            topicTitle: topicTitle,
            answerCount: MacConversationSummary.answerCount(in: conversation),
            isPinned: conversation.isPinned
        ) {
            MacActionMenu(entries: { menuEntries }) {
                MacCollectionCardOptionsLabel()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Conversation options")
        }
        .onTapGesture(perform: onOpen)
        .macCardHover()
        .macContextMenu { menuEntries }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Open"), onOpen)
    }
}

/// Shown before anything has been asked.
private struct MacFirstConversationCard: View {
    var onStart: () -> Void

    var body: some View {
        Button(action: onStart) {
            HStack(alignment: .center, spacing: 28) {
                Image(systemName: AppPage.openConversations.sidebarIconName)
                    .angroveIcon(.hero)
                    .foregroundStyle(AngroveTheme.Colors.lightGreen)
                    .frame(width: 64, height: 64)
                    .background(AngroveTheme.Colors.canvasSecondary, in: Circle())
                    .overlay(Circle().stroke(AngroveTheme.Colors.controlBorder, lineWidth: 1))
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ask your first question")
                        .font(AngroveTheme.Typography.title)
                        .foregroundStyle(AngroveTheme.Colors.headingText)
                    Text("Every conversation you begin is kept here, grouped by when you started it.")
                        .paragraphFont()
                        .foregroundStyle(AngroveTheme.Colors.paragraphText)
                        .lineSpacing(5)
                }
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.leading)
            .padding(36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: AngroveTheme.Spacing.cardRadius, style: .continuous)
                    .strokeBorder(AngroveTheme.Colors.controlBorder, style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
            }
            .contentShape(RoundedRectangle(cornerRadius: AngroveTheme.Spacing.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .macCardHover()
    }
}
