import Foundation
import Observation

/// Conversation data operations, independent of presentation and shell-owned model jobs.
/// Navigation changes the displayed session; it never cancels the shared task queue.
@MainActor
@Observable
final class ConversationSession {
    var conversations: [InquiryConversation] = []
    var activeConversationID: UUID?
    var activeBranches: [ChatBranch] = [ChatBranch(startingConcept: nil)]
    var focusedBranchID: UUID?

    @ObservationIgnored private let loadSnapshot: @MainActor () -> InquiryPersistenceSnapshot?
    @ObservationIgnored private let saveSnapshot: @MainActor (InquiryPersistenceSnapshot) -> Void

    init(
        loadSnapshot: @escaping @MainActor () -> InquiryPersistenceSnapshot? = CurrentConversationsStore.load,
        saveSnapshot: @escaping @MainActor (InquiryPersistenceSnapshot) -> Void = CurrentConversationsStore.save
    ) {
        self.loadSnapshot = loadSnapshot
        self.saveSnapshot = saveSnapshot
    }

    func saveActiveConversation(promotedInsightIDs: [UUID]) {
        guard let id = activeConversationID,
              let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[idx].branches = activeBranches
        conversations[idx].promotedInsightIDs = promotedInsightIDs
    }

    func rename(to title: String) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty,
              let index = conversations.firstIndex(where: { $0.id == activeConversationID }) else {
            return false
        }
        conversations[index].title = trimmedTitle
        // A title chosen before the first question should survive automatic title generation.
        if let rootIndex = activeBranches.firstIndex(where: { $0.parentBranchID == nil }) {
            activeBranches[rootIndex].generatedBranchTitle = trimmedTitle
            conversations[index].branches = activeBranches
        }
        return true
    }

    func refreshPersistedResponse(
        conversationID: UUID,
        branchID: UUID,
        responseIndex: Int
    ) -> Bool {
        guard let stored = loadSnapshot()?.conversations
            .first(where: { $0.id == conversationID })?.branches
            .first(where: { $0.id == branchID }),
              stored.activeChatBlocks.indices.contains(responseIndex) else { return false }

        // Copy only the completed slot, preserving any draft typed since the saved snapshot.
        func apply(to branch: inout ChatBranch) {
            guard branch.activeChatBlocks.indices.contains(responseIndex) else { return }
            branch.activeChatBlocks[responseIndex] = stored.activeChatBlocks[responseIndex]
            if let presentation = stored.responsePresentation(at: responseIndex) {
                branch.setResponsePresentation(presentation)
            }
            if responseIndex == branch.activeChatBlocks.count - 1 {
                branch.showBottomInput = true
            }
        }
        if let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
           let branchIndex = conversations[conversationIndex].branches.firstIndex(where: { $0.id == branchID }) {
            apply(to: &conversations[conversationIndex].branches[branchIndex])
        }
        if activeConversationID == conversationID,
           let branchIndex = activeBranches.firstIndex(where: { $0.id == branchID }) {
            apply(to: &activeBranches[branchIndex])
        }
        return true
    }

    func persist() {
        saveSnapshot(
            InquiryPersistenceSnapshot(conversations: conversations, activeConversationID: activeConversationID)
        )
    }

    func activate(_ conversation: InquiryConversation) {
        activeConversationID = conversation.id
        activeBranches = conversation.branches.isEmpty
            ? [ChatBranch(startingConcept: nil)]
            : conversation.branches
        focusedBranchID = activeBranches.first?.id
    }
}
