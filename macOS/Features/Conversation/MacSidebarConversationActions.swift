import Foundation

enum MacSidebarConversationMutation {
    case rename(String)
    case setPinned(Bool)
    case assignTopic(UUID?)
}

enum MacSidebarConversationActions {
    static func sorted(_ conversations: [InquiryConversation]) -> [InquiryConversation] {
        let recent = conversations.filter { !$0.isStudyTopic }.reversed()
        return recent.filter(\.isPinned) + recent.filter { !$0.isPinned }
    }

    static func applying(_ action: MacSidebarConversationMutation, to id: UUID,
                         in snapshot: InquiryPersistenceSnapshot) -> InquiryPersistenceSnapshot? {
        var updated = snapshot
        guard let index = updated.conversations.firstIndex(where: { $0.id == id }) else { return nil }
        switch action {
        case .rename(let value):
            let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            updated.conversations[index].title = title
        case .setPinned(let pinned): updated.conversations[index].isPinned = pinned
        case .assignTopic(let id): updated.conversations[index].studyTopicID = id
        }
        return updated
    }

    /// Conversations leave a deleted Study Topic for Recents; nil when none were filed under it.
    static func unfiling(topic topicID: UUID, in snapshot: InquiryPersistenceSnapshot) -> InquiryPersistenceSnapshot? {
        guard snapshot.conversations.contains(where: { $0.studyTopicID == topicID }) else { return nil }
        var updated = snapshot
        for index in updated.conversations.indices where updated.conversations[index].studyTopicID == topicID {
            updated.conversations[index].studyTopicID = nil
        }
        return updated
    }

    static func deleting(_ id: UUID, in snapshot: InquiryPersistenceSnapshot) -> InquiryPersistenceSnapshot {
        var updated = snapshot
        updated.conversations.removeAll { $0.id == id }
        if updated.activeConversationID == id {
            updated.activeConversationID = sorted(updated.conversations).first?.id
        }
        return updated
    }
}
