import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

struct MacInsightCardWidthTests {
    @Test func bothEdgesExpandOutwardAndContractInward() {
        #expect(MacInsightCardWidth.resized(from: 500, translation: -25, isLeftEdge: true) == 550)
        #expect(MacInsightCardWidth.resized(from: 500, translation: 25, isLeftEdge: false) == 550)
        #expect(MacInsightCardWidth.resized(from: 500, translation: 25, isLeftEdge: true) == 450)
        #expect(MacInsightCardWidth.resized(from: 500, translation: -25, isLeftEdge: false) == 450)
    }

    @MainActor @Test func nativeEdgesResizeOnePreferenceSharedByNewCards() throws {
        let suite = "MacInsightCardWidthTests-\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        func makeHost() -> NSHostingView<some View> {
            NSHostingView(rootView: Color.clear.frame(height: 160)
                .modifier(MacInsightCardSizing()).frame(width: 800, height: 400)
                .defaultAppStorage(store))
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = makeHost()
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let edge = try #require(host.hitTest(NSPoint(x: 594, y: 200)))
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown,
            location: NSPoint(x: 594, y: 200), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let drag = try #require(NSEvent.mouseEvent(with: .leftMouseDragged,
            location: NSPoint(x: 644, y: 200), modifierFlags: [], timestamp: 1,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        edge.mouseDown(with: down)
        edge.mouseDragged(with: drag)
        #expect(store.double(forKey: MacInsightCardWidth.storageKey) == 500)
        // A newly mounted card uses the same saved preference and has its edge at 650.
        let next = makeHost()
        window.contentView = next
        next.layoutSubtreeIfNeeded()
        let nextEdge = try #require(next.hitTest(NSPoint(x: 644, y: 200)))
        #expect(nextEdge.frame.width == 12)
        #expect(nextEdge.frame.height == 104)
    }

    @Test func largeDragsStopAtTheWidthLimits() {
        #expect(MacInsightCardWidth.resized(from: 500, translation: -1000, isLeftEdge: true) == 600)
        #expect(MacInsightCardWidth.resized(from: 500, translation: -1000, isLeftEdge: false) == 400)
        #expect(MacInsightCardWidth.clamped(.nan) == 400)
    }

    @Test func narrowPanesDoNotOverwriteThePreferredWidth() {
        #expect(MacInsightCardWidth.visible(600, available: 450) == 450)
        #expect(MacInsightCardWidth.visible(600, available: 800) == 600)
        #expect(MacInsightCardWidth.visible(600, available: nil) == 600)
        #expect(MacInsightCardWidth.visible(500, available: 300) == 400)
    }
}
