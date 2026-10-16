import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor @Suite(.serialized)
struct MacWorktreeSummaryRevealTests {
    @Test func generatedSummaryRevealsProgressivelyBeforeBecomingEditable() async throws {
        let text = Array(repeating: "Prudence", count: 120).joined(separator: " ")
        var visible = 0
        var completions = 0
        let host = NSHostingView(rootView: WorktreeSummaryReveal(text: text,
            onComplete: { completions += 1 }, onRevealedWordCountChange: { visible = $0 }))
        let window = mount(host)
        defer { window.contentView = nil; window.close() }
        let startDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while visible == 0 && ContinuousClock.now < startDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(visible > 0)
        #expect(visible < 120)
        #expect(completions == 0)
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while completions == 0 && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(visible == 120)
        #expect(completions == 1)
    }

    @Test func disabledAnimationFinishesWithoutWaitingForWordReveal() async throws {
        var completions = 0
        let host = NSHostingView(rootView: WorktreeSummaryReveal(
            text: Array(repeating: "Prudence", count: 120).joined(separator: " "),
            onComplete: { completions += 1 }, animatesReveal: false))
        let window = mount(host)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(completions == 1)
    }

    @Test func savedSummariesAndRedoDoNotReplayPresentation() throws {
        let board = WorktreeBoard()
        board.beginHistoryAction()
        var item = WorktreeBoard.Item(origin: .zero, text: "A completed summary")
        item.revealsSummary = true
        board.items.append(item)
        board.endHistoryAction()
        let saved = board.document(createdAt: Date())
        let restored = WorktreeBoard(document: try JSONDecoder().decode(WorktreeDocument.self, from: JSONEncoder().encode(saved)))
        #expect(restored.items.first?.text == item.text)
        #expect(restored.items.first?.revealsSummary == false)
        board.undo()
        board.redo()
        #expect(board.items.first?.text == item.text)
        #expect(board.items.first?.revealsSummary == false)
    }

    private func mount<Content: View>(_ host: NSHostingView<Content>) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 550, height: 720),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        return window
    }
}
