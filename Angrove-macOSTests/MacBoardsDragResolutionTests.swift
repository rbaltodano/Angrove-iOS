import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor @Suite(.serialized)
struct MacBoardsDragResolutionTests {
    @Test(arguments: [false, true]) func pickupAfterZoomBuildsOneRetinaImageThenReusesIt(group: Bool) async throws {
        let board = WorktreeBoard()
        let session = MacConversationState()
        session.savesConversation = false
        session.configure(preview: true)
        var branch = ChatBranch(startingConcept: nil)
        branch.topQuestionText = "What is practical wisdom?"
        branch.topQuestionSubmitted = true
        branch.activeChatBlocks = [.text(String(repeating: "Practical wisdom guides our actions. ", count: 50))]
        session.branches = [branch]
        session.selectedBranch = branch.id
        var item = WorktreeBoard.Item(origin: CGPoint(x: -120, y: -100))
        item.session = session
        item.size = CGSize(width: 400, height: 420)
        board.items = [item]
        var companion = WorktreeBoard.Item(origin: CGPoint(x: 250, y: 200), text: "Selected heading")
        companion.isHeading = true
        if group {
            board.items.append(companion)
            board.selection = [item.id, companion.id]
        }
        let runtime = MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue())
        let host = NSHostingView(rootView: MacWorktreeView(board: board, queuePopup: ModelTasksPopupState(), runtime: runtime)
            .environment(\.colorScheme, .dark))
        let window = NSWindow(contentRect: CGRect(x: 50, y: 50, width: 1200, height: 900),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .seconds(2))
        let scene = try #require(find(WorktreeSceneView.self, in: host))
        for _ in 0..<100 where scene.cacheStatistics.live != 0 || scene.cachedImage(for: item.id) == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        let original = try #require(scene.cachedImage(for: item.id))
        let oldCompanion = group ? try #require(scene.cachedImage(for: companion.id)) : nil
        // Start dragging immediately after zoom, before the normal idle cache refresh.
        scene.move(CanvasScrollTransform(scale: 2, offset: .zero), viewport: scene.bounds.size)
        let frame = try #require(board.frame(of: item.id))
        let local = CGPoint(x: scene.bounds.midX + (frame.minX + 80) * 2,
                            y: scene.bounds.midY + (frame.minY + 14) * 2)
        let start = scene.convert(local, to: nil)
        func post(_ type: NSEvent.EventType, _ delta: CGFloat) throws {
            let event = try #require(NSEvent.mouseEvent(with: type,
                location: CGPoint(x: start.x + delta, y: start.y - delta / 4), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            NSApp.postEvent(event, atStart: false)
        }
        try post(.leftMouseDown, 0)
        try await Task.sleep(for: .milliseconds(10))
        try post(.leftMouseDragged, 4)
        for _ in 0..<18 {
            let presentation = try #require(scene.presentationState(for: item.id))
            #expect(presentation.imageVisible || presentation.liveVisible, "A resolution handoff must never expose an empty frame")
            if presentation.staging {
                #expect(presentation.imageVisible && !presentation.liveVisible,
                        "The previous image must cover the staging transcript until its sharp replacement is ready")
            }
            try await Task.sleep(for: .milliseconds(8))
        }
        let sharp = try #require(scene.cachedImage(for: item.id))
        #expect(sharp.width >= original.width * 2 - 2)
        #expect(sharp.height >= original.height * 2 - 2)
        #expect(brightPixels(sharp) > brightPixels(original) * 3,
                "Staging must render the actual text, not a transparent or empty high-resolution bitmap")
        #expect(scene.cacheStatistics.live == 0)
        if let oldCompanion {
            let newCompanion = try #require(scene.cachedImage(for: companion.id))
            #expect(newCompanion.width >= oldCompanion.width * 2 - 2)
        }
        let builds = scene.cacheStatistics.builds
        for step in 1...30 {
            try post(.leftMouseDragged, CGFloat(step * 4))
            try await Task.sleep(for: .milliseconds(16))
        }
        #expect(scene.cachedImage(for: item.id) === sharp)
        #expect(scene.cacheStatistics.builds == builds)
        #expect(scene.cacheStatistics.bytes <= 128 * 1024 * 1024)
        let bitmap = NSBitmapImageRep(cgImage: sharp)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(filePath: "/tmp/angrove-retina-drag-200.png"))
        try post(.leftMouseUp, 120)
        try await Task.sleep(for: .milliseconds(100))
        #expect(board.items[0].origin != item.origin)
        if group { #expect(board.items[1].origin != companion.origin) }
        board.undo()
        #expect(board.items[0].origin == item.origin)
        if group { #expect(board.items[1].origin == companion.origin) }
    }
    private func brightPixels(_ image: CGImage) -> Int {
        let bitmap = NSBitmapImageRep(cgImage: image)
        var count = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.alphaComponent > 0.5 && color.redComponent + color.greenComponent + color.blueComponent > 1.8 {
                    count += 1
                }
            }
        }
        return count
    }

    private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let result = view as? T { return result }
        return view.subviews.lazy.compactMap { find(type, in: $0) }.first
    }
}
