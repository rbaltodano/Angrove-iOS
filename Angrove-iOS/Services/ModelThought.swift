//
//  ModelThought.swift
//  Angrove-iOS
//

import Foundation

/// Turns Gemma 4's raw `thought` channel (markdown-ish numbered notes) into readable lines for
/// the live **Thinking** display and **Show Thinking**.
///
/// Gemma's thinking habitually plans the reply's persona, tone, structure, and drafting, and
/// checks itself against the system prompt. Prompting does not stop it (tested on E4B with the
/// instruction at the start of the system prompt, the end, and in the user turn), so that
/// self-talk is filtered here, leaving the reasoning about the question itself.
nonisolated enum ModelThought {
    /// Every readable line of the thought so far, including a trailing line still being written.
    static func lines(in thought: String) -> [String] {
        entries(in: thought).map(\.text)
    }

    /// The line to show while the model is still thinking: the most recently completed line, so
    /// the display advances a whole line at a time instead of flickering word by word. Falls back
    /// to the line in progress until the first one completes.
    static func currentLine(in thought: String) -> String? {
        let visible = entries(in: thought)
        return visible.last(where: \.isComplete)?.text ?? visible.last?.text
    }

    private enum Marker { case numbered, bullet, none }

    private struct Skip {
        let indent: Int
        let marker: Marker
    }

    private static func entries(in thought: String) -> [(text: String, isComplete: Bool)] {
        let rawLines = thought.components(separatedBy: .newlines)
        var result: [(text: String, isComplete: Bool)] = []
        var skip: Skip?
        for (index, raw) in rawLines.enumerated() {
            let indent = raw.prefix(while: { $0 == " " || $0 == "\t" }).count
            let marker = marker(of: raw)
            guard let line = cleanedLine(raw) else {
                // A blank line closes an unnumbered meta section ("Structure:" then a list).
                if raw.trimmingCharacters(in: .whitespaces).isEmpty { skip = nil }
                continue
            }
            if let active = skip {
                // A meta section ends at its next sibling: same-or-shallower indent with the same
                // kind of list marker. Everything else belongs to it.
                if indent > active.indent || marker != active.marker { continue }
                skip = nil
            }
            let heading = heading(of: line)
            if let heading, matches(heading, sectionTerms) {
                skip = Skip(indent: indent, marker: marker)
                continue
            }
            // Drafting sections often hold the substance, so only their heading is dropped.
            if let heading, heading.contains("draft") { continue }
            if matches(line.lowercased(), metaLineTerms) { continue }
            result.append((line, index < rawLines.count - 1))
        }
        return result
    }

    private static func marker(of raw: String) -> Marker {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.range(of: #"^\d+[.)]\s"#, options: .regularExpression) != nil { return .numbered }
        if trimmed.range(of: #"^[*\-•]\s"#, options: .regularExpression) != nil { return .bullet }
        return .none
    }

    private static func cleanedLine(_ raw: String) -> String? {
        var line = raw.replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespaces)
        // Drop list markers ("1.", "*", "-", "•") that the numbered rows already supply.
        if let marker = line.range(of: #"^(\d+[.)]|[*\-•])\s+"#, options: .regularExpression) {
            line.removeSubrange(marker)
        }
        line = line
            .replacingOccurrences(of: " * ", with: " × ")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "{{", with: "")
            .replacingOccurrences(of: "}}", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !isBoilerplateHeading(line) else { return nil }
        return line
    }

    private static func isBoilerplateHeading(_ line: String) -> Bool {
        let normalized = line.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        return ["thinking process", "thought process", "thinking"].contains(normalized)
    }

    /// The text before the first colon, when short enough to be a heading.
    private static func heading(of line: String) -> String? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let heading = line[..<colon].lowercased()
        return heading.count <= 60 ? heading : nil
    }

    /// Section headings about composing the reply; the section and its sub-points are hidden.
    private static let sectionTerms = [
        "persona", "tone", "style", "structure", "refin", "review", "constraint", "polish",
        "self-correction", "output", "format", "length"
    ]

    /// Single lines that talk about the instructions rather than the subject.
    private static let metaLineTerms = [
        "persona", "tone", "system instruction", "instructions", "constraint", "chain-of-thought",
        "link-worthy", "corpus passage", "angrove", "(check)", "marker", "scholar friend"
    ]

    private static func matches(_ text: String, _ terms: [String]) -> Bool {
        terms.contains { term in
            // Word-start boundary, so "tone" does not match "stone" or "atonement".
            text.range(
                of: #"(^|[^a-z])"# + NSRegularExpression.escapedPattern(for: term),
                options: .regularExpression
            ) != nil
        }
    }
}
