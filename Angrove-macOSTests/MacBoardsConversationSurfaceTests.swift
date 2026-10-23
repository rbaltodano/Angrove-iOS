import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor @Suite(.serialized)
struct MacBoardsConversationSurfaceTests {
    @Test func automaticHeightAndNativeFollowUpEditingRemainLive() async throws {
        let board = WorktreeBoard()
        let runtime = MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue())
        let session = MacConversationState()
        session.savesConversation = false
        session.configure(preview: true)
        var branch = ChatBranch(startingConcept: nil)
        branch.topQuestionText = "What is practical wisdom?"
        branch.topQuestionSubmitted = true
        branch.activeChatBlocks = [.text("Wisdom guides sound judgment.")]
        session.branches = [branch]
        session.selectedBranch = branch.id
        var item = WorktreeBoard.Item(origin: CGPoint(x: -200, y: -100))
        item.session = session
        board.items = [item]
        let host = NSHostingView(rootView: MacWorktreeView(board: board, queuePopup: ModelTasksPopupState(), runtime: runtime))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(800))
        host.layoutSubtreeIfNeeded()
        let original = try #require(board.itemSizes[item.id])
        board.editingID = item.followUpID
        for _ in 0..<20 {
            if window.firstResponder is NSTextView { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let editor = try #require(window.firstResponder as? NSTextView)
        editor.insertText("A follow-up remains editable", replacementRange: editor.selectedRange())
        #expect(board.items.first?.followUp == "A follow-up remains editable")
        board.endEditing()
        session.branches[0].activeChatBlocks[0] = .text(String(repeating: "Practical wisdom guides everyday judgment. ", count: 100))
        try await Task.sleep(for: .milliseconds(650))
        host.layoutSubtreeIfNeeded()
        let expanded = try #require(board.itemSizes[item.id])
        #expect(expanded.height > original.height)
        #expect(expanded.height <= WorktreeItemView.cardMaxHeight + 1)
        #expect(board.items.first?.session === session)
    }
}
