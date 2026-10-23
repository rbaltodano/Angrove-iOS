import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor @Suite(.serialized)
struct MacBoardsMenuGeometryTests {
    @Test func wordMenusFollowPanZoomAndClipToTheConversationViewport() async throws {
        let driver = MenuGeometryDriver()
        let host = NSHostingView(rootView: MenuGeometryFixture(driver: driver))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(150))
        for scale: CGFloat in [1, 0.5, 2, 0.8] {
            driver.scale = scale
            driver.offset = CGSize(width: 30 * scale, height: 20 * scale)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            for (index, title) in ["First", "Second"].enumerated() {
                let local = CGPoint(x: 40 + driver.offset.width + 120 * scale,
                                    y: 40 + driver.offset.height + CGFloat(index * 44 + 22) * scale)
                let entries = MacContextMenuRegistry.entries(at: host.convert(local, to: nil), in: window)
                #expect(entries.first?.title == title, "Correct row at zoom \(scale)")
            }
            let below = CGPoint(x: 40 + driver.offset.width + 120 * scale,
                                y: 40 + driver.offset.height + 110 * scale)
            #expect(MacContextMenuRegistry.entries(at: host.convert(below, to: nil), in: window).isEmpty)
        }
        driver.scrollToThird = true
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let top = CGPoint(x: 40 + driver.offset.width + 120 * driver.scale,
                          y: 40 + driver.offset.height + 22 * driver.scale)
        #expect(MacContextMenuRegistry.entries(at: host.convert(top, to: nil), in: window).first?.title == "Third")
        driver.suffix = " updated"
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        #expect(MacContextMenuRegistry.entries(at: host.convert(top, to: nil), in: window).first?.title == "Third updated")
    }
}

@MainActor @Observable private final class MenuGeometryDriver {
    var scale: CGFloat = 1
    var offset = CGSize.zero
    var scrollToThird = false
    var suffix = ""
}

private struct MenuGeometryFixture: View {
    let driver: MenuGeometryDriver
    @State private var position = ScrollPosition(idType: Int.self)

    var body: some View {
        let suffix = driver.suffix
        ZStack(alignment: .topLeading) {
            Color.clear
            MacContextMenuContainer {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(["First", "Second", "Third", "Fourth", "Fifth"].enumerated()), id: \.offset) { index, title in
                            Text(title).frame(width: 240, height: 44)
                                .macContextMenu { [MacMenuEntry(LocalizedStringResource(stringLiteral: title + suffix)) {}] }
                                .id(index)
                        }
                    }
                }
                .scrollPosition($position)
                .frame(width: 240, height: 88)
                .onChange(of: driver.scrollToThird) { _, _ in position.scrollTo(id: 2, anchor: .top) }
            }
            .scaleEffect(driver.scale, anchor: .topLeading)
            .offset(x: 40 + driver.offset.width, y: 40 + driver.offset.height)
        }
        .frame(width: 900, height: 700, alignment: .topLeading)
    }
}
