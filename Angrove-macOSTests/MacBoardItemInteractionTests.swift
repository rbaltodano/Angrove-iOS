import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor @Suite(.serialized)
struct MacBoardItemInteractionTests {
    @Test func draggingTheInsightBodyMovesItInsteadOfStartingBoxSelection() async throws {
        let board = WorktreeBoard()
        var item = WorktreeBoard.Item(origin: CGPoint(x: -200, y: -100))
        item.insight = definition()
        board.items = [item]
        let runtime = MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue())
        let host = NSHostingView(rootView: MacWorktreeView(board: board, queuePopup: ModelTasksPopupState(), runtime: runtime))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(400))
        host.layoutSubtreeIfNeeded()
        let frame = try #require(board.frame(of: item.id))
        // Inside the definition text, away from its top strip, side grip and action buttons.
        let start = CGPoint(x: 450 + frame.midX, y: 700 - (350 + frame.maxY - 24))
        let end = CGPoint(x: start.x + 60, y: start.y - 40)
        for (type, point) in [(NSEvent.EventType.leftMouseDown, start), (.leftMouseDragged, end), (.leftMouseUp, end)] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: point,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            NSApp.postEvent(event, atStart: false)
        }
        try await Task.sleep(for: .milliseconds(400))
        let moved = try #require(board.items.first)
        #expect(abs(moved.origin.x - item.origin.x - 60) < 1)
        #expect(abs(moved.origin.y - item.origin.y - 40) < 1)
        #expect(moved.insight == item.insight)
        board.undo()
        #expect(board.items.first?.origin == item.origin)
    }

    @Test func selectedItemsRenderWithBordersInBothAppearances() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let board = WorktreeBoard()
            var insight = WorktreeBoard.Item(origin: CGPoint(x: -340, y: -180))
            insight.insight = definition()
            var heading = WorktreeBoard.Item(origin: CGPoint(x: 120, y: -180), text: "A heading")
            heading.isHeading = true
            let note = WorktreeBoard.Item(origin: CGPoint(x: 120, y: -60), text: "A selected note")
            board.items = [insight, heading, note]
            board.selection = board.items.map(\.id)
            let runtime = MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue())
            let host = NSHostingView(rootView: MacWorktreeView(board: board, queuePopup: ModelTasksPopupState(), runtime: runtime)
                .environment(\.colorScheme, scheme))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.contentView = nil; window.close() }
            try await Task.sleep(for: .milliseconds(650))
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(filePath: NSTemporaryDirectory() + "angrove-selection-borders-\(scheme == .light ? "light" : "dark").png"))
        }
    }

    private func definition() -> ConceptDefinition {
        ConceptDefinition(word: "Prudence", partOfSpeech: "noun", pronunciation: "",
            meaning: "Practical wisdom that guides sound judgment.", example: "")
    }
}
