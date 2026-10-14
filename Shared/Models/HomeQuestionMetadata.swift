import Foundation

struct HomeQuestionOfTheDay: Codable, Equatable, Identifiable {
    let id: UUID
    let question: String
    let reasonForAsking: String
    let citedInsight: ConceptDefinition?
    let sourceConversationID: UUID?
    let sourceConversationTitle: String?
    let generatedAt: Date
    let expiresAt: Date
    let answeredAt: Date?

    init(
        id: UUID = UUID(),
        question: String,
        reasonForAsking: String = "",
        citedInsight: ConceptDefinition? = nil,
        sourceConversationID: UUID? = nil,
        sourceConversationTitle: String? = nil,
        generatedAt: Date = Date(),
        expiresAt: Date? = nil,
        answeredAt: Date? = nil
    ) {
        self.id = id
        self.question = question
        self.reasonForAsking = reasonForAsking
        self.citedInsight = citedInsight
        self.sourceConversationID = sourceConversationID
        self.sourceConversationTitle = sourceConversationTitle
        self.generatedAt = generatedAt
        self.expiresAt = expiresAt ?? generatedAt.addingTimeInterval(24 * 60 * 60)
        self.answeredAt = answeredAt
    }

    func isPending(at date: Date = Date()) -> Bool {
        Self.isValidQuestionText(question)
            && answeredAt == nil
            && expiresAt > date
    }

    static func isValidQuestionText(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).last == "?"
    }

    func markingAnswered(at date: Date = Date()) -> HomeQuestionOfTheDay {
        HomeQuestionOfTheDay(
            id: id,
            question: question,
            reasonForAsking: reasonForAsking,
            citedInsight: citedInsight,
            sourceConversationID: sourceConversationID,
            sourceConversationTitle: sourceConversationTitle,
            generatedAt: generatedAt,
            expiresAt: expiresAt,
            answeredAt: date
        )
    }

    func nextEligibleRefreshDate(
        calendar: Calendar = .current
    ) -> Date {
        guard Self.isValidQuestionText(question) else {
            return .distantPast
        }
        guard let nextCalendarDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: generatedAt)
        ) else {
            return .distantFuture
        }
        if answeredAt != nil {
            return nextCalendarDay
        }
        return max(expiresAt, nextCalendarDay)
    }

    /// Home and the widget open the same answer composer, even for an older saved question.
    var conversationRequest: NewConversationRequest {
        NewConversationRequest(
            question: question,
            eyebrow: "QUESTION OF THE DAY",
            promptContext: taggedPromptContext
        )
    }

    /// Hidden context prepended to the first conversation created from the card.
    /// The deliberately human-readable outer tag matches the product language.
    var taggedPromptContext: String {
        var lines = [
            "<question of the day>",
            "<question>\(question.xmlEscaped)</question>"
        ]
        if !reasonForAsking.isEmpty {
            lines.append(
                "<reason_for_asking>\(reasonForAsking.xmlEscaped)</reason_for_asking>"
            )
        }
        if let citedInsight {
            lines.append(
                "<relevant_insight title=\"\(citedInsight.word.xmlEscaped)\">"
                    + citedInsight.semanticDefinition.xmlEscaped
                    + "</relevant_insight>"
            )
        }
        lines.append(
            "<response_guidance>The user's next message answers this question. "
                + "Occasionally mention the reason for asking or relevant Insight when natural."
                + "</response_guidance>"
        )
        lines.append("</question of the day>")
        return lines.joined(separator: "\n")
    }
}

extension String {
    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

func debugQuestionOfTheDayConsoleLog(_ message: String) {
#if DEBUG
    guard let data = "[QuestionOfTheDay] \(message)\n".data(using: .utf8) else { return }
    try? FileHandle.standardError.write(contentsOf: data)
#endif
}
