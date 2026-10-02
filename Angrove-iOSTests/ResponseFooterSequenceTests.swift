import SwiftUI
import Testing
import UIKit
@testable import Angrove_iOS

@Suite("Response finishing sequence", .serialized)
@MainActor
struct ResponseFooterSequenceTests {
    private final class Completion {
        var body: ContinuousClock.Instant?
        var footer: ContinuousClock.Instant?
        var count = 0
    }

    private func host<V: View>(_ content: V) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 340, height: 800))
        window.rootViewController = UIHostingController(rootView: content)
        window.makeKeyAndVisible()
        window.rootViewController?.view.frame = window.bounds
        window.rootViewController?.view.layoutIfNeeded()
        return window
    }

    @Test("Footer completion waits for concurrent actions and disclaimer after body reveal")
    func liveResponseSequence() async throws {
        let completion = Completion()
        let window = host(StreamingMessageView(
            fullText: "A completed answer.", shouldStream: true,
            onRegenerate: {}, onBranch: {},
            onBodyRevealComplete: { completion.body = .now },
            onFinish: { completion.footer = .now; completion.count += 1 }
        ))
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .seconds(4))
        let body = try #require(completion.body)
        let footer = try #require(completion.footer)
        #expect(body.duration(to: footer) >= .seconds(0.45))
        #expect(body.duration(to: footer) < .seconds(0.85))
        #expect(completion.count == 1)
    }

    @Test("Restored footers finish immediately without replaying their reveal")
    func restoredFooter() async throws {
        let completion = Completion()
        let window = host(ModelResponseFooter(
            copyText: "Saved answer", onRegenerate: {}, onBranch: {},
            shouldAnimateOnAppear: false,
            onRevealComplete: { completion.count += 1 }
        ))
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(150))
        #expect(completion.count == 1)
    }

    @Test("Removing a footer cancels its pending composer reveal")
    func removalCancelsSequence() async throws {
        let completion = Completion()
        let window = host(ModelResponseFooter(
            copyText: "An answer", onRegenerate: {}, onBranch: {},
            shouldAnimateOnAppear: true,
            onRevealComplete: { completion.count += 1 }
        ))
        try await Task.sleep(for: .milliseconds(150))
        window.isHidden = true
        window.rootViewController = nil
        try await Task.sleep(for: .seconds(2.5))
        #expect(completion.count == 0)
    }

    @Test("Answers with no actions complete without waiting for an absent footer")
    func noActions() async throws {
        let completion = Completion()
        let window = host(StreamingMessageView(
            fullText: "Question canceled", shouldStream: true,
            showsResponseActions: false,
            onFinish: { completion.count += 1 }
        ))
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .seconds(1.2))
        #expect(completion.count == 1)
    }
}
