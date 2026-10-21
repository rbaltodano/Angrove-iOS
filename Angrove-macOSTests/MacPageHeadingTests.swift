import AppKit
import Observation
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor
@Suite(.serialized)
struct MacPageHeadingTests {
    @Observable final class RevealState { var canReveal = false; var title = "Settings" }

    struct IntroductionFixture: View {
        let state: RevealState
        var body: some View {
            MacPageIntroduction(title: state.title, description: "Choose how Angrove looks, works, and fits your conversations.")
                .padding(32)
                .frame(width: 640, height: 240, alignment: .topLeading)
                .background(AngroveTheme.Colors.canvas)
                .environment(\.isBootPageRevealAnimating, state.canReveal)
                .environment(\.colorScheme, .light)
        }
    }

    @Test func headingAndParagraphRespectMotionPreferenceWithoutMovingTheirLayout() async throws {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let state = RevealState()
        let host = NSHostingView(rootView: IntroductionFixture(state: state))
        let window = mount(host)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(100))
        let before = try capture(host)
        let size = host.fittingSize
        state.canReveal = true
        try await Task.sleep(for: .milliseconds(1100))
        let after = try capture(host)
        // Reduced motion displays text immediately, bypassing the boot reveal gate.
        #expect((before != after) == !reduceMotion)
        #expect(host.fittingSize == size)
        try after.write(to: URL(filePath: NSTemporaryDirectory() + "angrove-heading-revealed.png"))
    }

    @Test func changingAnAlreadyRevealedHeadingRevealsItsReplacement() async throws {
        let state = RevealState()
        state.canReveal = true
        let host = NSHostingView(rootView: IntroductionFixture(state: state))
        let window = mount(host)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(1100))
        let before = try capture(host)
        state.title = "Your Settings"
        try await Task.sleep(for: .milliseconds(1100))
        #expect(before != (try capture(host)))
    }

    private func mount<Content: View>(_ host: NSHostingView<Content>) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 240), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        return window
    }

    private func capture<Content: View>(_ host: NSHostingView<Content>) throws -> Data {
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}
