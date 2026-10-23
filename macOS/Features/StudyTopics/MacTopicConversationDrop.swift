import SwiftUI

/// Files conversations dragged from the sidebar or from search into a Study Topic.
private struct MacTopicConversationDrop: ViewModifier {
    let topicID: UUID
    let onFiled: () -> Void
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: AngroveTheme.Spacing.cardRadius, style: .continuous)
                    .strokeBorder(AngroveTheme.Colors.lightGreen.opacity(isTargeted ? 1 : 0), lineWidth: 1)
                    .animation(.easeOut(duration: 0.15), value: isTargeted)
                    .allowsHitTesting(false)
            }
            .dropDestination(for: String.self) { payloads, _ in
                MacTopicConversationDrop.file(payloads, into: topicID, onFiled: onFiled)
            } isTargeted: { isTargeted = $0 }
    }

    /// Assigns every dropped conversation to the topic. Other text is ignored.
    @discardableResult
    static func file(_ payloads: [String], into topicID: UUID, onFiled: () -> Void) -> Bool {
        let ids = payloads.compactMap(WorktreeConversationDrop.conversationID(in:))
        guard !ids.isEmpty, var snapshot = CurrentConversationsStore.load() else { return false }
        for id in ids {
            if let updated = MacSidebarConversationActions.applying(.assignTopic(topicID), to: id, in: snapshot) {
                snapshot = updated
            }
        }
        CurrentConversationsStore.save(snapshot)
        onFiled()
        return true
    }
}

extension View {
    func macTopicConversationDrop(topicID: UUID, onFiled: @escaping () -> Void) -> some View {
        modifier(MacTopicConversationDrop(topicID: topicID, onFiled: onFiled))
    }
}
