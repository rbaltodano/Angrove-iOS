import AppKit
import Observation
import SwiftUI
import Testing
@testable import AngroveMac

struct MacModelControlHoverTests {
    @Test func labelsCenterOverTheirButtonAndStayInsideNarrowPanes() {
        let width = 160.0
        let pane = 350.0
        let centered = MacModelControlHoverLayout.leadingX(buttonX: 175, labelWidth: width, availableWidth: pane)
        #expect(centered + width / 2 == 175)
        let leading = MacModelControlHoverLayout.leadingX(buttonX: 12, labelWidth: width, availableWidth: pane)
        let trailing = MacModelControlHoverLayout.leadingX(buttonX: 338, labelWidth: width, availableWidth: pane)
        #expect(leading >= 0)
        #expect(trailing + width <= pane)
    }

    @MainActor
    @Test func hostKeepsBothAnchorsAndHoverDoesNotChangeDockHeight() async throws {
        let state = HoverProbe()
        let host = NSHostingView(rootView: HoverFixture(state: state))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 350, height: 150),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        try await wait { state.receivedHelp != nil }
        let button = try #require(state.button)
        let pill = try #require(state.pill)
        #expect(pill.contains(button))
        #expect(state.receivedHelp?.shortcut == "⌘M")
        let height = host.fittingSize.height
        state.isHovered = false
        try await wait { state.receivedHelp == nil }
        host.layoutSubtreeIfNeeded()
        #expect(abs(host.fittingSize.height - height) < 1)
    }

    @MainActor
    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}

@MainActor @Observable
private final class HoverProbe {
    var isHovered = true
    var receivedHelp: MacModelControlHelp?
    var button: CGRect?
    var pill: CGRect?
}

private struct HoverFixture: View {
    let state: HoverProbe

    var body: some View {
        ModelControlsHost(configuration: ModelControlsConfiguration(id: "hover-test", buttons: AnyView(
            Button("Idle") {}
                .anchorPreference(key: MacModelControlHoverKey.self, value: .bounds) {
                    state.isHovered ? MacModelControlHoverPreference(
                        help: MacModelControlHelp(title: "Model Tasks", shortcut: "⌘M"), button: $0
                    ) : .init()
                }
        )))
        .overlayPreferenceValue(MacModelControlHoverKey.self) { preference in
            GeometryReader { geometry in
                Color.clear.task(id: preference.help) {
                    state.receivedHelp = preference.help
                    state.button = preference.button.map { geometry[$0] }
                    state.pill = preference.pill.map { geometry[$0] }
                }
            }
        }
    }
}
