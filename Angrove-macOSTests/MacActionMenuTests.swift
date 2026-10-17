import AppKit
import Testing
import SwiftUI
@testable import AngroveMac

@MainActor @Suite(.serialized)
struct MacActionMenuTests {
    @Test func placementStaysInsideScreenIncludingNegativeScreenOriginsAndTallMenus() {
        let screen = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        for point in [CGPoint(x: -1439, y: 699), CGPoint(x: -1, y: -199)] {
            let frame = MacMenuPresenter.placement(origin: point, size: CGSize(width: 260, height: 2000), visible: screen)
            #expect(screen.contains(frame))
            #expect(frame.width == 260)
            #expect(frame.height == screen.height - 16)
        }
    }
    @Test func keyboardSelectionWrapsAndSkipsDisabledRowsAndSeparators() {
        let first = MacMenuEntry("Copy") {}
        let last = MacMenuEntry("Delete", destructive: true) {}
        let state = MacMenuState()
        state.entries = [first, .divider, MacMenuEntry("Unavailable", enabled: false) {}, last]
        state.move(1); #expect(state.selectedID == first.id)
        state.move(1); #expect(state.selectedID == last.id)
        state.move(1); #expect(state.selectedID == first.id)
        state.move(-1); #expect(state.selectedID == last.id)
        state.entries = []; state.move(1)
        #expect(state.selectable.isEmpty)
    }
    @Test func actionsDismissBeforeExecutingAndDisabledActionsDoNothing() async throws {
        let presenter = MacMenuPresenter.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { presenter.dismiss(); window.close() }
        var count = 0
        let action = MacMenuEntry("Copy") { #expect(presenter.panel == nil); count += 1 }
        presenter.show([action], at: CGPoint(x: 100, y: 400), in: window)
        presenter.select(MacMenuEntry("Disabled", enabled: false) { count += 100 })
        #expect(count == 0 && presenter.panel != nil)
        presenter.select(action)
        try await Task.sleep(for: .milliseconds(40))
        #expect(count == 1 && presenter.panel == nil)
        try writeMenuPreviews()
    }
    @Test func arrowReturnAndEscapeKeysOperateThePopup() async throws {
        let presenter = MacMenuPresenter.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { presenter.dismiss(); window.close() }
        var selected = 0
        let entries = [MacMenuEntry("First") { selected = 1 }, MacMenuEntry("Second") { selected = 2 }]
        func key(_ code: UInt16) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: presenter.panel?.windowNumber ?? 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
        }
        presenter.show(entries, at: CGPoint(x: 100, y: 400), in: window)
        presenter.panel?.keyDown(with: try key(125))
        presenter.panel?.keyDown(with: try key(125))
        #expect(presenter.state.selectedID == entries[1].id)
        presenter.panel?.keyDown(with: try key(36))
        try await Task.sleep(for: .milliseconds(40))
        #expect(selected == 2 && presenter.panel == nil)
        presenter.show(entries, at: CGPoint(x: 100, y: 400), in: window)
        presenter.panel?.keyDown(with: try key(53))
        #expect(presenter.panel == nil && selected == 2)
    }
    @Test func nativeMenuKeepsOriginalTargetActionAndNestedItems() async throws {
        let receiver = Receiver()
        let menu = NSMenu(); menu.autoenablesItems = false
        let item = NSMenuItem(title: "Copy", action: #selector(Receiver.run), keyEquivalent: "")
        item.target = receiver
        menu.addItem(item)
        menu.addItem(.separator())
        let submenu = NSMenu(); submenu.autoenablesItems = false
        submenu.addItem(withTitle: "Nested", action: nil, keyEquivalent: "")
        let parent = NSMenuItem(title: "More", action: nil, keyEquivalent: ""); parent.submenu = submenu
        menu.addItem(parent)
        let entries = MacMenuEntry.native(menu)
        #expect(entries.count == 3 && entries[1].separator)
        #expect(entries[2].children.first?.title == "Nested")
        entries[0].action()
        #expect(receiver.count == 1)
    }
    @Test func rightClickUsesTheVisibleRowInsteadOfASiblingHostingView() async throws {
        let host = NSHostingView(rootView:
            VStack(spacing: 0) {
                ForEach(["First", "Second", "Third"], id: \.self) { title in
                    Text(title).frame(width: 240, height: 44)
                        .macContextMenu { [MacMenuEntry(LocalizedStringResource(stringLiteral: title)) {}] }
                }
                Spacer(minLength: 0)
            }.frame(width: 240, height: 240, alignment: .topLeading)
        )
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 240, height: 240), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        for (index, title) in ["First", "Second", "Third"].enumerated() {
            let point = host.convert(CGPoint(x: 120, y: index * 44 + 22), to: nil)
            #expect(MacContextMenuRegistry.entries(at: point, in: window).first?.title == title)
        }
        #expect(MacContextMenuRegistry.entries(at: host.convert(CGPoint(x: 120, y: 200), to: nil), in: window).isEmpty)
    }
    @Test func textMenusRespectSelectionAndReadOnlyStateAndKeepLibraryActions() {
        let text = NSTextView()
        text.string = "A sample passage"
        text.setSelectedRange(NSRange(location: 0, length: 1))
        text.isEditable = false
        var asked = false
        let entries = MacNativeContextMenus.editingEntries(for: text, additional: [MacMenuEntry("Ask") { asked = true }])
        #expect(entries.contains { $0.title == "Copy" && $0.enabled })
        #expect(!entries.contains { $0.title == "Cut" || $0.title == "Paste" })
        entries.first { $0.title == "Ask" }?.action()
        #expect(asked)
        text.isEditable = true
        text.setSelectedRange(NSRange(location: 0, length: 0))
        let editing = MacNativeContextMenus.editingEntries(for: text, canPaste: true)
        #expect(editing.contains { $0.title == "Copy" && !$0.enabled })
        #expect(editing.contains { $0.title == "Cut" && !$0.enabled })
        #expect(editing.contains { $0.title == "Paste" && $0.enabled })
    }
    @Test func submenuBackRowReturnsWithoutDismissingOrFiringAnAction() {
        let presenter = MacMenuPresenter.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { presenter.dismiss(); window.close() }
        var fired = false
        var parent = MacMenuEntry("More") {}
        parent.children = [MacMenuEntry("Nested") { fired = true }]
        presenter.show([parent], at: CGPoint(x: 100, y: 400), in: window)
        presenter.select(parent)
        let back = presenter.state.entries.first { $0.isNavigationBack }
        #expect(back != nil)
        if let back { presenter.select(back) }
        #expect(presenter.state.entries.first?.id == parent.id)
        #expect(presenter.panel != nil && !fired)
    }
    /// Export the actual shared component for focused light/dark visual inspection.
    private func writeMenuPreviews() throws {
        let entries = [MacMenuEntry("Insights", symbol: "text.bubble") {},
                       MacMenuEntry("Passages", symbol: "books.vertical") {}, .divider,
                       MacMenuEntry("Photos…", symbol: "photo.on.rectangle") {},
                       MacMenuEntry("Image File…", symbol: "doc") {}]
        for (name, scheme, appearance) in [("light", ColorScheme.light, NSAppearance.Name.aqua), ("dark", .dark, .darkAqua)] {
            let host = NSHostingView(rootView: MacMenuContent(entries: entries, select: { _ in }).environment(\.colorScheme, scheme))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 260, height: MacMenuPresenter.height(for: entries)), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(filePath: NSTemporaryDirectory() + "angrove-menu-style-\(name).png"))
            window.contentView = nil
            window.close()
        }
    }
    final class Receiver: NSObject {
        var count = 0
        @objc func run() { count += 1 }
    }
}
