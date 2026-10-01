import Foundation
import Observation
import SwiftUI

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

    /// Resolve by captured IDs, then recheck after generation so a rename, clear, or deletion wins.
    func needsAutomaticTitle(conversationID: UUID, branchID: UUID, question: String) -> Bool {
        guard let conversation = loadSnapshot()?.conversations.first(where: { $0.id == conversationID }),
              conversation.title == "New Conversation",
              let branch = conversation.branches.first(where: { $0.id == branchID }),
              case .text(let answer) = branch.activeChatBlocks.first,
              !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return branch.parentBranchID == nil && branch.pinnedHeaderQuestion == nil
            && branch.generatedBranchTitle == nil && branch.topQuestionSubmitted
            && branch.topQuestionText == question
    }

    @discardableResult
    func applyAutomaticTitle(_ title: String, conversationID: UUID, branchID: UUID, question: String) -> Bool {
        guard let title = try? ConversationTitleValidation.validate(title),
              needsAutomaticTitle(conversationID: conversationID, branchID: branchID, question: question),
              var snapshot = loadSnapshot(),
              let index = snapshot.conversations.firstIndex(where: { $0.id == conversationID }),
              let branchIndex = snapshot.conversations[index].branches.firstIndex(where: { $0.id == branchID })
        else { return false }
        snapshot.conversations[index].title = title
        snapshot.conversations[index].branches[branchIndex].generatedBranchTitle = title
        saveSnapshot(snapshot)
        if let index = conversations.firstIndex(where: { $0.id == conversationID }) {
            conversations[index].title = title
            if let branchIndex = conversations[index].branches.firstIndex(where: { $0.id == branchID }) {
                conversations[index].branches[branchIndex].generatedBranchTitle = title
            }
        }
        if activeConversationID == conversationID,
           let index = activeBranches.firstIndex(where: { $0.id == branchID }) {
            activeBranches[index].generatedBranchTitle = title
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

    /// A removed page can still receive editor-blur or response-reveal callbacks. Resolve
    /// its branch by identity, never by the array position now occupied by another page.
    func binding(for branch: ChatBranch) -> Binding<ChatBranch> {
        let conversationID = activeConversationID
        let branchID = branch.id
        return Binding(
            get: {
                guard self.activeConversationID == conversationID else { return branch }
                return self.activeBranches.first(where: { $0.id == branchID }) ?? branch
            },
            set: { updated in
                guard self.activeConversationID == conversationID,
                      updated.id == branchID,
                      let index = self.activeBranches.firstIndex(where: { $0.id == branchID })
                else { return }
                self.activeBranches[index] = updated
            }
        )
    }
}

nonisolated enum ConversationTitleValidation {
    static func validate(_ raw: String) throws -> String {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 48,
              title.split(whereSeparator: \.isWhitespace).count <= 5,
              !title.contains("\n"), !title.contains("\r"),
              title.lowercased() != "new conversation" else {
            throw AngroveModelActionError.invalidResponse
        }
        return title
    }
}
