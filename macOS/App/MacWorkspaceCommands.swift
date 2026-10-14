import AppKit
import SwiftUI

struct MacShortcutRequest: Equatable {
    enum Action: Equatable {
        case newConversation, focusQuestion, openTree, swapPanes, pinPanes, openQueue
        case openGlobalTree, goBack, goForward
        case recentConversation(Int)
    }
    let id = UUID()
    let action: Action
}

struct MacWorkspaceCommandTarget {
    var request: Binding<MacShortcutRequest?>
    let recentConversationIDs: [UUID]
    var canGoBack = false
    var canGoForward = false

    func send(_ action: MacShortcutRequest.Action) {
        request.wrappedValue = MacShortcutRequest(action: action)
    }

    static func recentIDs(in conversations: [InquiryConversation]) -> [UUID] {
        Array(conversations.filter { !$0.isStudyTopic }.reversed().prefix(9).map(\.id))
    }
}

private struct MacWorkspaceCommandKey: FocusedValueKey {
    typealias Value = MacWorkspaceCommandTarget
}

extension FocusedValues {
    var macWorkspaceCommands: MacWorkspaceCommandTarget? {
        get { self[MacWorkspaceCommandKey.self] }
        set { self[MacWorkspaceCommandKey.self] = newValue }
    }
}

struct MacWorkspaceCommands: Commands {
    @FocusedValue(\.macWorkspaceCommands) private var target

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Conversation") { target?.send(.newConversation) }
                .keyboardShortcut("n")
                .disabled(target == nil)
        }
        CommandMenu("Conversation") {
            Button("Focus Question") { target?.send(.focusQuestion) }
                .keyboardShortcut(.return)
                .disabled(target == nil)
            Button("Open Insight Tree") { target?.send(.openTree) }
                .keyboardShortcut("t")
                .disabled(target == nil)
            Button("Open Global Insight Tree") { target?.send(.openGlobalTree) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(target == nil)
            Divider()
            Button("Previous Page") { target?.send(.goBack) }
                .keyboardShortcut("r")
                .disabled(target?.canGoBack != true)
            Button("Next Page") { target?.send(.goForward) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(target?.canGoForward != true)
            Divider()
            Button("Swap Panes") { target?.send(.swapPanes) }
                .keyboardShortcut("s")
                .disabled(target == nil)
            Button("Pin / Unpin Panes") { target?.send(.pinPanes) }
                .keyboardShortcut("p")
                .disabled(target == nil)
            Divider()
            ForEach(1...9, id: \.self) { number in
                Button("Recent Conversation \(number)") { target?.send(.recentConversation(number)) }
                    .keyboardShortcut(KeyEquivalent(Character(String(number))))
                    .disabled(number > (target?.recentConversationIDs.count ?? 0))
            }
        }
        // Reserve Command-M for Model Tasks, retaining native window actions.
        CommandGroup(replacing: .windowSize) {
            Button("Model Tasks") { target?.send(.openQueue) }
                .keyboardShortcut("m")
                .disabled(target == nil)
            Divider()
            Button("Minimize") { NSApp.keyWindow?.miniaturize(nil) }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Button("Zoom") { NSApp.keyWindow?.performZoom(nil) }
        }
    }
}
