import Foundation
import SwiftUI
import Testing
@testable import Angrove_iOS

@MainActor
@Suite("Conversation handoff and session")
struct ConversationCleanupTests {
    @Test("Late reveal and editor callbacks cannot copy an answered thread into a new conversation")
    func stalePageBindingCannotOverwriteNewConversation() {
        var originBranch = ChatBranch(startingConcept: nil)
        originBranch.topQuestionText = "What is prudence?"
        originBranch.topQuestionSubmitted = true
        originBranch.activeChatBlocks = [.text("")]
        let origin = InquiryConversation(branches: [originBranch])
        var saved: InquiryPersistenceSnapshot?
        let session = ConversationSession(loadSnapshot: { nil }, saveSnapshot: { saved = $0 })
        session.conversations = [origin]
        session.activate(origin)
        let oldPage = session.binding(for: originBranch)

        // The page was constructed with a placeholder; generation finishes before navigation.
        oldPage.wrappedValue.activeChatBlocks[0] = .text("Completed answer")
        session.saveActiveConversation(promotedInsightIDs: [])
        let freshBranch = ChatBranch(startingConcept: nil)
        let fresh = InquiryConversation(branches: [freshBranch])
        session.conversations.insert(fresh, at: 0)
        session.activate(fresh)

        // The removed renderer finishes its animation and UIKit flushes the old editor.
        oldPage.wrappedValue.showBottomInput = true
        oldPage.wrappedValue.bottomQuestionText = "Old follow-up draft"
        session.saveActiveConversation(promotedInsightIDs: [])
        session.persist()

        #expect(session.activeBranches == [freshBranch])
        #expect(saved?.conversations.first?.branches == [freshBranch])
        #expect(saved?.conversations.last?.branches[0].activeChatBlocks == [.text("Completed answer")])
    }

    @Test("Branch bindings follow identity through reorder and ignore removed branches")
    func branchBindingFollowsIdentity() {
        let root = ChatBranch(startingConcept: nil)
        let fork = ChatBranch(startingConcept: nil, parentBranchID: root.id)
        let conversation = InquiryConversation(branches: [root, fork])
        let session = ConversationSession(loadSnapshot: { nil }, saveSnapshot: { _ in })
        session.activate(conversation)
        let rootPage = session.binding(for: root)
        session.activeBranches.reverse()
        rootPage.wrappedValue.topQuestionText = "Root draft"
        #expect(session.activeBranches[0] == fork)
        #expect(session.activeBranches[1].topQuestionText == "Root draft")
        #expect(rootPage.wrappedValue.topQuestionText == "Root draft")

        session.activeBranches.removeAll { $0.id == root.id }
        rootPage.wrappedValue.showBottomInput = true
        #expect(session.activeBranches == [fork])
    }

    @Test("A request consumed by one page is not replayed when that page is recreated")
    func consumedRequestSurvivesRemount() throws {
        let shellRequests = NewConversationRequests()
        let topicID = UUID()
        let request = NewConversationRequest(
            question: "  What is prudence? \n", eyebrow: "QUESTION OF THE DAY",
            promptContext: "<question of the day>", topicID: topicID
        )
        shellRequests.submit(request)
        let firstPageRequest = try #require(shellRequests.takePending())
        #expect(firstPageRequest.id == request.id)
        #expect(firstPageRequest.question == "What is prudence?")
        #expect(firstPageRequest.topicID == topicID)
        #expect(shellRequests.takePending() == nil)

        // An identical question is still a distinct intentional navigation action.
        shellRequests.submit(NewConversationRequest(question: request.question))
        let nextPageRequest = try #require(shellRequests.takePending())
        #expect(nextPageRequest.id != request.id)
        #expect(nextPageRequest.eyebrow.isEmpty)
        #expect(nextPageRequest.promptContext.isEmpty)
        #expect(nextPageRequest.topicID == nil)
    }

    @Test("Several requests while unmounted select the latest complete destination")
    func latestRequestKeepsItsOwnMetadata() throws {
        let requests = NewConversationRequests()
        requests.submit(NewConversationRequest(
            question: "Daily question", eyebrow: "QUESTION OF THE DAY",
            promptContext: "hidden context", subtitle: "Daily description", topicID: UUID()
        ))
        requests.submit()
        let pending = try #require(requests.takePending())
        #expect(pending.question.isEmpty)
        #expect(pending.eyebrow.isEmpty)
        #expect(pending.promptContext.isEmpty)
        #expect(pending.subtitle.isEmpty)
        #expect(pending.topicID == nil)
        #expect(pending.quote == nil)
    }

    @Test("A completed response refresh preserves composer edits and other branches")
    func completionPreservesDraft() throws {
        var stored = ChatBranch(startingConcept: nil)
        stored.activeChatBlocks = [.user("Question", nil, []), .text("Answer")]
        stored.setResponsePresentation(ResponsePresentationMetadata(
            responseIndex: 1, showsThinking: true, thinkingSummary: ["Compare the sources"]
        ))
        let conversation = InquiryConversation(branches: [stored])
        let snapshot = InquiryPersistenceSnapshot(
            conversations: [conversation], activeConversationID: conversation.id
        )
        let session = ConversationSession(loadSnapshot: { snapshot }, saveSnapshot: { _ in })
        session.conversations = [conversation]
        session.activate(conversation)
        session.activeBranches[0].activeChatBlocks[1] = .text("")
        session.activeBranches[0].topQuestionText = "Edited top draft"
        session.activeBranches[0].bottomQuestionText = "Follow-up draft"
        let other = ChatBranch(startingConcept: nil, parentBranchID: stored.id)
        session.activeBranches.append(other)

        #expect(session.refreshPersistedResponse(
            conversationID: conversation.id, branchID: stored.id, responseIndex: 1
        ))
        #expect(session.activeBranches[0].activeChatBlocks[1] == .text("Answer"))
        #expect(session.activeBranches[0].topQuestionText == "Edited top draft")
        #expect(session.activeBranches[0].bottomQuestionText == "Follow-up draft")
        #expect(session.activeBranches[0].responsePresentation(at: 1)?.thinkingSummary == ["Compare the sources"])
        #expect(session.activeBranches[0].showBottomInput)
        #expect(session.activeBranches[1] == other)
    }

    @Test("A completion after navigation updates its conversation without replacing the displayed one")
    func completionStaysWithOrigin() throws {
        var originBranch = ChatBranch(startingConcept: nil)
        originBranch.activeChatBlocks = [.user("Original question", nil, []), .text("Answer")]
        let origin = InquiryConversation(branches: [originBranch])
        var displayedBranch = ChatBranch(startingConcept: nil)
        displayedBranch.topQuestionText = "New draft"
        let displayed = InquiryConversation(branches: [displayedBranch])
        let snapshot = InquiryPersistenceSnapshot(
            conversations: [origin, displayed], activeConversationID: displayed.id
        )
        let session = ConversationSession(loadSnapshot: { snapshot }, saveSnapshot: { _ in })
        session.conversations = [origin, displayed]
        session.conversations[0].branches[0].activeChatBlocks[1] = .text("")
        session.activate(displayed)

        #expect(session.refreshPersistedResponse(
            conversationID: origin.id, branchID: originBranch.id, responseIndex: 1
        ))
        #expect(session.activeConversationID == displayed.id)
        #expect(session.activeBranches == [displayedBranch])
        #expect(session.conversations[0].branches[0].activeChatBlocks[1] == .text("Answer"))
    }

    @Test("A late completion cannot restore a response slot cleared from the session")
    func clearedSlotStaysCleared() {
        var branch = ChatBranch(startingConcept: nil)
        branch.activeChatBlocks = [.user("Question", nil, []), .text("Late answer")]
        let original = InquiryConversation(branches: [branch])
        let snapshot = InquiryPersistenceSnapshot(conversations: [original], activeConversationID: original.id)
        var cleared = original
        cleared.branches[0].activeChatBlocks = []
        let session = ConversationSession(loadSnapshot: { snapshot }, saveSnapshot: { _ in })
        session.conversations = [cleared]
        session.activate(cleared)

        _ = session.refreshPersistedResponse(
            conversationID: original.id, branchID: branch.id, responseIndex: 1
        )
        #expect(session.activeBranches[0].activeChatBlocks.isEmpty)
        #expect(session.conversations[0].branches[0].activeChatBlocks.isEmpty)
    }

    @Test("A chosen title and promoted Insights survive saving the active session")
    func chosenTitleSurvivesSave() throws {
        let conversation = InquiryConversation()
        var saved: InquiryPersistenceSnapshot?
        let session = ConversationSession(loadSnapshot: { nil }, saveSnapshot: { saved = $0 })
        session.conversations = [conversation]
        session.activate(conversation)
        #expect(session.rename(to: "  My title \n"))
        #expect(!session.rename(to: " \n"))
        let insightID = UUID()
        session.saveActiveConversation(promotedInsightIDs: [insightID])
        session.persist()

        let snapshot = try #require(saved)
        #expect(snapshot.activeConversationID == conversation.id)
        #expect(snapshot.conversations[0].title == "My title")
        #expect(snapshot.conversations[0].branches[0].generatedBranchTitle == "My title")
        #expect(snapshot.conversations[0].promotedInsightIDs == [insightID])
    }
}
