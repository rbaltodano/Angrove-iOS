import Foundation

/// Shared Insight-markup removal with explicit policies for the two existing consumers.
/// Definition context preserves emphasis; conversation previews also remove legacy braces.
enum ResponseTextFormatting {
    private static let insightLinkPattern = #"\[([^\]]+)\]\(aq://[^)]+\)"#
    private static let contextLinks = try! NSRegularExpression(pattern: insightLinkPattern)
    private static let previewMarkup = try! NSRegularExpression(
        pattern: #"\*{0,2}"# + insightLinkPattern + #"\*{0,2}|\*{0,2}\{\{([^{}]+)\}\}\*{0,2}"#
    )

    static func definitionContext(from text: String) -> String {
        InlineInsightMarkup.plainText(from: replacingMarkup(in: text, using: contextLinks))
    }

    static func previewText(from text: String) -> String {
        replacingMarkup(in: InlineInsightMarkup.plainText(from: text), using: previewMarkup)
            .replacingOccurrences(of: "{{", with: "")
            .replacingOccurrences(of: "}}", with: "")
    }

    private static func replacingMarkup(in text: String, using pattern: NSRegularExpression) -> String {
        let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var result = ""
        var cursor = text.startIndex

        for match in matches {
            guard let fullRange = Range(match.range, in: text) else { continue }
            result += text[cursor..<fullRange.lowerBound]
            let titleRange = match.range(at: 1).location != NSNotFound
                ? match.range(at: 1)
                : match.range(at: 2)
            if let titleRange = Range(titleRange, in: text) {
                result += text[titleRange]
            }
            cursor = fullRange.upperBound
        }
        result += text[cursor...]
        return result
    }
}

/// Formatting boundary used by conversation cards and their existing callers.
enum ConversationCardAnswerFormatting {
    enum Segment: Equatable {
        case plain(String)
    }

    static func segments(from answer: String) -> [Segment] {
        let text = ResponseTextFormatting.previewText(from: answer)
        return text.isEmpty ? [] : [.plain(text)]
    }

    static func attributedText(from answer: String) -> AttributedString {
        AttributedString(ResponseTextFormatting.previewText(from: answer))
    }
}
