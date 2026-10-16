import Foundation

/// Worktree slash commands.
enum WorktreeCommand: Equatable {
    /// `/rename`: text after the command names the item; without it the model writes the label.
    case label(String?)
    /// Defines the typed term, or the selected material when no term follows.
    case define(String?)
    /// A brief summary of the selected object.
    case summarize
    /// A 40pt heading of the text after it; without text there is nothing to set.
    case heading(String?)
    /// A card listing every command, each opening onto its explanation.
    case help

    /// Object dependent: acts on the selected item, so it is invalid with nothing selected.
    var isObjectDependent: Bool {
        switch self {
        case .define(let term): term == nil
        case .summarize: true
        case .label, .heading, .help: false
        }
    }
}

/// What a person typed: an optional question, then commands to run after it, in order.
struct WorktreeInput: Equatable {
    var question: String?
    var commands: [WorktreeCommand] = []
}

enum WorktreeCommandParser {
    private static let names: Set<String> = ["/rename", "/define", "/summarize", "/heading", "/help"]
    /// A recognised command word, standing alone between whitespace.
    private static let token = try! NSRegularExpression(pattern: #"(?<![^\s])/(?:rename|define|summarize|heading|help)(?![^\s])"#,
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
            case "/heading": input.commands.append(.heading(value))
            case "/help": input.commands.append(.help)
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

/// What `/help` lists, in order.
enum WorktreeCommandGuide {
    struct Entry: Identifiable {
        let name: String
        let explanation: String
        var id: String { name }
    }

    static let entries: [Entry] = [
        Entry(name: "/rename", explanation: String(localized: "Names what you hover or have selected (each, if several), or the whole Worktree when nothing is. The model writes the name, or type your own right after the command.")),
        Entry(name: "/define", explanation: String(localized: "Defines the material you hover or select, or defines the term typed after the command in that material’s context. An existing Insight needs an explicit term. With a typed term, no selection is required.")),
        Entry(name: "/summarize", explanation: String(localized: "Writes a brief summary of what you hover or have selected, read together, and places it beside it.")),
        Entry(name: "/heading", explanation: String(localized: "Adds a heading from the hovered or selected material, or from text typed after the command. Existing headings cannot be headed again.")),
        Entry(name: "/help", explanation: String(localized: "Shows this list. Commands can follow a question in quotation marks, and run in the order typed.")),
    ]
}
