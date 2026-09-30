import Foundation
import Observation

/// One complete handoff into a new conversation. Display text and hidden prompt context stay
/// distinct, while metadata can no longer be left behind for an unrelated later request.
struct NewConversationRequest: Identifiable, Equatable {
    let id: UUID
    let question: String
    let eyebrow: String
    let promptContext: String
    let subtitle: String
    let topicID: UUID?
    let isStudyTopic: Bool
    let quote: NewConversationInsightQuoteRequest?

    init(
        id: UUID = UUID(),
        question: String = "",
        eyebrow: String = "",
        promptContext: String = "",
        subtitle: String = "",
        topicID: UUID? = nil,
        isStudyTopic: Bool = false,
        quote: NewConversationInsightQuoteRequest? = nil
    ) {
        self.id = id
        self.question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        self.eyebrow = eyebrow.trimmingCharacters(in: .whitespacesAndNewlines)
        self.promptContext = promptContext.trimmingCharacters(in: .whitespacesAndNewlines)
        self.subtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.topicID = topicID
        self.isStudyTopic = isStudyTopic
        self.quote = quote
    }
}

/// Owned by the app shell so consuming a request survives conversation-page remounts.
/// As with the previous counters, multiple unhandled requests select the latest destination.
@MainActor
@Observable
final class NewConversationRequests {
    private(set) var pending: NewConversationRequest?

    func submit() {
        submit(NewConversationRequest())
    }

    func submit(_ request: NewConversationRequest) {
        pending = request
    }

    func takePending() -> NewConversationRequest? {
        defer { pending = nil }
        return pending
    }
}
