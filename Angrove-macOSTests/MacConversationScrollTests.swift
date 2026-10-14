import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor
struct MacConversationScrollTests {
    @Test func scrollingDoesNotReevaluateTranscriptAndChromeRendersInBothAppearances() async throws {
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let evaluations = Evaluations()
            let host = NSHostingView(rootView: ScrollView {
                TranscriptProbe(evaluations: evaluations)
                    .frame(maxWidth: .infinity)
            }
            .modifier(MacConversationScrollChrome(title: "Conversation title", isCompact: false, showsCommands: false)))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 720),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            defer { window.contentView = nil; window.close() }
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            let scroll = try #require(findScrollView(in: host))
            let initialCount = evaluations.count
            // Include repeated scrolling within a region and both threshold crossings.
            for y in [40, 100, 199, 201, 260, 400, 800, 600, 300, 200, 100, 0] {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                scroll.reflectScrolledClipView(scroll.contentView)
                try await Task.sleep(for: .milliseconds(30))
                host.layoutSubtreeIfNeeded()
                #expect(evaluations.count == initialCount)
            }
            #expect(scroll.contentView.bounds.origin.y == 0)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: 400))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: FileManager.default.temporaryDirectory.appending(path: "angrove-scroll-\(name).png"))
        }
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { findScrollView(in: $0) }.first
    }

    private final class Evaluations {
        var count = 0
    }

    private struct TranscriptProbe: View {
        let evaluations: Evaluations
        var body: some View {
            evaluations.count += 1
            return Text(Array(repeating: "A response paragraph with enough text to scroll through the conversation.", count: 150).joined(separator: "\n\n"))
                .font(AngroveTheme.Typography.body)
                .foregroundStyle(AngroveTheme.Colors.paragraphText)
                .padding(24)
                .background(AngroveTheme.Colors.canvas)
        }
    }
}
