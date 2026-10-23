import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor @Suite(.serialized)
struct MacBoardsCameraMotionTests {
    @Test func continuousPanAndZoomWithConversationWindows() async throws {
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
        let surface = try #require(find(MacCanvasScrollInput.ScrollSurface.self, in: host))
        let scene = try #require(find(WorktreeSceneView.self, in: host))
        for _ in 0..<200 where scene.cacheStatistics.cached < scene.cacheStatistics.visible || scene.cacheStatistics.live != 0 {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(scene.cacheStatistics.nodes == 12)
        #expect(scene.cacheStatistics.visible > 0)
        #expect(scene.cacheStatistics.cached >= scene.cacheStatistics.visible, "Only visible items need snapshots; offscreen items may be culled before capture")
        #expect(scene.cacheStatistics.live == 0)
        print("HYBRID_CACHE_BEFORE \(scene.cacheStatistics)")
        let before = board.viewport
        print("BOARDS_MOTION_PROFILE_BEGIN pid=\(ProcessInfo.processInfo.processIdentifier)")
        var costs: [Double] = []
        for frame in 0..<180 {
            let start = CACurrentMediaTime()
            let zoom = (frame / 30) % 2 == 1
            let direction: CGFloat = frame < 90 ? 1 : -1
            surface.onScroll?(CGSize(width: zoom ? 0 : direction * 4, height: zoom ? direction * 0.8 : 2),
                              zoom ? .command : [], CGPoint(x: 700, y: 450))
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            costs.append((CACurrentMediaTime() - start) * 1000)
            try await Task.sleep(for: .milliseconds(16))
        }
        print("HYBRID_CACHE_AFTER \(scene.cacheStatistics)")
        let sorted = costs.sorted()
        print("BOARDS_MOTION_PROFILE_END mean_ms=\(costs.reduce(0, +) / Double(costs.count)) p95_ms=\(sorted[Int(Double(sorted.count) * 0.95)])")
        #expect(board.viewport != before)
        #expect(board.items.count == 12)
        #expect(board.items.allSatisfy { $0.session?.transcript.count == 2 })
    }

    private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for child in view.subviews {
            if let match = find(type, in: child) { return match }
        }
        return nil
    }
}
