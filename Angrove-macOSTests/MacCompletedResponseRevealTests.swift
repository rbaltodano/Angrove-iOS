import AppKit
import Observation
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor
struct MacCompletedResponseRevealTests {
    @Observable final class ResponseState {
        var text = ""
        var pending = true
        var starts = 0
        var finishes = 0
        var bodyFinishes = 0
        var visible = 0
    }

    struct ResponseCard: View {
        let state: ResponseState
        var body: some View {
            let presentation = MacConversationResponsePresentation(text: state.text, isPending: state.pending)
            ModelResponseCard(title: "", fullText: presentation.visibleText,
                isAwaitingResponse: presentation.isAwaitingResponse,
                isReceivingStream: presentation.isWriting, usesIncrementalStream: false,
                showsResponseActions: false,
                onRevealStart: { state.starts += 1 },
                onBodyRevealComplete: { state.bodyFinishes += 1 },
                onFinish: { state.finishes += 1 })
        }
    }

    struct CompletedBody: View {
        let state: ResponseState
        var body: some View {
            StreamingMessageView(fullText: state.text, usesIncrementalStream: false,
                showsResponseActions: false,
                onBodyRevealComplete: { state.bodyFinishes += 1 },
                onRevealedWordCountChange: { state.visible = $0 })
        }
    }

    @Test func partialFirstWordStaysInWritingUntilTheCompletedAnswerRevealsOnce() async throws {
        let state = ResponseState()
        let host = NSHostingView(rootView: ResponseCard(state: state))
        let window = mount(host)
        defer { window.contentView = nil; window.close() }
        state.text = "Prudence"
        try await Task.sleep(for: .seconds(1.6))
        #expect(state.starts == 0)
        #expect(state.bodyFinishes == 0)
        #expect(state.finishes == 0)
        #expect(MacConversationResponsePresentation(text: state.text, isPending: true).isWriting)
        state.text = "Prudence guides practical judgment.\n\nJustice gives each person their due."
        state.pending = false
        try await wait { state.finishes == 1 }
        #expect(state.starts == 1)
        #expect(state.bodyFinishes == 1)
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.finishes == 1)
    }

    @Test func paragraphsHeadingsAndListsShareOneRevealCounter() async throws {
        let state = ResponseState()
        state.text = Array(repeating: "Prudence", count: 100).joined(separator: " ")
            + "\n\n## Justice\n\n" + Array(repeating: "Justice", count: 100).joined(separator: " ")
            + "\n\n1. First example\n2. Second example"
        let host = NSHostingView(rootView: CompletedBody(state: state))
        let window = mount(host)
        defer { window.contentView = nil; window.close() }
        // SwiftUI may mount after 200 ms while other render suites are active.
        // Observe the first reveal update before checking its shared counter.
        try await wait { state.visible > 0 }
        #expect(state.visible < 100)
        #expect(state.bodyFinishes == 0)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: FileManager.default.temporaryDirectory.appending(path: "angrove-whole-response-reveal.png"))
        try await wait { state.bodyFinishes == 1 }
        #expect(state.visible == 205)
    }

    private func mount<Content: View>(_ host: NSHostingView<Content>) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 720),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        return window
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}
