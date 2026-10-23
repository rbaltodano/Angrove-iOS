import SwiftUI

/// The content a completed definition opens, even after its original conversation unmounts.
struct MacCompletedDefinition: Identifiable, Equatable {
    let id = UUID()
    let conversationID: UUID
    let branchID: UUID
    let concept: ConceptDefinition
}

extension Notification.Name {
    static let macOpenCompletedDefinition = Notification.Name("angrove.mac.open-completed-definition")
}

@MainActor
enum MacCompletionNotifications {
    static func isViewing(_ id: UUID, destination: MacDestination,
                          conversationID: UUID, board: WorktreeBoard?) -> Bool {
        switch destination {
        case .conversations: conversationID == id
        case .worktree: board?.items.contains { $0.session?.id == id } == true
        default: false
        }
    }

    static func postQuestion(
        _ task: ModelTaskSnapshot,
        to center: ModelCompletionNotificationCenter,
        isViewing: (UUID) -> Bool,
        isAppActive: Bool,
        conversation: InquiryConversation?,
        onOpen: @escaping @MainActor (UUID, UUID) -> Void
    ) {
        guard case .userQuestion(let branchID, let responseIndex) = task.kind,
              responseIndex >= 0, let conversationID = task.conversationID,
              !(isAppActive && isViewing(conversationID)) else { return }
        let branch = conversation?.branches.first { $0.id == branchID }
        if let branch, branch.activeChatBlocks.indices.contains(responseIndex),
           case .text(let response) = branch.activeChatBlocks[responseIndex],
           response == questionCanceledResponseText { return }
        let question = branch.flatMap { branch in
            branch.activeChatBlocks.prefix(min(responseIndex, branch.activeChatBlocks.count))
                .reversed().compactMap { block -> String? in
                    guard case .user(let text, _, _) = block else { return nil }
                    return nonEmpty(text)
                }.first ?? nonEmpty(branch.topQuestionText)
        }
        // MacNotifications retains the existing system banner's conversation routing.
        center.post(title: question ?? nonEmpty(conversation?.title ?? "") ?? "Answer ready",
                    postsSystemNotification: false) { onOpen(conversationID, branchID) }
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
