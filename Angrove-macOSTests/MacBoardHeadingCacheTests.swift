import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor @Suite(.serialized)
struct MacBoardHeadingCacheTests {
    /// The canvas swaps settled items for bitmaps; a heading's bitmap must contain its words.
    @Test func cachedHeadingShowsItsText() async throws {
        let board = WorktreeBoard()
        var heading = WorktreeBoard.Item(origin: CGPoint(x: -200, y: -60), text: "Cached Heading Text")
        heading.isHeading = true
        board.items = [heading]
        let runtime = MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue())
        let host = NSHostingView(rootView: MacWorktreeView(board: board, queuePopup: ModelTasksPopupState(), runtime: runtime)
            .environment(\.colorScheme, .light))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .seconds(2))
        let scene = try #require(find(WorktreeSceneView.self, in: host))
        for _ in 0..<100 where scene.cachedImage(for: heading.id) == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        let image = try #require(scene.cachedImage(for: heading.id))
        #expect(inkedPixels(in: image) > 500, "The cached heading must include its glyphs")
    }

    /// Camera movement during a heading's word reveal must not freeze an unrevealed bitmap.
    @Test func movingDuringRevealKeepsHeadingText() async throws {
        let board = WorktreeBoard()
        board.items = [WorktreeBoard.Item(origin: CGPoint(x: -280, y: -120), text: "A note already here")]
        let runtime = MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue())
        let host = NSHostingView(rootView: MacWorktreeView(board: board, queuePopup: ModelTasksPopupState(), runtime: runtime)
            .environment(\.colorScheme, .light))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .seconds(2))
        #expect(board.openCommand(freeOrigin: CGPoint(x: -100, y: 40)))
        try await Task.sleep(for: .milliseconds(300))
        board.commandText = "/heading Typed Heading"
        board.submitCommand(runtime: runtime)
        let scene = try #require(find(WorktreeSceneView.self, in: host))
        let scroll = try #require(find(MacCanvasScrollInput.ScrollSurface.self, in: host))
        let id = try #require(board.items.first(where: \.isHeading)?.id)
        // Two short pans during the reveal: the first prepares a snapshot, the second used to take it.
        for _ in 0..<2 {
            try await Task.sleep(for: .milliseconds(60))
            for _ in 0..<3 {
                scroll.onScroll?(CGSize(width: 2, height: 0), [], CGPoint(x: 450, y: 350))
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(8))
            }
            try await Task.sleep(for: .milliseconds(220))
        }
        try await Task.sleep(for: .seconds(3))
        let state = try #require(scene.presentationState(for: id))
        if state.imageVisible {
            let image = try #require(scene.cachedImage(for: id))
            #expect(inkedPixels(in: image) > 11_000, "A visible heading bitmap must show its whole text")
        } else {
            #expect(state.liveVisible)
        }
    }

    private func inkedPixels(in image: CGImage) -> Int {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 0, to: pixels.count, by: 4).reduce(0) { $0 + (pixels[$1 + 3] > 128 ? 1 : 0) }
    }

    private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { find(type, in: $0) }.first
    }
}
