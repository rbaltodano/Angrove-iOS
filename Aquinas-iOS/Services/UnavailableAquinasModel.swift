//
//  UnavailableAquinasModel.swift
//  Aquinas-iOS
//

import Foundation

/// The live model boundary when no verified on-device model is installed. Every generative action
/// fails explicitly rather than inventing content; `MockAquinasModel` stays preview/test-only.
struct UnavailableAquinasModel: AquinasModel {
    static let unavailableMessage =
        "Aquinas's on-device model isn't installed, so it can't answer yet."

    func respond(to context: ConversationContext) async -> ModelResponse {
        ModelResponse(text: Self.unavailableMessage)
    }

    func compact(_ context: ConversationContext) async -> String {
        context.compactedContext ?? ""
    }

    func defineTerm(
        _ term: String,
        in context: ConversationContext
    ) async throws -> ConceptDefinition {
        throw AquinasModelActionError.unavailable
    }

    func labelSubject(forTitles titles: [String]) async throws -> String {
        throw AquinasModelActionError.unavailable
    }

    func blendConceptCandidates(
        _ concepts: [ConceptDefinition],
        weights: [Double]
    ) async throws -> [ConceptDefinition] {
        throw AquinasModelActionError.unavailable
    }

    func generateChildren(for concept: ConceptDefinition) async throws -> [ConceptDefinition] {
        throw AquinasModelActionError.unavailable
    }

    func generateQuestionOfTheDay(
        from context: ConversationContext,
        conversationTitle: String,
        insights: [ConceptDefinition]
    ) async throws -> DailyQuestionDraft {
        throw AquinasModelActionError.unavailable
    }
}
