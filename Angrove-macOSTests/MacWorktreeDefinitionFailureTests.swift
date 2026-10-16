import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor @Suite(.serialized)
struct MacWorktreeDefinitionFailureTests {
    @Test func modelFailureStaysInlineAndNeverEntersPersistenceOrTrash() async throws {
        let runtime = MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue())
        let board = WorktreeBoard()
        #expect(board.openCommand(freeOrigin: .zero))
        board.commandText = "/define church"
        board.submitCommand(runtime: runtime)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while board.items.first?.definitionFailureTerm == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let item = try #require(board.items.first)
        #expect(item.definitionFailureTerm == "church")
        #expect(item.outputWork == nil)
        #expect(board.errorMessage == nil)
        #expect(board.document(createdAt: Date()).items.isEmpty)
        let rippleCount = board.ripples.count
        board.dismissDefinitionFailure(item.id)
        #expect(board.ripples.count == rippleCount + 1)
        #expect(board.items.isEmpty)
        #expect(board.recentlyDeleted.isEmpty)
        board.undo()
        #expect(board.items.isEmpty)
    }

    @Test func dismissedCommandPulsesAtTheFieldInsteadOfItsTarget() {
        let board = WorktreeBoard()
        #expect(board.openCommand(freeOrigin: CGPoint(x: 20, y: 30)))
        board.commandFieldSize = CGSize(width: 120, height: 28)
        board.closeCommand()
        #expect(board.ripples.last?.worldOrigin == CGPoint(x: 80, y: -44))
    }

    @Test func removedItemsPulseAtTheirFormerCentre() {
        let board = WorktreeBoard()
        let item = WorktreeBoard.Item(origin: CGPoint(x: 100, y: 200), text: "A note")
        board.items = [item]
        board.itemSizes[item.id] = CGSize(width: 116, height: 56)
        board.delete(item.id)
        #expect(board.ripples.last?.worldOrigin == CGPoint(x: 150, y: -220))
    }

    @Test func failureRevealsThenWaitsOneAndAHalfSecondsBeforeDismissal() async throws {
        var dismissals = 0
        let host = NSHostingView(rootView: WorktreeDefinitionFailure(term: "church", onDismiss: { dismissals += 1 }))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 150), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .seconds(1))
        #expect(dismissals == 0)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while dismissals == 0 && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(dismissals == 1)
    }
}
