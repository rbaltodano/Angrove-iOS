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
    /// Opens the file browser (pictures only, for now) and places what is chosen.
    case file

    /// Object dependent: acts on the selected item, so it is invalid with nothing selected.
    var isObjectDependent: Bool {
        switch self {
        case .define(let term): term == nil
        case .summarize: true
        case .label, .heading, .file: false
        }
    }
}

/// What a person typed: an optional question, then commands to run after it, in order.
struct WorktreeInput: Equatable {
    var question: String?
    var commands: [WorktreeCommand] = []
}

enum WorktreeCommandParser {
    /// Each command word, and its one-letter short form, by full name.
    static let aliases: [String: String] = [
        "/rename": "/rename", "/r": "/rename",
        "/define": "/define", "/d": "/define",
        "/summarize": "/summarize", "/s": "/summarize",
        "/heading": "/heading", "/h": "/heading",
        "/file": "/file", "/f": "/file",
    ]
    /// A recognised command word, standing alone between whitespace.
    private static let token = try! NSRegularExpression(pattern: #"(?<![^\s])/(?:rename|define|summarize|heading|file|r|d|s|h|f)(?![^\s])"#,
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
            case "/file": input.commands.append(.file)
            default: input.commands.append(.label(value)) // /rename
            }
        }
        for word in rest.split(whereSeparator: \.isWhitespace).map(String.init) {
            if let full = aliases[word.lowercased()] {
                flush()
                name = full
                words = []
            } else {
                words.append(word)
            }
        }
        flush()
        return input
    }
}

/// What a `/help` card placed before the Tools card replaced it lists, in order.
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
        Entry(name: "/file", explanation: String(localized: "Opens the file browser and places the pictures you choose where you click.")),
    ]
}

/// The Tools card's rows: each can be clicked to place it on the canvas, typed as a command
/// (full or short), or run with its shortcut.
enum WorktreeTool: String, CaseIterable, Identifiable {
    case text, question, heading, rename, summarize, define, file

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: String(localized: "Text")
        case .question: String(localized: "Question")
        case .heading: String(localized: "Heading")
        case .rename: String(localized: "Rename")
        case .summarize: String(localized: "Summarize")
        case .define: String(localized: "Define")
        case .file: String(localized: "Add File")
        }
    }

    /// The full command and its short form; Text and Question have none.
    var command: (full: String, short: String)? {
        switch self {
        case .text, .question: nil
        case .heading: ("/heading", "/h")
        case .rename: ("/rename", "/r")
        case .summarize: ("/summarize", "/s")
        case .define: ("/define", "/d")
        case .file: ("/file", "/f")
        }
    }

    /// The key pressed with Command, and whether Shift is held too.
    var shortcut: (key: String, shift: Bool)? {
        switch self {
        case .text, .question: nil
        case .heading: ("h", true)
        case .rename: ("r", false)
        case .summarize: ("s", false)
        case .define: ("d", false)
        case .file: ("k", true)
        }
    }

    /// The tool a Command-key press runs on the Worktree page, if any.
    static func forShortcut(key: String, shift: Bool) -> WorktreeTool? {
        allCases.first { $0.shortcut.map { $0.key == key.lowercased() && $0.shift == shift } ?? false }
    }

    /// Acts on something clicked rather than placing new material where the click lands.
    var needsTarget: Bool { self == .rename || self == .summarize || self == .define }

    /// What follows the pointer while the tool is being placed.
    var placementPrompt: String {
        switch self {
        case .text: String(localized: "Text")
        case .question: "“"
        case .heading: String(localized: "Heading")
        case .rename: String(localized: "Click on something to rename")
        case .summarize: String(localized: "Click on something to summarize")
        case .define: String(localized: "Click on something to define")
        case .file: ""
        }
    }
}
