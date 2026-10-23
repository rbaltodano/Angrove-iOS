import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor @Suite(.serialized)
struct MacBoardsItemMotionTests {
    @Test func movingAConversationReusesItsSnapshot() async throws {
        let board = WorktreeBoard()
        let runtime = MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue())
        for index in 0..<12 {
            let session = MacConversationState()
            session.savesConversation = false
            session.configure(preview: true)
            var branch = ChatBranch(startingConcept: nil)
            branch.topQuestionText = "What guides practical judgment?"
            branch.topQuestionSubmitted = true
            branch.activeChatBlocks = [.text(String(repeating: "Practical wisdom connects understanding with everyday decisions. ", count: 30))]
            session.branches = [branch]
            session.selectedBranch = branch.id
            var item = WorktreeBoard.Item(origin: CGPoint(x: (index % 3) * 440 - 630, y: (index / 3) * 460 - 340))
            item.session = session
            item.size = CGSize(width: 400, height: 420)
            board.items.append(item)
        }
        let host = NSHostingView(rootView: MacWorktreeView(board: board, queuePopup: ModelTasksPopupState(), runtime: runtime))
        let window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 1440, height: 900),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .seconds(3))
        let scene = try #require(find(WorktreeSceneView.self, in: host))
        for _ in 0..<200 where scene.cacheStatistics.cached < scene.cacheStatistics.visible || scene.cacheStatistics.live != 0 {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(scene.cacheStatistics.nodes == 12)
        #expect(scene.cacheStatistics.visible > 0)
        #expect(scene.cacheStatistics.cached >= scene.cacheStatistics.visible, "Only visible items need snapshots; offscreen items may be culled before capture")
        #expect(scene.cacheStatistics.live == 0)
        print("HYBRID_CACHE_BEFORE \(scene.cacheStatistics)")
        let moving = board.items[0]
        let builds = scene.cacheStatistics.builds
        let snapshot = try #require(scene.cachedImage(for: moving.id))
        let frame = try #require(board.frame(of: moving.id))
        let startPoint = CGPoint(x: 720 + frame.minX + 80, y: 900 - (450 + frame.minY + 14))
        window.makeKeyAndOrderFront(nil)
        func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        NSApp.postEvent(try event(.leftMouseDown, startPoint), atStart: false)
        try await Task.sleep(for: .milliseconds(50))
        var costs: [Double] = []
        let motionStart = CACurrentMediaTime()
        for frame in 1...120 {
            let start = CACurrentMediaTime()
            NSApp.postEvent(try event(.leftMouseDragged, CGPoint(x: startPoint.x + CGFloat(frame) * 2, y: startPoint.y - CGFloat(frame) * 0.5)), atStart: false)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            costs.append((CACurrentMediaTime() - start) * 1000)
            try await Task.sleep(for: .milliseconds(16))
        }
        print("BOARDS_ITEM_MOTION_CACHE_BUILDS \(scene.cacheStatistics.builds - builds)")
        print("BOARDS_ITEM_MOTION_DURATION_SECONDS \(CACurrentMediaTime() - motionStart)")
        #expect(scene.cachedImage(for: moving.id) === snapshot, "Dragging must move the existing surface without rebuilding its bitmap")
        #expect(scene.cacheStatistics.live == 0, "Dragging a resting conversation keeps its transcript detached")
        NSApp.postEvent(try event(.leftMouseUp, CGPoint(x: startPoint.x + 240, y: startPoint.y - 60)), atStart: false)
        try await Task.sleep(for: .milliseconds(300))
        let sorted = costs.sorted()
        print("BOARDS_ITEM_MOTION_PROFILE_END mean_ms=\(costs.reduce(0, +) / Double(costs.count)) p95_ms=\(sorted[Int(Double(sorted.count) * 0.95)])")
        #expect(board.items[0].origin != moving.origin)
        #expect(board.items.count == 12)
        #expect(board.items.allSatisfy { $0.session?.transcript.count == 2 })
        board.undo()
        try await Task.sleep(for: .milliseconds(500))
        window.makeKeyAndOrderFront(nil)
        let scroll = try #require(find(MacCanvasScrollInput.ScrollSurface.self, in: host))
        for scale: CGFloat in [1, 2] {
            if scale == 2 {
                scroll.onScroll?(CGSize(width: 0, height: log(2) / 0.012), .command, CGPoint(x: 160, y: 90))
                try await Task.sleep(for: .milliseconds(650))
            }
            let frame = try #require(board.frame(of: moving.id))
            let transform = board.viewport.transform
            let start = CGPoint(x: 720 + transform.offset.width + (frame.minX + 80) * scale,
                                y: 900 - (450 + transform.offset.height + (frame.minY + 14) * scale))
            for step in 0...7 {
                let type: NSEvent.EventType = step == 0 ? .leftMouseDown : step == 7 ? .leftMouseUp : .leftMouseDragged
                let progress = CGFloat(min(step, 6)) / 6
                let point = CGPoint(x: start.x + 120 * progress, y: start.y - 70 * progress)
                let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: step, clickCount: 1, pressure: 1))
                NSApp.postEvent(event, atStart: false)
                try await Task.sleep(for: .milliseconds(25))
            }
            try await Task.sleep(for: .milliseconds(300))
            #expect(abs(board.items[0].origin.x - moving.origin.x - 120 / scale) < 1)
            #expect(abs(board.items[0].origin.y - moving.origin.y - 70 / scale) < 1)
            board.undo()
            try await Task.sleep(for: .milliseconds(300))
            #expect(board.items[0].origin == moving.origin)
        }
        // Bring the left grip fully into the viewport after the anchored 200% zoom.
        scroll.onScroll?(CGSize(width: 240, height: 0), [], CGPoint(x: 720, y: 450))
        try await Task.sleep(for: .milliseconds(500))
        let frameAfterUndo = try #require(board.frame(of: moving.id))
        let transform = board.viewport.transform
        let gripStart = CGPoint(x: 720 + transform.offset.width + (frameAfterUndo.minX - 16 / transform.scale) * transform.scale,
                                y: 900 - (450 + transform.offset.height + (frameAfterUndo.minY + 36) * transform.scale))
        // The standalone board fixture has no workspace controls parent to publish this rect.
        board.trashFrame = CGRect(x: 1200, y: 750, width: 100, height: 80)
        let trash = board.trashFrame
        let trashPoint = CGPoint(x: trash.midX, y: 900 - trash.midY)
        for (type, point) in [(NSEvent.EventType.leftMouseDown, gripStart), (.leftMouseDragged, trashPoint), (.leftMouseUp, trashPoint)] {
            NSApp.postEvent(try event(type, point), atStart: false)
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(300))
        #expect(!board.items.contains { $0.id == moving.id }, "Native grip dragging preserves the Trash drop")
        board.undo()
        #expect(board.items.contains { $0.id == moving.id })
    }

    private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for child in view.subviews {
            if let match = find(type, in: child) { return match }
        }
        return nil
    }
}
