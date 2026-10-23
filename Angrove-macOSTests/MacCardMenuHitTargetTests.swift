import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor @Suite(.serialized)
struct MacCardMenuHitTargetTests {
    @Test func clickingOutsideTheOldTargetOpensMenuWithoutOpeningCard() async throws {
        var openedCard = false
        let host = NSHostingView(rootView:
            ZStack {
                AngroveTheme.Colors.canvasSecondary
                MacActionMenu(entries: { [MacMenuEntry("Rename", symbol: "pencil.line") {}] }) {
                    MacCollectionCardOptionsLabel()
                }
                .buttonStyle(.plain)
            }
            .frame(width: 200, height: 120)
            .contentShape(Rectangle())
            .onTapGesture { openedCard = true }
        )
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 120),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            MacMenuPresenter.shared.dismiss()
            window.contentView = nil
            window.close()
        }
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        // Twenty points from the icon's center, including square corners: outside both
        // the former 22pt conversation button and the former 28pt circular buttons.
        for offset in [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0), CGPoint(x: -20, y: 0),
                       CGPoint(x: 0, y: 20), CGPoint(x: 20, y: 20)] {
            MacMenuPresenter.shared.dismiss()
            let point = CGPoint(x: 100 + offset.x, y: 60 + offset.y)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(NSEvent.mouseEvent(with: type, location: point,
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                    clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
                NSApp.postEvent(event, atStart: false)
            }
            try await Task.sleep(for: .milliseconds(100))
            #expect(MacMenuPresenter.shared.panel != nil)
            #expect(!openedCard)
            #expect(MacMenuPresenter.shared.state.entries.map(\.title) == ["Rename"])
        }
    }
}
