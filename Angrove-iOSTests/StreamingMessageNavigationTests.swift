import Observation
import SwiftUI
import Testing
import UIKit
@testable import Angrove_iOS

@Suite("Response rendering after navigation", .serialized)
@MainActor
struct StreamingMessageNavigationTests {
    @Observable
    final class SampleState {
        var text = ""
        var shouldStream = false
        var revealedCount = 0
    }

    private struct Sample: View {
        let state: SampleState

        var body: some View {
            StreamingMessageView(
                fullText: state.text,
                shouldStream: state.shouldStream,
                showsResponseActions: false,
                onRevealedWordCountChange: { state.revealedCount = $0 }
            )
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    @Test("A mounted empty placeholder renders the answer loaded after navigation",
          arguments: [UIUserInterfaceStyle.light, .dark])
    func restoredAnswerReplacesPlaceholder(style: UIUserInterfaceStyle) async throws {
        let state = SampleState()
        let window = host(state, style: style)
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(200))
        let emptyImage = renderedImage(window)

        // Preserve the renderer's identity, as when task completion reloads a saved slot.
        state.text = "Prudence guides practical judgment."
        try await Task.sleep(for: .milliseconds(200))
        #expect(state.revealedCount == 4)
        #expect(renderedImage(window) != emptyImage)

        // Later persisted annotations/text must reconcile too, without remounting the page.
        state.text = "Prudence guides practical judgment and wise action."
        try await Task.sleep(for: .milliseconds(200))
        #expect(state.revealedCount == 7)
    }

    @Test("Ending an interrupted reveal immediately presents the entire restored answer")
    func restoredPresentationEndsReveal() async throws {
        let state = SampleState()
        state.text = Array(repeating: "Prudence", count: 200).joined(separator: " ")
        state.shouldStream = true
        let window = host(state)
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(250))
        #expect(state.revealedCount > 0)
        #expect(state.revealedCount < 200)

        state.shouldStream = false
        try await Task.sleep(for: .milliseconds(200))
        #expect(state.revealedCount == 200)
    }

    private func host(_ state: SampleState, style: UIUserInterfaceStyle = .light) -> UIWindow {
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow()
        }
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 800)
        window.overrideUserInterfaceStyle = style
        let controller = UIHostingController(rootView: Sample(state: state))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        return window
    }

    private func renderedImage(_ window: UIWindow) -> Data? {
        window.layoutIfNeeded()
        return UIGraphicsImageRenderer(bounds: window.bounds).image { context in
            window.layer.render(in: context.cgContext)
        }.pngData()
    }
}
