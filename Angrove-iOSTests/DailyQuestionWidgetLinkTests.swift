import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Question widget navigation")
struct DailyQuestionWidgetLinkTests {
    @Test("Only the question widget destination is handled")
    func supportedDestination() throws {
        #expect(DailyQuestionWidgetLink.matches(DailyQuestionWidgetLink.url))
        for address in ["https://question-of-the-day", "angrove://other", "angrove://question-of-the-day/other", "angrove://question-of-the-day?question=unexpected"] {
            #expect(!DailyQuestionWidgetLink.matches(try #require(URL(string: address))))
        }
    }

    @Test("An answered, expired question still opens its answer composer with original context")
    func savedQuestionRequest() {
        let question = HomeQuestionOfTheDay(
            question: "What follows from this distinction?",
            reasonForAsking: "Test the unresolved distinction.",
            generatedAt: .distantPast,
            expiresAt: .distantPast,
            answeredAt: .distantPast
        )
        #expect(!question.isPending())
        let request = question.conversationRequest
        #expect(request.question == question.question)
        #expect(request.eyebrow == "QUESTION OF THE DAY")
        #expect(request.promptContext == question.taggedPromptContext)
        #expect(request.promptContext.contains(question.reasonForAsking))
    }
}
