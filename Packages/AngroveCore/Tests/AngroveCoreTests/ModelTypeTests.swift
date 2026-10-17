import Foundation
import Testing
@testable import AngroveCore

struct ModelTypeTests {
    @Test func stableIDsDependOnlyOnContent() {
        #expect(stableUUID(from: "a") == stableUUID(from: "a"))
        #expect(stableUUID(from: "a") != stableUUID(from: "b"))
        // A term keeps one Insight identity regardless of case or surrounding space.
        #expect(ConceptDefinition.stableID(forTerm: " Prudence ") == ConceptDefinition.stableID(forTerm: "prudence"))
    }

    @Test func conceptSurvivesEncoding() throws {
        let concept = ConceptDefinition(word: "Prudence", partOfSpeech: "noun", pronunciation: "",
                                        meaning: "Right reason applied to action.", example: "", context: "ethics")
        let decoded = try JSONDecoder().decode(ConceptDefinition.self, from: JSONEncoder().encode(concept))
        #expect(decoded == concept)
    }

    @Test func questionOfTheDayExpiresAndIsSpentByAnswering() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let question = HomeQuestionOfTheDay(question: "What makes a life meaningful?", generatedAt: start)
        #expect(question.isPending(at: start))
        #expect(!question.isPending(at: start.addingTimeInterval(25 * 60 * 60)))
        #expect(!question.markingAnswered(at: start).isPending(at: start))
    }

    @Test func hiddenPromptContextEscapesMarkup() {
        let question = HomeQuestionOfTheDay(question: "Is <truth> & beauty one?")
        #expect(question.taggedPromptContext.contains("Is &lt;truth&gt; &amp; beauty one?"))
        #expect(!question.taggedPromptContext.contains("<truth>"))
    }
}
