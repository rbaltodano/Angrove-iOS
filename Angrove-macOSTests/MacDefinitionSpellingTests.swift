import Foundation
import LiteRTLM
import Testing
@testable import AngroveMac

struct MacDefinitionSpellingTests {
    @Test func falseRejectionOfChurchRetriesTheRealDefinitionPath() async throws {
        let runtime = DefinitionSequenceRuntime(responses: ["<unrecognized_term/>", "A church is a community of Christians or a building used for Christian worship."])
        let model = LiteRTAngroveModel(runtime: runtime, groundingProvider: DefinitionNoGrounding())
        let result = try await model.defineTerm("church", in: ConversationContext(transcript: []))
        #expect(result.word == "church")
        #expect(result.meaning.contains("Christian worship"))
        let calls = await runtime.calls
        #expect(calls == 2)
    }

    @Test func validDefinitionsDoNotRetryAndRepeatedRejectionsStopAfterTwoCalls() async throws {
        let good = DefinitionSequenceRuntime(responses: ["A freely given gift."])
        let model = LiteRTAngroveModel(runtime: good, groundingProvider: DefinitionNoGrounding())
        _ = try await model.defineTerm("grace", in: ConversationContext(transcript: []))
        let goodCalls = await good.calls
        #expect(goodCalls == 1)
        let bad = DefinitionSequenceRuntime(responses: ["<unrecognized_term/>", "<unrecognized_term/>"])
        let failing = LiteRTAngroveModel(runtime: bad, groundingProvider: DefinitionNoGrounding())
        do {
            _ = try await failing.defineTerm("qzxwvv", in: ConversationContext(transcript: []))
            Issue.record("Expected an unrecognized-term failure")
        } catch is LiteRTAngroveModel.DefinitionTermError {} 
        let badCalls = await bad.calls
        #expect(badCalls == 2)
    }

    @Test func correctedSpellingBecomesTheInsightTitleAndCanonicalIdentity() throws {
        let result = try LiteRTAngroveModel.contextualDefinition(
            from: "<corrected_term>hypostasis</corrected_term>\nAn individual subsisting reality.", requestedTerm: "hypostais")
        #expect(result.word == "hypostasis")
        #expect(result.id == ConceptDefinition.stableID(forTerm: "hypostasis"))
        #expect(result.meaning == "An individual subsisting reality.")
    }

    @Test func specialistTermsAndExistingProseRemainCompatible() throws {
        let result = try LiteRTAngroveModel.contextualDefinition(from: "An individual subsisting reality.", requestedTerm: "hypostasis")
        #expect(result.word == "hypostasis")
        #expect(result.meaning == "An individual subsisting reality.")
    }

    @Test func unresolvableWordsRequestClarificationInsteadOfCreatingAnInsight() {
        #expect(throws: LiteRTAngroveModel.DefinitionTermError.self) {
            try LiteRTAngroveModel.contextualDefinition(from: "<unrecognized_term/>", requestedTerm: "qzxwvv")
        }
    }

    @Test func malformedCorrectionMetadataCannotLeakIntoACard() {
        for response in ["<corrected_term>grace", "<corrected_term></corrected_term>Meaning",
                         "<corrected_term>grace</corrected_term>", "<corrected_term>bad\nterm</corrected_term>Meaning"] {
            #expect(throws: (any Error).self) {
                try LiteRTAngroveModel.contextualDefinition(from: response, requestedTerm: "graec")
            }
        }
    }
}


private actor DefinitionSequenceRuntime: AngroveTextRuntime {
    nonisolated let supportsUnloading = false
    var responses: [String]
    var calls = 0
    init(responses: [String]) { self.responses = responses }
    func loadModelWeights() async throws {}
    func unloadModelWeights() async {}
    func generate(systemInstruction: String, initialMessages: [Message], message: Message, sampling: LiteRTSampling,
                  onText: (@Sendable (String) async -> Void)?, onThought: (@Sendable (String) async -> Void)?) async throws -> String {
        calls += 1
        guard !responses.isEmpty else { throw AngroveModelActionError.invalidResponse }
        return responses.removeFirst()
    }
}

nonisolated private struct DefinitionNoGrounding: AngroveGroundingProviding {
    func references(for question: String, limit: Int) -> [AngroveGroundingReference] { [] }
}
