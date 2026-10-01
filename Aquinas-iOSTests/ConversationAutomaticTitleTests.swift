import Foundation
import Testing
@testable import Aquinas_iOS

@Suite("Automatic conversation titles")
@MainActor
struct ConversationAutomaticTitleTests {
    private func answeredConversation() -> InquiryConversation {
        var branch = ChatBranch(startingConcept: nil)
        branch.topQuestionText = "What is prudence?"
        branch.topQuestionSubmitted = true
        branch.activeChatBlocks = [.text("Prudence guides practical judgment.")]
        return InquiryConversation(branches: [branch])
    }

    @Test("Naming targets the original conversation and preserves a newer draft")
    func namingAfterNavigation() {
        let original = answeredConversation()
        let other = InquiryConversation()
        var snapshot = InquiryPersistenceSnapshot(conversations: [original, other], activeConversationID: other.id)
        let session = ConversationSession(loadSnapshot: { snapshot }, saveSnapshot: { snapshot = $0 })
        session.conversations = snapshot.conversations
        session.activate(other)
        session.activeBranches[0].topQuestionText = "A new draft"
        #expect(session.applyAutomaticTitle("Prudence and Practical Judgment", conversationID: original.id,
                                            branchID: original.branches[0].id, question: "What is prudence?"))
        #expect(snapshot.conversations[0].title == "Prudence and Practical Judgment")
        #expect(snapshot.conversations[0].branches[0].generatedBranchTitle == snapshot.conversations[0].title)
        #expect(snapshot.activeConversationID == other.id)
        #expect(session.activeBranches[0].topQuestionText == "A new draft")
        #expect(!session.applyAutomaticTitle("Another Title", conversationID: original.id,
                                             branchID: original.branches[0].id, question: "What is prudence?"))
    }

    @Test("A manual rename during generation wins")
    func manualRenameWins() {
        let original = answeredConversation()
        var snapshot = InquiryPersistenceSnapshot(conversations: [original], activeConversationID: original.id)
        let session = ConversationSession(loadSnapshot: { snapshot }, saveSnapshot: { snapshot = $0 })
        session.conversations = [original]
        session.activate(original)
        #expect(session.needsAutomaticTitle(conversationID: original.id, branchID: original.branches[0].id,
                                             question: "What is prudence?"))
        #expect(session.rename(to: "My Study"))
        session.persist()
        #expect(!session.applyAutomaticTitle("Practical Judgment", conversationID: original.id,
                                             branchID: original.branches[0].id, question: "What is prudence?"))
        #expect(snapshot.conversations[0].title == "My Study")
    }

    @Test("Deleted, cleared, pinned, and unanswered conversations cannot be renamed")
    func obsoleteRequestsAreDiscarded() {
        let original = answeredConversation()
        var snapshot = InquiryPersistenceSnapshot(conversations: [], activeConversationID: nil)
        let session = ConversationSession(loadSnapshot: { snapshot }, saveSnapshot: { snapshot = $0 })
        for variation in 0..<5 {
            var changed = original
            switch variation {
            case 0: changed.branches = [ChatBranch(startingConcept: nil)]
            case 1: changed.branches[0].pinnedHeaderQuestion = "A pinned prompt"
            case 2: changed.branches[0].activeChatBlocks = [.text("")]
            case 3: changed.branches[0].topQuestionText = "A different question"
            default: break
            }
            snapshot.conversations = variation == 4 ? [] : [changed]
            #expect(!session.applyAutomaticTitle("Practical Judgment", conversationID: original.id,
                                                 branchID: original.branches[0].id, question: "What is prudence?"))
        }
    }

    @Test("Malformed model titles are rejected")
    func titleValidation() throws {
        #expect(try ConversationTitleValidation.validate("  Practical Judgment  ") == "Practical Judgment")
        for value in ["", "New Conversation", "Title\nExplanation", String(repeating: "A", count: 49),
                      "One two three four five six"] {
            #expect(throws: AquinasModelActionError.self) { try ConversationTitleValidation.validate(value) }
        }
    }

    @Test("A stale snapshot cannot undo the completed title or newer composer draft")
    func staleSavePreservesTitle() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = InquirySnapshotFileStore(rootDirectory: directory, defaults: defaults)
        let original = answeredConversation()
        var stored = original
        stored.title = "Practical Judgment"
        stored.branches[0].generatedBranchTitle = stored.title
        try store.save(InquiryPersistenceSnapshot(conversations: [stored], activeConversationID: original.id))
        var stale = original
        stale.branches[0].bottomQuestionText = "What about justice?"
        try store.savePreservingCompletedResponses(
            InquiryPersistenceSnapshot(conversations: [stale], activeConversationID: original.id)
        )
        let restored = try #require(store.load()?.conversations.first)
        #expect(restored.title == "Practical Judgment")
        #expect(restored.branches[0].generatedBranchTitle == restored.title)
        #expect(restored.branches[0].bottomQuestionText == "What about justice?")
    }
}
