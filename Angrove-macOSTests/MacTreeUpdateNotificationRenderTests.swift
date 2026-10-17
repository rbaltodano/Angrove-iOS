import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor
struct MacTreeUpdateNotificationRenderTests {
    @Test func updateQuestionFitsSmallPhoneWidthInBothAppearances() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let view = VStack {
                Spacer()
                TreeUpdateNotificationPill(title: "Update Tree?", onUpdate: {}, onKeepCurrent: {})
                    .padding(24)
            }
            .frame(width: 320, height: 150)
            .background(AngroveTheme.Colors.canvas)
            .environment(\.colorScheme, scheme)
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 150),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.contentView = nil; window.close() }
            try await Task.sleep(for: .milliseconds(150))
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(filePath: NSTemporaryDirectory() + "angrove-update-tree-\(scheme == .light ? "light" : "dark").png"))
        }
    }
}
