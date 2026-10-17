import Foundation

extension HomeQuestionOfTheDay {
    /// Home and the widget open the same answer composer, even for an older saved question.
    var conversationRequest: NewConversationRequest {
        NewConversationRequest(
            question: question,
            eyebrow: "QUESTION OF THE DAY",
            promptContext: taggedPromptContext
        )
    }
}
