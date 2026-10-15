import AppKit
import SwiftUI
import Observation
import Testing
@testable import AngroveMac

@MainActor
struct MacWorkspaceShortcutTests {
    @Test func recentShortcutsMatchSidebarOrderExcludeTopicsAndStopAtNine() {
        let conversations = (0..<12).map { InquiryConversation(title: "Conversation \($0)", isPinned: $0 == 0) }
        let topic = InquiryConversation(title: "Topic", isStudyTopic: true)
        let displayedIDs = MacSidebarConversationActions.sorted(conversations + [topic]).prefix(9).map(\.id)
        #expect(MacWorkspaceCommandTarget.recentIDs(in: conversations + [topic]) == displayedIDs)
        #expect(displayedIDs.first == conversations[0].id)
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

    @Test func commandTOnlyDispatchesInsideConversationThreads() {
        for destination in MacDestination.allCases {
            var request: MacShortcutRequest?
            let target = MacWorkspaceCommandTarget(
                request: Binding(get: { request }, set: { request = $0 }),
                recentConversationIDs: [], destination: destination)
            target.send(.openTree)
            #expect(target.canToggleConversationTree == (destination == .conversations))
            #expect((request?.action == .openTree) == (destination == .conversations))
            // The global-tree shortcut remains available on every page.
            target.send(.openGlobalTree)
            #expect(request?.action == .openGlobalTree)
        }
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
        pane.swap()
        pane.close()
        pane.applyShortcut(.toggleContext, workspaceWidth: 1000)
        #expect(pane.fraction > 0 && pane.isSwapped)
    }

    @Test func treeShortcutTogglesAndPreservesLayoutInEveryOrientation() {
        for pinned in [false, true] {
            for swapped in [false, true] {
                var pane = MacInsightPaneLayout()
                pane.open(workspaceWidth: 1200)
                pane.drag(from: 500, translation: -100, workspaceWidth: 1200)
                if pinned { pane.togglePin(workspaceWidth: 1200) }
                if swapped { pane.swap() }
                let width = pane.viewportWidth(in: 1200)
                pane.applyShortcut(.openTree, workspaceWidth: 1200)
                #expect(pane.fraction == 0)
                pane.applyShortcut(.openTree, workspaceWidth: 1200)
                #expect(pane.viewportWidth(in: 1200) == width)
                #expect(pane.isPinned == pinned)
                #expect(pane.isSwapped == swapped)
            }
        }
    }

    @Test func globalTreeToggleReturnsToItsOriginalPageAndSupportsSidebarEntry() {
        let conversation = MacWorkspacePage(destination: .conversations, conversationID: UUID(), isFixture: true)
        var shortcut = MacGlobalTreeShortcut()
        for original in [conversation, MacWorkspacePage(destination: .home), MacWorkspacePage(destination: .studyTopics)] {
            let tree = shortcut.toggle(from: original, fallback: conversation)
            #expect(tree.destination == .insights)
            #expect(shortcut.toggle(from: tree, fallback: conversation) == original)
        }
        #expect(shortcut.toggle(from: MacWorkspacePage(destination: .insights), fallback: conversation) == conversation)
    }

    @Test func settingsShortcutTargetsWorkspaceAndParticipatesInPageHistory() {
        var request: MacShortcutRequest?
        let target = MacWorkspaceCommandTarget(request: Binding(get: { request }, set: { request = $0 }), recentConversationIDs: [])
        target.send(.openSettings)
        #expect(request?.action == .openSettings)
        let conversation = MacWorkspacePage(destination: .conversations, conversationID: UUID())
        let settings = MacWorkspacePage(destination: .settings)
        var history = MacPageHistory()
        history.visit(conversation)
        history.visit(settings)
        #expect(history.current == settings)
        #expect(history.back() == conversation)
        #expect(history.forward() == settings)
        history.visit(settings)
        #expect(history.pages == [conversation, settings])
        #expect(!MacDestination.sidebarDestinations.contains(.settings))
    }

    @Test func contextRequestsToggleOnceCloseOtherPopupsAndRespectCompaction() async throws {
        let request = ContextCommandProbe()
        let context = ContextCardState()
        let popup = ModelTasksPopupState()
        popup.isOpen = true
        let dock = InquiryControlDock(isCanvasMode: false,
            showFilePicker: .constant(false), showPhotoPicker: .constant(false), showCamera: .constant(false),
            selectedPersonality: .constant("default"), isPersonalityMenuOpen: .constant(false), isAtBottom: true,
            onScrollToBottom: {}, onViewEntireCanvas: {}, onOpenInsights: {},
            modelTasks: ModelTaskQueue(), modelTasksPopupState: popup,
            contextCard: context, contextToggleRequest: Binding(get: { request.id }, set: { request.id = $0 }))
        let host = NSHostingView(rootView: dock)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 350, height: 180),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        try await waitForContext { request.id == nil && context.isOpen }
        #expect(!popup.isOpen)
        request.id = UUID()
        try await waitForContext { request.id == nil && !context.isOpen }
        context.isCompacting = true
        request.id = UUID()
        try await waitForContext { request.id == nil }
        #expect(!context.isOpen)
        context.isCompacting = false
        request.id = UUID()
        try await waitForContext { request.id == nil && context.isOpen }
    }

    private func waitForContext(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
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

@MainActor @Observable
private final class ContextCommandProbe {
    var id: UUID? = UUID()
}
