import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Live model action availability")
struct ModelActionAvailabilityTests {
    private func model() -> UnavailableAngroveModel {
        UnavailableAngroveModel()
    }

    private var context: ConversationContext {
        ConversationContext(
            transcript: [.user("What is prudence?", nil, [])]
        )
    }

    private var concept: ConceptDefinition {
        ConceptDefinition(
            word: "Prudence",
            partOfSpeech: "",
            pronunciation: "",
            meaning: "Practical wisdom applied to action.",
            example: ""
        )
    }

    @Test("Responses explain the missing model instead of inventing an answer")
    func responseFailsExplicitly() async {
        let response = await model().respond(to: context)
        #expect(response.text == UnavailableAngroveModel.unavailableMessage)
        #expect(response.keyTerms.isEmpty)
    }

    @Test("Definitions fail instead of returning a mock Insight")
    func definitionFailsExplicitly() async {
        do {
            _ = try await model().defineTerm("prudence", in: context)
            Issue.record("Expected the unavailable model to throw.")
        } catch {
            #expect(error is AngroveModelActionError)
        }
    }

    @Test("Tree-generating actions fail instead of returning template content")
    func treeActionsFailExplicitly() async {
        do {
            _ = try await model().labelSubject(
                forTitles: ["Prudence: Practical wisdom applied to action."]
            )
            Issue.record("Expected Node labeling to throw.")
        } catch {
            #expect(error is AngroveModelActionError)
        }

        do {
            _ = try await model().blendConceptCandidates(
                [concept, concept],
                weights: [0.5, 0.5]
            )
            Issue.record("Expected Midpoint generation to throw.")
        } catch {
            #expect(error is AngroveModelActionError)
        }

        do {
            _ = try await model().generateChildren(for: concept)
            Issue.record("Expected Make Node generation to throw.")
        } catch {
            #expect(error is AngroveModelActionError)
        }
    }

    @Test("Question of the Day fails instead of returning a mock question")
    func dailyQuestionFailsExplicitly() async {
        do {
            _ = try await model().generateQuestionOfTheDay(
                from: context,
                conversationTitle: "Practical Wisdom",
                insights: [concept]
            )
            Issue.record("Expected Question of the Day generation to throw.")
        } catch {
            #expect(error is AngroveModelActionError)
        }
    }
}
