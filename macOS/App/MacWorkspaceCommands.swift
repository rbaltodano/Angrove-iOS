import AppKit
import SwiftUI

struct MacShortcutRequest: Equatable {
    enum Action: Equatable {
        case newBoard, newStudyTopic
        case newConversation, focusQuestion, openTree, swapPanes, pinPanes, openQueue
        case openGlobalTree, goBack, goForward, toggleContext, openSettings, openHome, search
        /// Sends the composer's text once the conversation opens (search's New Conversation).
        case submitQuestion
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
    var destination: MacDestination = .home

    var newItemAction: MacShortcutRequest.Action {
        switch destination {
        case .worktree: .newBoard
        case .studyTopics: .newStudyTopic
        default: .newConversation
        }
    }
    var newItemTitle: String {
        switch destination {
        case .worktree: String(localized: "New Board")
        case .studyTopics: String(localized: "New Study Topic")
        default: String(localized: "New Conversation")
        }
    }

    var canToggleConversationTree: Bool { destination == .conversations }

    func send(_ action: MacShortcutRequest.Action) {
        guard action != .openTree || canToggleConversationTree else { return }
        request.wrappedValue = MacShortcutRequest(action: action)
    }

    static func recentIDs(in conversations: [InquiryConversation]) -> [UUID] {
        Array(MacSidebarConversationActions.sorted(conversations).prefix(9).map(\.id))
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
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { target?.send(.openSettings) }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(target == nil)
        }
        CommandGroup(replacing: .newItem) {
            Button(target?.newItemTitle ?? String(localized: "New Conversation")) {
                if let target { target.send(target.newItemAction) }
            }
                .keyboardShortcut("n")
                .disabled(target == nil)
            Button("Search…") { target?.send(.search) }
                .keyboardShortcut("k")
                .disabled(target == nil)
        }
        CommandMenu("Conversation") {
            Button("Focus Question") { target?.send(.focusQuestion) }
                .keyboardShortcut(.return)
                .disabled(target == nil)
            Button("Conversation Context") { target?.send(.toggleContext) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(target == nil)
            Button("Toggle Insight Tree") { target?.send(.openTree) }
                .keyboardShortcut("t")
                .disabled(target?.canToggleConversationTree != true)
            Button("Toggle Global Insight Tree") { target?.send(.openGlobalTree) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(target == nil)
            Divider()
            Button("Home") { target?.send(.openHome) }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(target == nil)
            // Command-R is the Worktree's Rename for now; Previous Page has no shortcut until it gets a new one.
            Button("Previous Page") { target?.send(.goBack) }
                .disabled(target?.canGoBack != true)
            Button("Next Page") { target?.send(.goForward) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(target?.canGoForward != true)
            Divider()
            Button("Swap Panes") { target?.send(.swapPanes) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
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
