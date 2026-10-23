import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor @Suite(.serialized)
struct MacBoardsScrollRenderingTests {
    @Test(arguments: [ColorScheme.light, .dark])
    func conversationRenderingAcrossScrollingAndCaching(_ scheme: ColorScheme) async throws {
        let board = WorktreeBoard()
        let session = MacConversationState()
        session.savesConversation = false
        session.configure(preview: true)
        var branch = ChatBranch(startingConcept: nil)
        branch.topQuestionText = "/define Supralapsarianism"
        branch.topQuestionSubmitted = true
        branch.activeChatBlocks = [.text(String(repeating: "The difference between these positions concerns the logical order of God's decrees. Practical wisdom considers these distinctions carefully. ", count: 16))]
        session.branches = [branch]
        session.selectedBranch = branch.id
        var item = WorktreeBoard.Item(origin: CGPoint(x: -200, y: -150))
        item.session = session
        item.size = CGSize(width: 400, height: 420)
        item.label = "Difference Between"
        board.items = [item]
        let runtime = MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue())
        let host = NSHostingView(rootView: MacWorktreeView(board: board, queuePopup: ModelTasksPopupState(), runtime: runtime).environment(\.colorScheme, scheme))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .seconds(2))
        let scene = try #require(find(WorktreeSceneView.self, in: host))
        let cached = try snapshot(host, name: "\(scheme)-cached")
        #expect(scene.subviews.first?.subviews.first?.accessibilityPerformPress() == true)
        try await Task.sleep(for: .milliseconds(200))
        let live = try snapshot(host, name: "\(scheme)-live")
        let labelRegion = CGRect(x: 220, y: 120, width: 350, height: 45)
        #expect(Double(ink(cached, in: labelRegion)) / Double(ink(live, in: labelRegion)) > 0.98,
                "The cached label must retain its complete glyph ascenders")
        let builds = scene.cacheStatistics.builds
        let scroll = try #require(find(NSScrollView.self, in: scene))
        let canvas = try #require(find(MacCanvasScrollInput.ScrollSurface.self, in: host))
        func wheel(_ phase: NSEvent.Phase, delta: Int32) throws -> NSEvent {
            let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0))
            cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
            return try #require(NSEvent(cgEvent: cg))
        }
        scroll.scrollWheel(with: try wheel(.began, delta: -2))
        scroll.contentView.scroll(to: CGPoint(x: 0, y: 20))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(for: .milliseconds(60))
        for index in 0..<8 {
            scroll.scrollWheel(with: try wheel(.changed, delta: -12))
            scroll.contentView.scroll(to: CGPoint(x: 0, y: CGFloat(index * 34)))
            scroll.reflectScrolledClipView(scroll.contentView)
            canvas.onScroll?(CGSize(width: 1, height: 0), [], CGPoint(x: 450, y: 350))
            try await Task.sleep(for: .milliseconds(40))
            #expect(scroll.window === window, "Do not unmount an internally scrolling card during camera updates")
            _ = try snapshot(host, name: "\(scheme)-scroll-\(index)")
        }
        #expect(scene.cacheStatistics.builds == builds, "Internal scrolling must not rebuild the bitmap")
        scroll.scrollWheel(with: try wheel(.ended, delta: 0))
        try await Task.sleep(for: .milliseconds(250))
        let scrolledOffset = scroll.contentView.bounds.origin
        #expect(scrolledOffset.y > 100)
        let beforeRecache = try snapshot(host, name: "\(scheme)-scrolled-live")
        let clip = scroll.convert(scroll.bounds, to: nil)
        let body = CGRect(x: clip.minX + 4, y: 700 - clip.maxY + 70, width: clip.width - 8, height: clip.height - 120)
        canvas.onScroll?(CGSize(width: 2, height: 0), [], CGPoint(x: 450, y: 350))
        try await Task.sleep(for: .milliseconds(350))
        let recached = try snapshot(host, name: "\(scheme)-scrolled-cached")
        #expect(scene.cacheStatistics.live == 0, "Settled camera movement returns the conversation to its cache")
        #expect(Double(ink(recached, in: body.offsetBy(dx: 2, dy: 0))) / Double(ink(beforeRecache, in: body)) > 0.9,
                "A cache transition must not blank or truncate the visible answer")
        #expect(scene.subviews.first?.subviews.first?.accessibilityPerformPress() == true)
        try await Task.sleep(for: .milliseconds(100))
        let restoredScroll = try #require(find(NSScrollView.self, in: scene))
        #expect(abs(restoredScroll.contentView.bounds.origin.y - scrolledOffset.y) < 1,
                "Returning to the live conversation preserves the reading position")
        try await Task.sleep(for: .milliseconds(250))
        canvas.onScroll?(CGSize(width: 0, height: log(1.7) / 0.012), .command, CGPoint(x: 220, y: 125))
        try await Task.sleep(for: .milliseconds(600))
        _ = try snapshot(host, name: "\(scheme)-zoomed-cached")
        #expect(scene.subviews.first?.subviews.first?.accessibilityPerformPress() == true)
        try await Task.sleep(for: .milliseconds(100))
        _ = try snapshot(host, name: "\(scheme)-zoomed-live")
    }
    private func ink(_ bitmap: NSBitmapImageRep, in rect: CGRect) -> Int {
        let factor = CGFloat(bitmap.pixelsWide) / 900
        let background = bitmap.colorAt(x: 20, y: 400)?.usingColorSpace(.deviceRGB)?.redComponent ?? 0
        var count = 0
        for y in Int(rect.minY * factor)..<Int(rect.maxY * factor) {
            for x in Int(rect.minX * factor)..<Int(rect.maxX * factor) {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), abs(color.redComponent - background) > 0.2 { count += 1 }
            }
        }
        return count
    }
    private func snapshot<V: View>(_ host: NSHostingView<V>, name: String) throws -> NSBitmapImageRep {
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(filePath: "/tmp/angrove-board-scroll-\(name).png"))
        return bitmap
    }
    private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let result = view as? T { return result }
        return view.subviews.lazy.compactMap { find(type, in: $0) }.first
    }
}
