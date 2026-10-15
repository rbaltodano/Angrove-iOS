import Foundation

/// Worktree slash commands.
enum WorktreeCommand: Equatable {
    /// `/rename`: text after the command names the item; without it the model writes the label.
    case label(String?)
    /// Makes an Insight card for the term; without one there is nothing to define.
    case define(String?)
    /// A brief summary of the selected object.
    case summarize

    /// Object dependent: acts on the selected item, so it is invalid with nothing selected.
    var isObjectDependent: Bool {
        switch self {
        case .define, .summarize: true
        case .label: false
        }
    }
}

/// What a person typed: an optional question, then commands to run after it, in order.
struct WorktreeInput: Equatable {
    var question: String?
    var commands: [WorktreeCommand] = []
}

enum WorktreeCommandParser {
    private static let names: Set<String> = ["/rename", "/define", "/summarize"]
    /// A recognised command word, standing alone between whitespace.
    private static let token = try! NSRegularExpression(pattern: #"(?<![^\s])/(?:rename|define|summarize)(?![^\s])"#,
                                                        options: [.caseInsensitive])

    /// Ranges of recognised command words, for highlighting.
    static func commandRanges(in text: String) -> [NSRange] {
        token.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).map(\.range)
    }

    /// Splits `"question" /rename /rename Title`. With `requiresQuotes`, only text opened with a
    /// quotation mark is a question (the canvas); otherwise any leading text is (a follow-up).
    static func parse(_ text: String, requiresQuotes: Bool) -> WorktreeInput {
        let source = text as NSString
        let first = commandRanges(in: text).first
        let lead = (first.map { source.substring(to: $0.location) } ?? text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = first.map { source.substring(from: $0.location) } ?? ""

        var input = WorktreeInput()
        let isQuoted = lead.first == "\"" || lead.first == "“"
        if isQuoted || (!requiresQuotes && !lead.isEmpty) {
            let question = lead.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !question.isEmpty { input.question = question }
        }

        var name: String?
        var words: [String] = []
        func flush() {
            guard name != nil else { return }
            let argument = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            let value = argument.isEmpty ? nil : argument
            switch name {
            case "/define": input.commands.append(.define(value))
            case "/summarize": input.commands.append(.summarize)
            default: input.commands.append(.label(value)) // /rename
            }
        }
        for word in rest.split(whereSeparator: \.isWhitespace).map(String.init) {
            if names.contains(word.lowercased()) {
                flush()
                name = word.lowercased()
                words = []
            } else {
                words.append(word)
            }
        }
        flush()
        return input
    }
}
