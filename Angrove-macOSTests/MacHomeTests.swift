import Foundation
import Testing
@testable import AngroveMac

@MainActor
struct MacHomeTests {
    private let empty = InquiryPersistenceSnapshot(conversations: [], activeConversationID: nil)

    @Test func homePromptsOpenASavedConversationWithHiddenContextAndPinnedHeader() throws {
        let card = TodayInHistoryCard(title: "The Council of Nicaea", description: "Bishops gathered in 325.")
        let request = NewConversationRequest(question: card.title, eyebrow: "TODAY IN HISTORY",
                                             promptContext: card.taggedPromptContext, subtitle: card.description)
        let snapshot = MacDailyPrompt.conversation(for: request, in: empty)
        let conversation = try #require(snapshot.conversations.first)
        let branch = try #require(conversation.branches.first)
        #expect(snapshot.activeConversationID == conversation.id)
        #expect(conversation.title == card.title)
        #expect(branch.pinnedHeaderQuestion == card.title)
        #expect(branch.hiddenPromptContext == request.promptContext)
        #expect(!branch.topQuestionSubmitted)
    }

    @Test func reopeningTheSameCardReusesItsUntouchedConversation() throws {
        let request = HomeQuestionOfTheDay(question: "What makes a question worth returning to?").conversationRequest
        let first = MacDailyPrompt.conversation(for: request, in: empty)
        let second = MacDailyPrompt.conversation(for: request, in: first)
        #expect(second.conversations.count == 1)
        #expect(second.activeConversationID == first.activeConversationID)

        // Once the person has asked something, the card starts a fresh conversation instead.
        var asked = second
        asked.conversations[0].branches[0].topQuestionText = "Because it changes me."
        asked.conversations[0].branches[0].topQuestionSubmitted = true
        let third = MacDailyPrompt.conversation(for: request, in: asked)
        #expect(third.conversations.count == 2)
        #expect(third.activeConversationID != first.activeConversationID)
    }

    @Test func homeShortcutTargetsHome() {
        var request: MacShortcutRequest?
        let target = MacWorkspaceCommandTarget(request: .init(get: { request }, set: { request = $0 }), recentConversationIDs: [])
        target.send(.openHome)
        #expect(request?.action == .openHome)
    }

    @Test func libraryIsASidebarDestinationBetweenConversationsAndTopics() {
        let destinations = MacDestination.sidebarDestinations
        let library = try? #require(destinations.firstIndex(of: .library))
        #expect(library == (destinations.firstIndex(of: .conversations) ?? 0) + 1)
        #expect(destinations.firstIndex(of: .studyTopics) == (library ?? 0) + 1)
    }
}
