import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor @Observable private final class RenameFlowModel {
    var selection = MacDestination.conversations
    var renamingID: UUID?
    var finished: [String?] = []
}

private struct RenameFlowHost: View {
    let model: RenameFlowModel
    let conversations: [InquiryConversation]

    var body: some View {
        MacFloatingSidebar(selection: Binding(get: { model.selection }, set: { model.selection = $0 }),
            showsFixture: false, conversations: conversations,
            openConversation: { _ in }, newConversation: {}, openPreview: {},
            activeConversationID: conversations[0].id, openMenuID: nil, openMenu: { _ in },
            renamingConversationID: model.renamingID,
            beginRename: { model.renamingID = $0 },
            finishRename: { id, title in
                if model.renamingID == id { model.renamingID = nil }
                model.finished.append(title)
            }, menuAction: { _, _ in })
    }
}

@MainActor @Suite(.serialized)
struct MacSidebarRenameFlowTests {
    @Test func sidebarRenameAcceptsTypingAndCommits() async throws {
        let conversations = [InquiryConversation(title: "First conversation"), InquiryConversation(title: "Second conversation")]
        let model = RenameFlowModel()
        let host = NSHostingView(rootView: RenameFlowHost(model: model, conversations: conversations))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 800),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .seconds(1.5))
        model.renamingID = conversations[1].id
        try await Task.sleep(for: .milliseconds(600))
        #expect(model.finished.isEmpty, "The field must stay open after mounting")
        let editor = try #require(window.firstResponder as? NSTextView, "The rename field must take focus")
        editor.insertText("Renamed", replacementRange: editor.selectedRange())
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.finished == ["Renamed"])
    }
}
