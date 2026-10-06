import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Question of the Day lifecycle")
struct HomeQuestionOfTheDayTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test("Answering hides the question and permits refresh the next calendar day")
    func answeredQuestionRefreshesNextDay() throws {
        let generatedAt = try #require(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 30,
                hour: 10
            ))
        )
        let answeredAt = generatedAt.addingTimeInterval(60 * 60)
        let question = HomeQuestionOfTheDay(
            question: "What follows?",
            generatedAt: generatedAt,
            answeredAt: answeredAt
        )
        let nextDay = try #require(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 31
            ))
        )

        #expect(!question.isPending(at: answeredAt))
        #expect(
            question.nextEligibleRefreshDate(calendar: calendar) == nextDay
        )
    }

    @Test("An unanswered question remains pending until its expiration")
    func unansweredQuestionWaitsForExpiration() {
        let generatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let expiration = generatedAt.addingTimeInterval(24 * 60 * 60)
        let question = HomeQuestionOfTheDay(
            question: "What follows?",
            generatedAt: generatedAt,
            expiresAt: expiration
        )

        #expect(question.isPending(at: expiration.addingTimeInterval(-1)))
        #expect(!question.isPending(at: expiration))
        #expect(
            question.nextEligibleRefreshDate(calendar: calendar) >= expiration
        )
    }

    @Test("An invalid cached value is hidden and can be replaced immediately")
    func invalidCachedValueIsImmediatelyEligibleForReplacement() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let question = HomeQuestionOfTheDay(
            question: "Failed to load",
            generatedAt: now,
            expiresAt: now.addingTimeInterval(24 * 60 * 60)
        )

        #expect(!question.isPending(at: now))
        #expect(question.nextEligibleRefreshDate(calendar: calendar) == .distantPast)
    }

    @Test("A generated one-line question is accepted without a JSON wrapper")
    func generatedPlainQuestionIsAccepted() {
        #expect(
            LiteRTAngroveModel.questionOfTheDayQuestion(
                from: "Question: What practical step would test this conclusion?"
            ) == "What practical step would test this conclusion?"
        )
        #expect(
            LiteRTAngroveModel.questionOfTheDayQuestion(
                from: "How might this distinction change the conclusion"
            ) == "How might this distinction change the conclusion?"
        )
        #expect(
            LiteRTAngroveModel.questionOfTheDayQuestion(
                from: "Here is an explanation without a question."
            ) == nil
        )
    }
}

@Suite("Question of the Day conversation selection")
@MainActor
struct DailyQuestionSourceSelectorTests {
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64 = 42

        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    private func conversation(_ index: Int, answered: Bool = true) -> InquiryConversation {
        var branch = ChatBranch(startingConcept: nil)
        branch.topQuestionText = "What follows from idea \(index)?"
        branch.topQuestionSubmitted = true
        if answered {
            branch.activeChatBlocks = [.text(String(repeating: "A substantive answer. ", count: 8))]
        }
        return InquiryConversation(
            title: "Conversation \(index)",
            branches: [branch],
            createdAt: Date(timeIntervalSince1970: Double(index))
        )
    }

    @Test("Random selection reaches all five newest conversations and excludes older ones")
    func randomlySelectsWithinRecentWindow() throws {
        let conversations = (0..<8).map { conversation($0) }
        let expectedIDs = Set(conversations.suffix(5).map(\.id))
        var generator = SeededGenerator()
        var selectedIDs = Set<UUID>()
        for _ in 0..<100 {
            let source = try #require(DailyQuestionSourceSelector.select(
                conversations: conversations,
                savedInsights: [],
                using: &generator
            ))
            #expect(expectedIDs.contains(source.conversation.id))
            #expect(source.context.transcript.count == 2)
            selectedIDs.insert(source.conversation.id)
        }
        #expect(selectedIDs == expectedIDs)
    }

    @Test("Fewer than five conversations use the available eligible sources")
    func smallHistory() throws {
        let answered = conversation(0)
        let unanswered = conversation(1, answered: false)
        var generator = SeededGenerator()
        let source = try #require(DailyQuestionSourceSelector.select(
            conversations: [unanswered, answered], savedInsights: [], using: &generator
        ))
        #expect(source.conversation.id == answered.id)
        #expect(DailyQuestionSourceSelector.select(conversations: [], savedInsights: []) == nil)
    }

    @Test("Unanswered recent conversations never fall back to a sixth conversation")
    func doesNotReachBeyondFive() {
        let older = conversation(0)
        let recent = (1...5).map { conversation($0, answered: false) }
        #expect(DailyQuestionSourceSelector.select(
            conversations: [older] + recent, savedInsights: []
        ) == nil)
    }

    @Test("Study Topic containers do not consume the recent conversation window")
    func excludesStudyTopics() throws {
        let answered = conversation(0)
        let unanswered = (1...4).map { conversation($0, answered: false) }
        var topic = conversation(5)
        topic.isStudyTopic = true
        let source = try #require(DailyQuestionSourceSelector.select(
            conversations: [topic] + unanswered + [answered], savedInsights: []
        ))
        #expect(source.conversation.id == answered.id)
    }
}
