import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor @Suite(.serialized)
struct MacBoardsGripInteractionTests {
    @Test func selectionMovesTogetherAndUndoRestoresEveryItem() {
        let board = WorktreeBoard()
        let first = WorktreeBoard.Item(origin: .zero, text: "First")
        let second = WorktreeBoard.Item(origin: CGPoint(x: 180, y: 130), text: "Second")
        let other = WorktreeBoard.Item(origin: CGPoint(x: 400, y: 300), text: "Other")
        board.items = [first, second, other]
        for item in board.items { board.itemSizes[item.id] = CGSize(width: 100, height: 60) }
        board.selection = [first.id, second.id]
        board.beginHistoryAction()
        board.move(first.id, to: CGPoint(x: 3, y: 4), threshold: 8, overhang: 84)
        #expect(board.items[0].origin == CGPoint(x: 3, y: 4))
        board.move(first.id, to: CGPoint(x: 42, y: 33), threshold: 8, overhang: 84)
        board.move(first.id, to: CGPoint(x: 79, y: 91), threshold: 8, overhang: 84)
        board.endMove()
        board.endHistoryAction()
        #expect(board.items[0].origin == CGPoint(x: 79, y: 91))
        #expect(board.items[1].origin == CGPoint(x: 259, y: 221))
        #expect(board.items[2] == other)
        #expect(board.selection == [first.id, second.id])
        board.undo()
        #expect(board.items == [first, second, other])
        board.redo()
        #expect(board.items[1].origin == CGPoint(x: 259, y: 221))
        // Dragging an unselected item does not move the highlighted group.
        let selected = Array(board.items.prefix(2))
        board.move(other.id, to: CGPoint(x: 450, y: 380), threshold: 0, overhang: 84)
        #expect(Array(board.items.prefix(2)) == selected)
    }

    @Test(arguments: [false, true]) func gripsStartDragAndMoveTheSelectionAtBothZooms(sideGrip: Bool) async throws {
        for scale in [CGFloat(1), 2] {
            let board = WorktreeBoard()
            var heading = WorktreeBoard.Item(origin: CGPoint(x: -150, y: -50), text: "Heading")
            heading.isHeading = true
            heading.size = CGSize(width: 240, height: 80)
            let note = WorktreeBoard.Item(origin: CGPoint(x: 150, y: 100), text: "A selected note")
            board.items = [heading, note]
            board.selection = [heading.id, note.id]
            let runtime = MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue())
            let host = NSHostingView(rootView: MacWorktreeView(board: board, queuePopup: ModelTasksPopupState(), runtime: runtime))
            let window = makeWindow(host)
            defer { window.contentView = nil; window.close() }
            try await Task.sleep(for: .seconds(2))
            let scene = try #require(find(WorktreeSceneView.self, in: host))
            scene.move(CanvasScrollTransform(scale: scale, offset: .zero), viewport: host.bounds.size)
            try await Task.sleep(for: .milliseconds(400))
            let frame = try #require(board.frame(of: heading.id))
            let point = sideGrip ? CGPoint(x: frame.minX - 11.75 / scale, y: frame.minY + 6 / scale)
                : CGPoint(x: frame.midX, y: frame.minY - 11.75 / scale)
            // Hover alone must attach the cached host; no click is needed to get its cursors.
            scene.hover(world: point)
            #expect(scene.cacheStatistics.live >= 1)
            #expect(NSCursor.current == .openHand)
            scene.hover(world: nil)
            #expect(NSCursor.current == .arrow)
            scene.hover(world: point)
            let local = CGPoint(x: scene.bounds.midX + point.x * scale, y: scene.bounds.midY + point.y * scale)
            let start = scene.convert(local, to: nil)
            for (type, delta) in [(NSEvent.EventType.leftMouseDown, CGFloat(0)), (.leftMouseDragged, 60), (.leftMouseUp, 60)] {
                let event = try #require(NSEvent.mouseEvent(with: type,
                    location: CGPoint(x: start.x + delta, y: start.y - delta), modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                NSApp.postEvent(event, atStart: false)
                try await Task.sleep(for: .milliseconds(30))
            }
            try await Task.sleep(for: .milliseconds(300))
            #expect(abs(board.items[0].origin.x - heading.origin.x - 60 / scale) < 1)
            #expect(abs(board.items[0].origin.y - heading.origin.y - 60 / scale) < 1)
            #expect(abs(board.items[1].origin.x - note.origin.x - 60 / scale) < 1)
            #expect(abs(board.items[1].origin.y - note.origin.y - 60 / scale) < 1)
            #expect(board.selection.count == 2)
            board.undo()
            #expect(board.items.map(\.origin) == [heading.origin, note.origin])
        }
    }

    @Test func headingSideGripRendersAtTopCornerInBothAppearances() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let board = WorktreeBoard()
            var item = WorktreeBoard.Item(origin: .zero, text: "h")
            item.isHeading = true
            item.size = CGSize(width: 180, height: 80)
            board.items = [item]
            board.selection = [item.id]
            let runtime = MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue())
            let pointer = WorktreeCanvasPointer()
            let host = NSHostingView(rootView: WorktreeItemView(board: board, item: item, scale: 1,
                runtime: runtime, pointer: pointer).fixedSize().padding(60).environment(\.colorScheme, scheme))
            let window = makeWindow(host)
            defer { window.contentView = nil; window.close() }
            try await Task.sleep(for: .seconds(1))
            host.layoutSubtreeIfNeeded()
            pointer.update(world: CGPoint(x: -12, y: -8), board: board, zoom: 1)
            board.editingID = item.id // Keep the side grip visible for the rendering check.
            try await Task.sleep(for: .milliseconds(300))
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(filePath: "/tmp/angrove-heading-grip-\(scheme == .light ? "light" : "dark").png"))
        }
    }

    private func makeWindow(_ view: NSView) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 700),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        return window
    }
    private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let found = view as? T { return found }
        return view.subviews.lazy.compactMap { find(type, in: $0) }.first
    }
}
