//
//  UnavailableAngroveModel.swift
//  Angrove-iOS
//

import Foundation

/// The live model boundary when no verified on-device model is installed. Every generative action
/// fails explicitly rather than inventing content; `MockAngroveModel` stays preview/test-only.
struct UnavailableAngroveModel: AngroveModel {
    static let unavailableMessage =
        "Angrove's on-device model isn't installed, so it can't answer yet."

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
        throw AngroveModelActionError.unavailable
    }

    func labelSubject(forTitles titles: [String]) async throws -> String {
        throw AngroveModelActionError.unavailable
    }

    func blendConceptCandidates(
        _ concepts: [ConceptDefinition],
        weights: [Double]
    ) async throws -> [ConceptDefinition] {
        throw AngroveModelActionError.unavailable
    }

    func generateChildren(for concept: ConceptDefinition) async throws -> [ConceptDefinition] {
        throw AngroveModelActionError.unavailable
    }

    func generateQuestionOfTheDay(
        from context: ConversationContext,
        conversationTitle: String,
        insights: [ConceptDefinition]
    ) async throws -> DailyQuestionDraft {
        throw AngroveModelActionError.unavailable
    }
}
