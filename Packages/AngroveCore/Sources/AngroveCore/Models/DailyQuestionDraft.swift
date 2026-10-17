import Foundation

public struct DailyQuestionDraft: Equatable, Sendable {
    public let question: String
    public let reasonForAsking: String
    public let citedInsightTitle: String?

    public init(question: String, reasonForAsking: String, citedInsightTitle: String?) {
        self.question = question
        self.reasonForAsking = reasonForAsking
        self.citedInsightTitle = citedInsightTitle
    }
}
