import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

// Temporary: renders the redesigned collection pages with sample data for visual review.
@MainActor
struct ZZRedesignRenderTests {
    static let output = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "angrove-redesign")

    static func conversation(_ title: String, question: String, answer: String, daysAgo: Double,
                             topic: UUID? = nil, pinned: Bool = false) -> InquiryConversation {
        var branch = ChatBranch(startingConcept: nil)
        branch.topQuestionText = question
        branch.topQuestionSubmitted = true
        branch.activeChatBlocks = [.text(answer), .user("And how does that relate?", [], []), .text(answer)]
        return InquiryConversation(title: title, studyTopicID: topic, isPinned: pinned, branches: [branch],
                                   createdAt: Date().addingTimeInterval(-daysAgo * 86_400))
    }

    static let topics: [StudyTopic] = [
        StudyTopic(title: "The Desert Fathers", description: "Sayings, solitude and the early monastic tradition of Egypt and Syria.", createdAt: .now.addingTimeInterval(-86_400 * 3)),
        StudyTopic(title: "Summer Bible Study", description: "Notes for the Thursday group working through the Gospel of John.", createdAt: .now.addingTimeInterval(-86_400 * 12)),
        StudyTopic(title: "Aquinas on Virtue", description: "", createdAt: .now.addingTimeInterval(-86_400 * 30))
    ]

    static var conversations: [InquiryConversation] {
        let answer = "Prudence, for Aquinas, is right reason applied to action. It is the virtue that perfects practical judgment, letting the other moral virtues find their mean in concrete circumstances rather than in the abstract."
        return [
            conversation("Prudence as the Charioteer", question: "Why is prudence called the charioteer of the virtues?", answer: answer, daysAgo: 0.1, topic: topics[2].id, pinned: true),
            conversation("Abba Moses and the Basket of Sand", question: "What does the story of Abba Moses teach?", answer: "Abba Moses carried a leaking basket of sand to a council called to judge a brother, showing that his own faults ran out behind him unseen.", daysAgo: 0.3, topic: topics[0].id),
            conversation("The Prologue of John", question: "What does Logos mean in John 1?", answer: "In the opening of John's Gospel, the Logos is the eternal Word through whom all things were made, now made flesh.", daysAgo: 1.2, topic: topics[1].id),
            conversation("Grace and Nature", question: "Does grace destroy nature?", answer: "Grace does not destroy nature but perfects it, as the scholastic axiom puts it.", daysAgo: 3),
            conversation("Acedia in the Noonday", question: "What is the noonday demon?", answer: "Evagrius names acedia the noonday demon: a restless weariness that makes the monk's cell unbearable.", daysAgo: 4, topic: topics[0].id),
            conversation("The Woman at the Well", question: "Why does Jesus speak with the Samaritan woman?", answer: answer, daysAgo: 9, topic: topics[1].id),
            conversation("Augustine's Restless Heart", question: "What did Augustine mean by a restless heart?", answer: "Our heart is restless until it rests in God: the opening of the Confessions frames the whole work as a search.", daysAgo: 40, pinned: true),
            conversation("Natural Law", question: "What is natural law?", answer: answer, daysAgo: 70)
        ]
    }

    static var windowBranch: ChatBranch {
        var branch = ChatBranch(startingConcept: nil)
        branch.topQuestionText = "Why is prudence called the charioteer of the virtues?"
        branch.topQuestionSubmitted = true
        branch.activeChatBlocks = [.text("Prudence, for Aquinas, is right reason applied to action. It perfects practical judgment, letting the other moral virtues find their mean in concrete circumstances.")]
        return branch
    }

    static var boards: [WorktreeDocument] {
        func item(_ x: CGFloat, _ y: CGFloat, _ text: String = "", heading: Bool = false, window: Bool = false,
                  size: CGSize? = nil, insight: Bool = false) -> WorktreeStoredItem {
            WorktreeStoredItem(id: UUID(), origin: CGPoint(x: x, y: y), text: text, size: size, label: nil, isHeading: heading,
                               isHelp: insight ? true : nil, image: nil, insight: nil, sourceID: nil, sourceConversationID: nil,
                               sourceTitle: nil, visibleTurnLimit: nil, conversationID: nil,
                               branches: nil, promotedIDs: nil, photoLayout: nil)
        }
        return [
            WorktreeDocument(title: "Virtue Map", updatedAt: .now.addingTimeInterval(-600), items: [
                item(0, 0, "The Cardinal Virtues", heading: true),
                item(0, 80, window: true, size: CGSize(width: 400, height: 380)),
                item(460, 80, window: true, size: CGSize(width: 400, height: 300)),
                item(460, 420, "Prudence perfects practical reason; justice the will; fortitude and temperance the passions."),
                item(920, 120, insight: true)
            ]),
            WorktreeDocument(title: "Gospel of John Outline", updatedAt: .now.addingTimeInterval(-86_400 * 2), items: [
                item(0, 0, "Book of Signs", heading: true), item(0, 70, "Water into wine at Cana"), item(0, 120, "The healing at Bethesda"),
                item(0, 170, "Feeding of the five thousand"), item(520, 0, "Book of Glory", heading: true),
                item(520, 70, "The farewell discourse and the prayer for unity among the disciples"), item(520, 160, window: true, size: CGSize(width: 360, height: 260))
            ]),
            WorktreeDocument(title: nil, updatedAt: .now.addingTimeInterval(-86_400 * 20), items: [])
        ]
    }

    static func render<V: View>(_ view: V, _ name: String, width: CGFloat = 1100, height: CGFloat = 1500, dark: Bool = false) async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let size = CGSize(width: width, height: height)
        let host = NSHostingView(rootView: view.frame(width: width, height: height))
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFront(nil)
        try await Task.sleep(for: .seconds(3))
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: output.appending(path: "\(name).png"))
        window.orderOut(nil)
        print("RENDERED \(output.appending(path: "\(name).png").path)")
    }

    @Test func renderBoardCardsWithoutPreviews() async throws {
        let library = WorktreeLibrary(documents: Self.boards, persistsSnapshots: false)
        let boards = MacWorktreeHomeView(library: library, queuePopup: ModelTasksPopupState())
        try await Self.render(boards, "boards-no-preview-light", height: 1100)
        try await Self.render(boards, "boards-no-preview-dark", height: 1100, dark: true)
        try await Self.render(boards, "boards-no-preview-narrow", width: 700, height: 1500)
        try await Self.render(MacWorktreeHomeView(library: WorktreeLibrary(documents: [], persistsSnapshots: false),
            queuePopup: ModelTasksPopupState()), "boards-no-preview-empty", height: 900)
    }

    @Test func snapshotOne() async throws {
        print("SNAP test begin")
        let library = WorktreeLibrary(documents: Self.boards, persistsSnapshots: false)
        print("SNAP library made")
        await library.refreshSnapshots()
        print("SNAP done \(library.snapshots.count)")
    }

    @Test func renderPages() async throws {
        let conversations = Self.conversations
        let list = MacConversationsListView(conversations: conversations, activeConversationID: conversations[0].id,
                                            onOpen: { _ in }, onNew: {}, onAction: { _, _ in }, topics: Self.topics)
        try await Self.render(list, "conversations-light")
        try await Self.render(list, "conversations-dark", dark: true)
        try await Self.render(list, "conversations-narrow", width: 700, height: 1700)

        let topics = MacStudyTopicsView(conversations: conversations, onOpenConversation: { _ in }, onNewConversation: { _ in },
                                        onTopicsChanged: {}, topics: Self.topics)
        try await Self.render(topics, "topics-light", height: 1100)
        try await Self.render(topics, "topics-dark", height: 1100, dark: true)
        try await Self.render(topics, "topics-narrow", width: 700, height: 1700)
        let detail = MacStudyTopicsView(conversations: conversations, onOpenConversation: { _ in }, onNewConversation: { _ in },
                                        onTopicsChanged: {}, topics: Self.topics, selectedTopicID: Self.topics[0].id)
        try await Self.render(detail, "topic-detail-light", height: 1100)
        try await Self.render(detail, "topic-detail-dark", height: 1100, dark: true)

        let library = WorktreeLibrary(documents: Self.boards, persistsSnapshots: false)
        await library.refreshSnapshots()
        #expect(library.snapshots.isEmpty) // Offscreen snapshots are disabled; cards use drawn previews.
        let boards = MacWorktreeHomeView(library: library, queuePopup: ModelTasksPopupState())
        try await Self.render(boards, "boards-light", height: 1100)
        try await Self.render(boards, "boards-dark", height: 1100, dark: true)
        try await Self.render(boards, "boards-narrow", width: 700, height: 1500)

        try await Self.render(MacConversationsListView(conversations: [], activeConversationID: UUID(), onOpen: { _ in },
                                                       onNew: {}, onAction: { _, _ in }, topics: []), "conversations-empty", height: 800)
        try await Self.render(MacStudyTopicsView(conversations: [], onOpenConversation: { _ in }, onNewConversation: { _ in },
                                                 onTopicsChanged: {}, topics: []), "topics-empty", height: 800)
        try await Self.render(MacWorktreeHomeView(library: WorktreeLibrary(documents: [], persistsSnapshots: false), queuePopup: ModelTasksPopupState()),
                              "boards-empty", height: 900)
    }
}
