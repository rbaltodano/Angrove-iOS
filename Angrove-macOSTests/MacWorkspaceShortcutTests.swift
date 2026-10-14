import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor
struct MacWorkspaceShortcutTests {
    @Test func recentShortcutsExcludeTopicsIgnorePinsAndStopAtNine() {
        let conversations = (0..<12).map { InquiryConversation(title: "Conversation \($0)", isPinned: $0 == 0) }
        let topic = InquiryConversation(title: "Topic", isStudyTopic: true)
        #expect(MacWorkspaceCommandTarget.recentIDs(in: conversations + [topic]) == conversations.reversed().prefix(9).map(\.id))
        #expect(MacWorkspaceCommandTarget.recentIDs(in: []).isEmpty)
        #expect(MacWorkspaceCommandTarget.recentIDs(in: [conversations[0]]) == [conversations[0].id])
    }

    @Test func repeatedCommandsProduceDistinctRequests() {
        var request: MacShortcutRequest?
        let target = MacWorkspaceCommandTarget(request: Binding(get: { request }, set: { request = $0 }), recentConversationIDs: [])
        target.send(.focusQuestion)
        let first = request
        target.send(.focusQuestion)
        #expect(first != request)
        #expect(request?.action == .focusQuestion)
    }

    @Test func treeSwapPinAndFocusWorkWithClosedAndSwappedPanes() {
        var pane = MacInsightPaneLayout()
        pane.applyShortcut(.openTree, workspaceWidth: 1000)
        #expect(pane.fraction > 0)
        pane.applyShortcut(.swapPanes, workspaceWidth: 1000)
        #expect(pane.isSwapped)
        pane.close()
        pane.applyShortcut(.focusQuestion, workspaceWidth: 1000)
        #expect(pane.fraction > 0)
        #expect(pane.isSwapped)
        pane.applyShortcut(.pinPanes, workspaceWidth: 1000)
        #expect(pane.isPinned)
        pane.applyShortcut(.pinPanes, workspaceWidth: 1000)
        #expect(!pane.isPinned)
        pane.close()
        pane.applyShortcut(.swapPanes, workspaceWidth: 1000)
        #expect(!pane.isSwapped)
        #expect(pane.fraction > 0)
        pane.close()
        pane.applyShortcut(.focusQuestion, workspaceWidth: 1000)
        #expect(pane.fraction == 0)
        pane.applyShortcut(.pinPanes, workspaceWidth: 1000)
        #expect(pane.isPinned && pane.fraction > 0)
    }

    @Test func questionFocusRequestMountsNativeEditorWithoutSubmittingOrReplacingDraft() async throws {
        let session = MacConversationState()
        var draft = "Unsubmitted question"
        var submissions = 0
        let host = NSHostingView(rootView: MacConversationView(showsFixture: false, session: session,
            onSend: { submissions += 1 }, question: Binding(get: { draft }, set: { draft = $0 }), focusQuestionRequest: 1))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        let editor = try #require(window.firstResponder as? NSTextView)
        #expect(editor.string == draft)
        #expect(submissions == 0)
    }
}
