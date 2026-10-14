import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor
struct MacSidebarInlineRenameTests {
    @Test func returnCommitsOnceAndEscapeDiscardsTheDraft() {
        var results: [String?] = []
        let coordinator = MacSidebarRenameField.Coordinator { results.append($0) }
        let field = NSTextField(string: "Original")
        let editor = NSTextView()
        editor.string = "Renamed conversation"
        #expect(coordinator.control(field, textView: editor,
            doCommandBy: #selector(NSResponder.insertNewline(_:))))
        coordinator.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        #expect(results.count == 1)
        #expect(results[0] == "Renamed conversation")

        results = []
        let cancel = MacSidebarRenameField.Coordinator { results.append($0) }
        #expect(cancel.control(field, textView: editor,
            doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        cancel.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        #expect(results.count == 1)
        #expect(results[0] == nil)
    }

    @Test func losingFocusCommitsCurrentTextAndOrdinaryEditingKeysRemainNative() {
        var saved: String?
        let coordinator = MacSidebarRenameField.Coordinator { saved = $0 }
        let field = NSTextField(string: "A new title")
        #expect(!coordinator.control(field, textView: NSTextView(),
            doCommandBy: #selector(NSResponder.moveLeft(_:))))
        coordinator.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        #expect(saved == "A new title")
    }

    @Test func mountedFieldSelectsTheWholeTitleForImmediateReplacement() async throws {
        var results: [String?] = []
        let coordinator = MacSidebarRenameField.Coordinator { results.append($0) }
        let field = MacSidebarRenameField.TitleField(string: "Original conversation")
        field.delegate = coordinator
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 44),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        field.frame = NSRect(x: 12, y: 8, width: 216, height: 28)
        window.contentView?.addSubview(field)
        defer { field.stopMonitoringClicks(); window.close() }
        try await Task.sleep(for: .milliseconds(50))
        #expect(results.isEmpty)
        let editor = try #require(field.currentEditor() as? NSTextView)
        #expect(editor.selectedRange() == NSRange(location: 0, length: (field.stringValue as NSString).length))
        editor.insertText("Replacement", replacementRange: editor.selectedRange())
        #expect(editor.string == "Replacement")
    }

    @Test func mountedInlineEditorStaysOpenAfterInitialSelection() async throws {
        var results: [String?] = []
        let row = MacSidebarConversationRow(
            conversation: InquiryConversation(title: "Original conversation"),
            isSelected: true, isMenuOpen: false, onOpen: {}, onMenu: {},
            isRenaming: true, onRename: {}, onFinishRename: { results.append($0) })
        let host = NSHostingView(rootView: row)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 232, height: 44),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        #expect(results.isEmpty)
        let editor = try #require(window.firstResponder as? NSTextView)
        #expect(editor.selectedRange() == NSRange(location: 0, length: 21))
    }

    @Test func narrowRowsRenderInBothAppearances() throws {
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let row = MacSidebarConversationRow(
                conversation: InquiryConversation(title: "A long conversation title that exceeds the sidebar width"),
                isSelected: true, isMenuOpen: false, onOpen: {}, onMenu: {},
                isRenaming: true, onRename: {}, onFinishRename: { _ in })
            let host = NSHostingView(rootView: row)
            host.appearance = NSAppearance(named: appearance)
            host.frame = NSRect(x: 0, y: 0, width: 232, height: 44)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: FileManager.default.temporaryDirectory.appending(path: "angrove-inline-rename-\(name).png"))
            #expect(host.fittingSize.height <= 44)
        }
    }
}
