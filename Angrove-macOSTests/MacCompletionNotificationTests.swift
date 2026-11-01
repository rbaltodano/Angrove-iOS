import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor
struct MacCompletionNotificationTests {
    @Test func completedQuestionsAppearElsewhereAndOpenTheirConversation() throws {
        let center = ModelCompletionNotificationCenter()
        var branch = ChatBranch(startingConcept: nil)
        branch.topQuestionText = "First question"
        branch.activeChatBlocks = [.user("  Follow-up question  ", [], []), .text("Answer")]
        let conversation = InquiryConversation(title: "Test", branches: [branch])
        let task = snapshot(kind: .userQuestion(branchID: branch.id, responseIndex: 1), conversationID: conversation.id)
        var opened: UUID?
        var openedBranch: UUID?
        MacCompletionNotifications.postQuestion(task, to: center, isViewing: { _ in true },
            isAppActive: true, conversation: conversation) { opened = $0; openedBranch = $1 }
        #expect(center.notifications.isEmpty)
        MacCompletionNotifications.postQuestion(task, to: center, isViewing: { _ in false },
            isAppActive: true, conversation: conversation) { opened = $0; openedBranch = $1 }
        let pill = try #require(center.notifications.first)
        #expect(pill.title == "Follow-up question")
        center.dismiss(id: pill.id)
        #expect(opened == nil)
        MacCompletionNotifications.postQuestion(task, to: center, isViewing: { _ in true },
            isAppActive: false, conversation: conversation) { opened = $0; openedBranch = $1 }
        center.open(id: try #require(center.notifications.first).id)
        #expect(opened == conversation.id)
        #expect(openedBranch == branch.id)
        #expect(center.notifications.isEmpty)
    }

    @Test func canceledAnswersAndMaintenanceDoNotPost() {
        let center = ModelCompletionNotificationCenter()
        var branch = ChatBranch(startingConcept: nil)
        branch.activeChatBlocks = [.text(questionCanceledResponseText)]
        let conversation = InquiryConversation(branches: [branch])
        for kind: ModelTaskKind in [.userQuestion(branchID: branch.id, responseIndex: 0), .updateInsightTree,
                                    .userQuestion(branchID: branch.id, responseIndex: -1)] {
            MacCompletionNotifications.postQuestion(snapshot(kind: kind, conversationID: conversation.id),
                to: center, isViewing: { _ in false }, isAppActive: true, conversation: conversation) { _, _ in
                    Issue.record("Unexpected open")
                }
        }
        #expect(center.notifications.isEmpty)
    }

    @Test func returnPromptsReplaceCancelAndPreserveCompletionPills() async throws {
        let center = ModelCompletionNotificationCenter()
        center.post(title: "Prudence", kind: .insightDefinition, postsSystemNotification: false) {}
        var returned = false
        let obsolete = center.schedulePageReturn(title: "Return to Home", returnPage: .home) {}
        let current = center.schedulePageReturn(title: "Return to Conversation", returnPage: .conversation) { returned = true }
        await obsolete.value
        await current.value
        #expect(center.notifications.count == 2)
        let pill = try #require(center.notifications.first { $0.kind == .pageReturn })
        center.open(id: pill.id)
        #expect(returned)
        let canceled = center.schedulePageReturn(title: "Return to Home", returnPage: .home) {}
        center.dismissPageReturn()
        await canceled.value
        #expect(center.notifications.count == 1)
        #expect(center.notifications.first?.kind == .insightDefinition)
    }

    @Test func notificationStackRendersAboveControlsInLightAndDark() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let center = ModelCompletionNotificationCenter()
            center.post(title: "What is practical wisdom?", postsSystemNotification: false) {}
            center.post(title: "Prudence", kind: .insightDefinition, postsSystemNotification: false) {}
            center.post(title: "Return to Conversation", kind: .pageReturn, returnPage: .conversation,
                        postsSystemNotification: false) {}
            let host = NSHostingView(rootView: NotificationFixture()
                .environment(\.modelCompletionNotifications, center).environment(\.colorScheme, scheme))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.contentView = nil; window.close() }
            try await Task.sleep(for: .milliseconds(300))
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: FileManager.default.temporaryDirectory.appending(path: "angrove-notifications-\(scheme == .light ? "light" : "dark").png"))
        }
    }

    private func snapshot(kind: ModelTaskKind, conversationID: UUID) -> ModelTaskSnapshot {
        ModelTaskSnapshot(id: UUID(), kind: kind, originPage: .conversation, conversationID: conversationID,
                          phase: .completed, funStatusText: nil, funLoadingStatusText: nil)
    }
}

private struct NotificationFixture: View {
    @State private var context = ContextCardState()
    @State private var queue = ModelTaskQueue()

    var body: some View {
        Color.clear
            .background {
                InquiryControlDock(isCanvasMode: false,
                    showFilePicker: .constant(false), showPhotoPicker: .constant(false), showCamera: .constant(false),
                    selectedPersonality: .constant("default"), isPersonalityMenuOpen: .constant(false), isAtBottom: true,
                    showsSendButton: false, showsAttachments: false,
                    onScrollToBottom: {}, onViewEntireCanvas: {}, onOpenInsights: {},
                    modelTasks: queue, keepsIdleModelStatus: true, contextCard: context)
            }
            .overlayPreferenceValue(ModelControlsPreferenceKey.self, alignment: .bottom) { configuration in
                ModelControlsHost(configuration: configuration)
            }
            .background(AngroveTheme.Colors.canvas)
    }
}
