import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor @Suite(.serialized)
struct MacBoardsHoverAndInsightTests {
    @Test func snapshotsExcludeGripsAndHoverChrome() async throws {
        let board = WorktreeBoard()
        var item = WorktreeBoard.Item(origin: .zero, text: "Heading")
        item.isHeading = true
        item.size = CGSize(width: 240, height: 80)
        board.items = [item]
        board.editingID = item.id
        let pointer = WorktreeCanvasPointer()
        let runtime = MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue())
        func view(_ snapshot: Bool) -> some View {
            WorktreeItemView(board: board, item: item, scale: 1, runtime: runtime, pointer: pointer)
                .fixedSize().padding(60).environment(\.colorScheme, .dark)
                .environment(\.worktreeCapturesSnapshot, snapshot)
        }
        let host = NSHostingView(rootView: view(false))
        let window = makeWindow(host)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(200))
        pointer.update(world: .zero, board: board, zoom: 1)
        try await Task.sleep(for: .milliseconds(250))
        let hovered = try accentPixels(host)
        #expect(hovered > 5)
        host.rootView = view(true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(try accentPixels(host) < hovered / 3, "Hover grips and outlines must not be baked into the cache")
        host.rootView = view(false)
        board.editingID = nil
        pointer.update(world: nil, board: board, zoom: 1)
        try await Task.sleep(for: .milliseconds(250))
        #expect(try accentPixels(host) < hovered / 3)
    }

    @Test func nativeHoverChangesToResizeCursorsAndResetsOnExit() async throws {
        let (board, item, _, runtime) = fixture()
        let host = NSHostingView(rootView: MacWorktreeView(board: board, queuePopup: ModelTasksPopupState(), runtime: runtime))
        let window = makeWindow(host)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .seconds(2))
        let scene = try #require(find(WorktreeSceneView.self, in: host))
        let frame = try #require(board.frame(of: item.id))
        for point in [CGPoint(x: frame.maxX + 2, y: frame.midY), CGPoint(x: frame.maxX + 2, y: frame.maxY + 2)] {
            scene.hover(world: point)
            #expect(NSCursor.current != .arrow)
        }
        scene.hover(world: nil)
        #expect(NSCursor.current == .arrow)
    }

    @Test(arguments: [CGFloat(0.5), 1, 2]) func firstClickOnCachedInsightReachesDefineAction(scale: CGFloat) async throws {
        let (board, _, session, runtime) = fixture()
        let host = NSHostingView(rootView: MacWorktreeView(board: board, queuePopup: ModelTasksPopupState(), runtime: runtime))
        let window = makeWindow(host)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .seconds(2))
        let scene = try #require(find(WorktreeSceneView.self, in: host))
        let scroll = try #require(find(MacCanvasScrollInput.ScrollSurface.self, in: host))
        scroll.onScroll?(CGSize(width: 0, height: log(scale) / 0.012), .command, CGPoint(x: 450, y: 350))
        try await Task.sleep(for: .milliseconds(450))
        #expect(scene.cacheStatistics.live == 0)
        host.layoutSubtreeIfNeeded()
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(filePath: "/tmp/angrove-insight-scale-\(scale).png"))
        }
        // Centre of the fixture's first answer word, verified in its native rendering.
        // Send the initiating click while the conversation is still cached.
        let point = CGPoint(x: 450 - 165 * scale, y: 700 - (350 - 90 * scale))
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            NSApp.postEvent(event, atStart: false)
            try await Task.sleep(for: .milliseconds(30))
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(session.showsError, "The unavailable test model reports an error only if the actual Define action was reached")
    }

    @Test(arguments: [CGFloat(1), 2]) func resizeEdgeWorksAtTheCursorLocation(scale: CGFloat) async throws {
        let (board, item, _, runtime) = fixture()
        let host = NSHostingView(rootView: MacWorktreeView(board: board, queuePopup: ModelTasksPopupState(), runtime: runtime))
        let window = makeWindow(host)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .seconds(2))
        let scroll = try #require(find(MacCanvasScrollInput.ScrollSurface.self, in: host))
        scroll.onScroll?(CGSize(width: 0, height: log(scale) / 0.012), .command, CGPoint(x: 450, y: 350))
        try await Task.sleep(for: .milliseconds(400))
        let frame = try #require(board.frame(of: item.id))
        let start = CGPoint(x: 450 + (frame.maxX - 2) * scale, y: 700 - (350 + frame.midY * scale))
        for (type, delta) in [(NSEvent.EventType.leftMouseDown, CGFloat(0)), (.leftMouseDragged, 60), (.leftMouseUp, 60)] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: CGPoint(x: start.x + delta, y: start.y),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            NSApp.postEvent(event, atStart: false)
            try await Task.sleep(for: .milliseconds(30))
        }
        try await Task.sleep(for: .milliseconds(200))
        #expect(abs((board.items[0].size?.width ?? 0) - 400 - 60 / scale) < 1)
    }

    @Test func nativePointerClearsIlluminationOnExitDeactivationAndCameraMovement() async throws {
        let board = WorktreeBoard()
        var item = WorktreeBoard.Item(origin: .zero, text: "Hover outline")
        item.size = CGSize(width: 200, height: 80)
        board.items = [item]
        let pointer = WorktreeCanvasPointer()
        let runtime = MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue())
        let scene = WorktreeSceneView(board: board, runtime: runtime, pointer: pointer)
        let window = makeWindow(scene)
        defer { scene.stop(); window.contentView = nil; window.close() }
        scene.move(CanvasScrollTransform(scale: 1, offset: .zero), viewport: CGSize(width: 900, height: 700))
        var environment = EnvironmentValues()
        environment.colorScheme = .dark
        scene.update([WorktreeSceneEntry(item: item, branches: nil, savedIDs: [], isSavedInsight: false,
            needsLiveContent: false, isEditing: false, isSelected: false)], environment: environment, typography: "hover-test")
        try await Task.sleep(for: .seconds(2))
        func move(to local: CGPoint) throws {
            let event = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: scene.convert(local, to: nil),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
            scene.mouseMoved(with: event)
        }
        try move(to: CGPoint(x: 442, y: 380))
        #expect(pointer.nearIDs.contains(item.id))
        try await Task.sleep(for: .milliseconds(200))
        let lit = try accentPixels(scene)
        #expect(lit > 5)
        // Force the real cache path while the outline is lit, then inspect after departure.
        scene.move(CanvasScrollTransform(scale: 1, offset: CGSize(width: 1, height: 0)), viewport: CGSize(width: 900, height: 700))
        let leave = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        scene.mouseExited(with: leave)
        try await Task.sleep(for: .milliseconds(350))
        #expect(scene.cacheStatistics.live == 0)
        if let image = scene.cachedImage(for: item.id) {
            #expect(accentPixels(NSBitmapImageRep(cgImage: image)) == 0, "Cached pixels themselves must contain no transient highlight")
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(filePath: "/tmp/angrove-hover-cached-patch.png"))
        }
        #expect(try accentPixels(scene) < lit / 3, "The actual cached surface must not retain the old illuminated patch")
        scene.move(CanvasScrollTransform(scale: 1, offset: .zero), viewport: CGSize(width: 900, height: 700))
        try move(to: CGPoint(x: 850, y: 650))
        #expect(pointer.nearIDs.isEmpty)
        #expect(pointer.nearWorld == nil)
        try await Task.sleep(for: .milliseconds(200))
        #expect(try accentPixels(scene) < lit / 3, "Moving onto another native surface must clear the previous highlight")
        try move(to: CGPoint(x: 442, y: 380))
        scene.move(CanvasScrollTransform(scale: 1, offset: CGSize(width: -400, height: 0)), viewport: CGSize(width: 900, height: 700))
        #expect(pointer.nearIDs.isEmpty, "Panning away beneath a stationary cursor must clear its old spotlight")
        scene.move(CanvasScrollTransform(scale: 1, offset: .zero), viewport: CGSize(width: 900, height: 700))
        #expect(pointer.nearIDs.contains(item.id))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        #expect(pointer.nearIDs.isEmpty)
        try move(to: CGPoint(x: 442, y: 380))
        let exit = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        scene.mouseExited(with: exit)
        #expect(pointer.nearIDs.isEmpty)
        #expect(pointer.world == nil)
    }

    @Test func adjacentItemsOnlyRevealGripsInsideThePointerSpotlight() {
        let board = WorktreeBoard()
        var heading = WorktreeBoard.Item(origin: .zero, text: "Common Good")
        heading.isHeading = true
        let note = WorktreeBoard.Item(origin: CGPoint(x: 0, y: 100), text: "Okay, trying to get this straight…")
        board.items = [heading, note]
        board.itemSizes[heading.id] = CGSize(width: 360, height: 80)
        board.itemSizes[note.id] = CGSize(width: 600, height: 220)
        let pointer = WorktreeCanvasPointer()
        // Both boxes are nearby here, but their centred top grips are hundreds of points away.
        pointer.update(world: CGPoint(x: -8, y: 84), board: board, zoom: 1)
        #expect(pointer.nearIDs == [heading.id, note.id])
        #expect(!pointer.isNearControl(CGPoint(x: 180, y: -11.75), for: heading.id, board: board, zoom: 1))
        #expect(!pointer.isNearControl(CGPoint(x: 300, y: -11.75), for: note.id, board: board, zoom: 1))
        pointer.update(world: CGPoint(x: 172, y: -20), board: board, zoom: 1)
        #expect(pointer.isNearControl(CGPoint(x: 180, y: -11.75), for: heading.id, board: board, zoom: 1))
        #expect(!pointer.isNearControl(CGPoint(x: -12, y: 6), for: heading.id, board: board, zoom: 1))
        pointer.update(world: nil, board: board, zoom: 1)
        #expect(!pointer.isNearControl(CGPoint(x: 180, y: -11.75), for: heading.id, board: board, zoom: 1))
    }

    private func fixture() -> (WorktreeBoard, WorktreeBoard.Item, MacConversationState, MacApplicationRuntime) {
        let board = WorktreeBoard()
        let session = MacConversationState()
        session.savesConversation = false
        session.configure(preview: true)
        var branch = ChatBranch(startingConcept: nil)
        branch.topQuestionText = "What guides us?"
        branch.topQuestionSubmitted = true
        branch.activeChatBlocks = [.text("[Prudence](aq://Prudence) guides sound judgment.")]
        session.branches = [branch]
        session.selectedBranch = branch.id
        var item = WorktreeBoard.Item(origin: CGPoint(x: -200, y: -150))
        item.session = session
        item.size = CGSize(width: 400, height: 350)
        board.items = [item]
        return (board, item, session, MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue()))
    }
    private func makeWindow(_ host: NSView) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        return window
    }
    private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let view = view as? T { return view }
        return view.subviews.lazy.compactMap { find(type, in: $0) }.first
    }
    private func accentPixels(_ host: NSView) throws -> Int {
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return accentPixels(bitmap)
    }
    private func accentPixels(_ bitmap: NSBitmapImageRep) -> Int {
        var count = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if c.alphaComponent > 0.1 && c.redComponent > 0.25 && c.greenComponent > 0.25
                    && c.blueComponent < min(c.redComponent, c.greenComponent) * 0.85 { count += 1 }
            }
        }
        return count
    }
}
