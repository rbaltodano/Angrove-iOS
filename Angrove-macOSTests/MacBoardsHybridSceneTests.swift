import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor @Suite(.serialized)
struct MacBoardsHybridSceneTests {
    @Test func cachesRefreshAfterEditsAndOffscreenItemsAreCulled() async throws {
        let board = WorktreeBoard()
        let note = WorktreeBoard.Item(origin: CGPoint(x: -280, y: -120), text: "A cached note")
        let distant = WorktreeBoard.Item(origin: CGPoint(x: 10_000, y: 10_000), text: "Offscreen")
        board.items = [note, distant]
        let runtime = MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue())
        let popup = ModelTasksPopupState()
        let host = NSHostingView(rootView: MacWorktreeView(board: board, queuePopup: popup, runtime: runtime).environment(\.colorScheme, .light))
        let window = makeWindow(host)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .seconds(2))
        let scene = try #require(find(WorktreeSceneView.self, in: host))
        for _ in 0..<100 where scene.cacheStatistics.visible != 1 || scene.cachedImage(for: note.id) == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        let original = try #require(scene.cachedImage(for: note.id))
        #expect(scene.cacheStatistics.visible == 1)
        #expect(scene.cacheStatistics.live == 0)
        #expect(scene.cacheStatistics.bytes <= 128 * 1024 * 1024)
        let scroll = try #require(find(MacCanvasScrollInput.ScrollSurface.self, in: host))
        let builds = scene.cacheStatistics.builds
        for _ in 0..<20 {
            scroll.onScroll?(CGSize(width: 2, height: 0.2), .command, CGPoint(x: 450, y: 350))
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(8))
        }
        #expect(scene.cacheStatistics.builds == builds, "Camera movement reuses existing snapshots")
        try await Task.sleep(for: .milliseconds(500))
        board.update(note.id) { $0.text = "The cached note has been updated" }
        try await Task.sleep(for: .milliseconds(500))
        let updated = try #require(scene.cachedImage(for: note.id))
        #expect(updated !== original)
        let expectedWidth = ("The cached note has been updated" as NSString).size(withAttributes: [.font: WorktreeTextEditor.font]).width
        #expect((board.itemSizes[note.id]?.width ?? 0) >= expectedWidth)
        #expect(scene.cacheStatistics.builds > builds)
        for scheme in [ColorScheme.light, .dark] {
            host.rootView = MacWorktreeView(board: board, queuePopup: popup, runtime: runtime).environment(\.colorScheme, scheme)
            try await Task.sleep(for: .milliseconds(500))
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(filePath: "/tmp/angrove-hybrid-\(scheme == .light ? "light" : "dark").png"))
        }
    }

    @Test func cachedInsightTakesTheInitiatingDrag() async throws {
        let board = WorktreeBoard()
        var item = WorktreeBoard.Item(origin: CGPoint(x: -200, y: -100))
        item.insight = ConceptDefinition(word: "Prudence", partOfSpeech: "noun", pronunciation: "", meaning: "Practical wisdom that guides sound judgment.", example: "")
        board.items = [item]
        let runtime = MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue())
        let host = NSHostingView(rootView: MacWorktreeView(board: board, queuePopup: ModelTasksPopupState(), runtime: runtime))
        let window = makeWindow(host)
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .seconds(2))
        let scene = try #require(find(WorktreeSceneView.self, in: host))
        #expect(scene.cachedImage(for: item.id) != nil)
        let scroll = try #require(find(MacCanvasScrollInput.ScrollSurface.self, in: host))
        for scale: CGFloat in [1, 2] {
            if scale == 2 {
                scroll.onScroll?(CGSize(width: 0, height: log(2) / 0.012), .command, CGPoint(x: 450, y: 350))
                try await Task.sleep(for: .milliseconds(650))
            }
            let frame = try #require(board.frame(of: item.id))
            let start = CGPoint(x: 450 + frame.midX * scale, y: 700 - (350 + (frame.maxY - 24) * scale))
            let end = CGPoint(x: start.x + 60, y: start.y - 40)
            for (type, point) in [(NSEvent.EventType.leftMouseDown, start), (.leftMouseDragged, end), (.leftMouseUp, end)] {
                let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                NSApp.postEvent(event, atStart: false)
            }
            try await Task.sleep(for: .milliseconds(300))
            #expect(abs((board.items.first?.origin.x ?? 0) - item.origin.x - 60 / scale) < 1, "scale \(scale), origin \(String(describing: board.items.first?.origin))")
            #expect(abs((board.items.first?.origin.y ?? 0) - item.origin.y - 40 / scale) < 1, "scale \(scale), origin \(String(describing: board.items.first?.origin))")
            board.undo()
            #expect(board.items.first?.origin == item.origin)
        }
    }

    @Test func generationStaysLiveAndCachedWordsTakeTheFirstMenuRequest() async throws {
        let board = WorktreeBoard()
        let session = MacConversationState()
        session.savesConversation = false
        session.configure(preview: true)
        var branch = ChatBranch(startingConcept: nil)
        branch.topQuestionText = "What is wisdom?"
        branch.topQuestionSubmitted = true
        branch.activeChatBlocks = [.text("Wisdom guides sound judgment in everyday life.")]
        session.branches = [branch]
        session.selectedBranch = branch.id
        var item = WorktreeBoard.Item(origin: CGPoint(x: -200, y: -140))
        item.session = session
        item.size = CGSize(width: 400, height: 350)
        board.items = [item]
        let runtime = MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue())
        let host = NSHostingView(rootView: MacWorktreeView(board: board, queuePopup: ModelTasksPopupState(), runtime: runtime))
        let window = makeWindow(host)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .seconds(2))
        let scene = try #require(find(WorktreeSceneView.self, in: host))
        #expect(scene.cacheStatistics.live == 0)
        let pendingKey = "\(branch.id):0"
        session.pendingResponses.insert(pendingKey)
        try await Task.sleep(for: .milliseconds(150))
        #expect(scene.cacheStatistics.live == 1)
        session.pendingResponses.remove(pendingKey)
        try await Task.sleep(for: .milliseconds(500))
        #expect(scene.cacheStatistics.live == 0)
        var found = false
        for y in stride(from: 240, through: 380, by: 14) {
            for x in stride(from: 260, through: 550, by: 20) {
                let point = CGPoint(x: x, y: 700 - y)
                if MacContextMenuRegistry.entries(at: point, in: window).contains(where: { $0.title == "Copy" }) {
                    found = true
                    break
                }
            }
            if found { break }
        }
        #expect(found, "The initiating menu request activates cached word hit regions")
        #expect(scene.cacheStatistics.live == 1)
    }

    @Test func transientNotesFinishTheirTaskAndDeletedLiveHostsAreRemoved() async throws {
        let board = WorktreeBoard()
        let quote = WorktreeBoard.Item(origin: CGPoint(x: -200, y: -100), text: "\"")
        let note = WorktreeBoard.Item(origin: CGPoint(x: 100, y: -100), text: "Editing")
        board.items = [quote, note]
        board.editingID = note.id
        let runtime = MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue())
        let host = NSHostingView(rootView: MacWorktreeView(board: board, queuePopup: ModelTasksPopupState(), runtime: runtime))
        let window = makeWindow(host)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(1300))
        let scene = try #require(find(WorktreeSceneView.self, in: host))
        #expect(scene.cacheStatistics.live == 2)
        board.delete(note.id)
        try await Task.sleep(for: .milliseconds(200))
        #expect(scene.cacheStatistics.nodes == 1)
        #expect(scene.subviews.count == 3, "Only the cached world, native drag receiver, and transient note's live host remain")
        try await Task.sleep(for: .seconds(2))
        #expect(board.items.isEmpty, "Unmounting inactive surfaces must not cancel the quote's expiry task")
        #expect(scene.subviews.count == 2)
    }

    private func makeWindow(_ host: NSView) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        return window
    }
    private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { find(type, in: $0) }.first
    }
}
