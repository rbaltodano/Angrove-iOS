import Testing
import llama
@testable import AngroveMac

struct MacBonsaiSamplerTests {
    @Test func recommendedPresencePenaltyExpiresAfterItsWindow() {
        let configuration = LlamaAngroveRuntime.SamplerConfiguration(
            sampling: .conversation, profile: .prismRecommended, thinking: false
        )
        let chain = LlamaAngroveRuntime.makeSampler(configuration, vocabularySize: 128, seed: 0)
        defer { llama_sampler_free(chain) }
        let penalty = llama_sampler_chain_get(chain, 0)
        // Exercise the adapter's actual native penalty stage independently of random sampling.
        func logit() -> Float {
            var candidates = [llama_token_data(id: 3, logit: 4, p: 0)]
            return candidates.withUnsafeMutableBufferPointer { buffer in
                var data = llama_token_data_array(data: buffer.baseAddress, size: buffer.count, selected: -1, sorted: false)
                llama_sampler_apply(penalty, &data)
                return buffer[0].logit
            }
        }
        #expect(logit() == 4)
        llama_sampler_accept(chain, 3)
        #expect(logit() == 2.5)
        // Presence is charged once, rather than once per occurrence (frequency penalty).
        llama_sampler_accept(chain, 3)
        #expect(logit() == 2.5)
        for _ in 0..<64 { llama_sampler_accept(chain, 4) }
        #expect(logit() == 4)
    }

    @Test func structuredCallsRemainGreedyUnderRecommendedProfile() {
        let configuration = LlamaAngroveRuntime.SamplerConfiguration(
            sampling: .structured, profile: .prismRecommended, thinking: false
        )
        let chain = LlamaAngroveRuntime.makeSampler(configuration, vocabularySize: 128, seed: 7)
        defer { llama_sampler_free(chain) }
        #expect(llama_sampler_chain_n(chain) == 1)
        var candidates = [llama_token_data(id: 3, logit: 4, p: 0), llama_token_data(id: 4, logit: 2, p: 0)]
        candidates.withUnsafeMutableBufferPointer { buffer in
            var data = llama_token_data_array(data: buffer.baseAddress, size: buffer.count, selected: -1, sorted: false)
            llama_sampler_apply(chain, &data)
            #expect(data.selected == 0)
        }
    }
}

struct MacBonsaiPromptTests {
    @Test func compactPromptPreservesEvidenceSummaryAndCorrectionWithinSmallerBudget() {
        let reference = AngroveGroundingReference(
            id: "fixture", title: "Exact source title", sourceName: "Fixture author",
            facts: "The complete passage must survive unchanged.", retrievalAliases: []
        )
        let context = ConversationContext(compactedContext: "The user distinguished faith from hope.")
        let correction = (author: "Fixture writer", subject: "Fixture work")
        let standard = LiteRTAngroveModel.evidenceExperimentInstruction(
            context: context, references: [reference], correction: correction
        )
        let compact = LiteRTAngroveModel.evidenceExperimentInstruction(
            context: context, references: [reference], style: .bonsaiCompact, correction: correction
        )
        #expect(compact.contains(reference.promptText))
        #expect(compact.contains(context.compactedContext!))
        #expect(compact.contains(correction.author) && compact.contains(correction.subject))
        #expect(compact.contains("Ternary Bonsai 2"))
        #expect(!compact.contains("You are Gemma 4"))
        #expect(compact.utf8.count < standard.utf8.count / 2)
    }

    @Test func exactAuthorityEvidenceRouteKeepsItsExistingInstruction() {
        let reference = AngroveGroundingReference(
            id: "authority-section-fixture", title: "Exact authority", sourceName: "Source",
            facts: "A precisely scoped primary-source passage.", retrievalAliases: []
        )
        let context = ConversationContext()
        let standard = LiteRTAngroveModel.evidenceExperimentInstruction(context: context, references: [reference])
        let compact = LiteRTAngroveModel.evidenceExperimentInstruction(
            context: context, references: [reference], style: .bonsaiCompact
        )
        #expect(compact == standard)
        #expect(compact.contains(reference.promptText))
    }
}
