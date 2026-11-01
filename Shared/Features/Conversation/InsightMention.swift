//
//  InsightMention.swift
//  Angrove-iOS
//

import Foundation

/// Quoting an Insight by typing `#` and its title in a question. `#` only starts a mention at
/// the beginning of a word, so text such as "C#" or "#1" in a question stays ordinary text.
/// Mentions stay in the draft, colored like a command, and become quotes when it is sent.
enum InsightMention {
    /// Characters that end a typed title.
    private static let terminators: Set<Character> = [" ", ",", ".", ";", ":", "!", "?", ")", "\""]

    /// The title being typed after a `#` at the end of the draft, without the `#`.
    static func activeQuery(in text: String) -> String? {
        guard let hash = text.lastIndex(of: "#") else { return nil }
        if hash > text.startIndex, !text[text.index(before: hash)].isWhitespace { return nil }
        let query = text[text.index(after: hash)...]
        guard !query.contains(where: \.isNewline), !query.hasPrefix(" ") else { return nil }
        return String(query)
    }

    /// Insights whose titles match the typed query: title prefixes first, then other matches,
    /// each group in the candidates' order. An empty query lists every candidate.
    static func suggestions(
        for query: String,
        from candidates: [ConceptDefinition],
        excluding quotedIDs: Set<UUID> = []
    ) -> [ConceptDefinition] {
        let available = unique(candidates).filter { !quotedIDs.contains($0.id) }
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return available }
        let prefixed = available.filter { $0.word.lowercased().hasPrefix(query) }
        let containing = available.filter {
            !$0.word.lowercased().hasPrefix(query) && $0.word.lowercased().contains(query)
        }
        return prefixed + containing
    }

    /// A recognized `#title` in a draft: its UTF-16 range, including the `#`, and its Insight.
    struct Mention: Equatable {
        let range: NSRange
        let concept: ConceptDefinition
    }

    /// Every complete `#title` in the draft, matching the longest title. A title must end at a
    /// space, punctuation, a line break, or the end of the draft; at the very end it must also
    /// be one no longer title could still continue ("#law" waits while "Law of nature" exists).
    static func mentions(in text: String, candidates: [ConceptDefinition]) -> [Mention] {
        let candidates = unique(candidates)
        guard !candidates.isEmpty else { return [] }
        let source = text as NSString
        var result: [Mention] = []
        var searchStart = 0
        while searchStart < source.length {
            let hash = source.range(
                of: "#",
                range: NSRange(location: searchStart, length: source.length - searchStart)
            )
            guard hash.location != NSNotFound else { break }
            searchStart = hash.location + 1
            if hash.location > 0 {
                let before = source.substring(with: NSRange(location: hash.location - 1, length: 1))
                if before.rangeOfCharacter(from: .whitespacesAndNewlines) == nil { continue }
            }
            let rest = source.substring(from: hash.location + 1).lowercased()
            let matches = candidates.filter { candidate in
                let title = candidate.word.lowercased()
                guard rest.hasPrefix(title) else { return false }
                guard let after = rest.dropFirst(title.count).first else { return true }
                return after.isNewline || terminators.contains(after)
            }
            guard let match = matches.max(by: { $0.word.count < $1.word.count }) else { continue }
            let range = NSRange(location: hash.location, length: (match.word as NSString).length + 1)
            if NSMaxRange(range) == source.length {
                let typed = match.word.lowercased()
                let couldContinue = candidates.contains {
                    let title = $0.word.lowercased()
                    return title != typed && title.hasPrefix(typed)
                }
                if couldContinue { continue }
            }
            result.append(Mention(range: range, concept: match))
            searchStart = NSMaxRange(range)
        }
        return result
    }

    /// The question as sent: each recognized mention keeps its words and loses its `#`.
    static func resolving(_ mentions: [Mention], in text: String) -> String {
        let result = NSMutableString(string: text)
        for mention in mentions.sorted(by: { $0.range.location > $1.range.location }) {
            result.deleteCharacters(in: NSRange(location: mention.range.location, length: 1))
        }
        return result as String
    }

    /// The draft with the `#title` being typed at its end completed to the Insight's title,
    /// followed by a space so typing continues after it.
    static func completingActiveQuery(in text: String, with concept: ConceptDefinition) -> String {
        guard let query = activeQuery(in: text) else { return text }
        return String(text.dropLast(query.count)) + concept.word + " "
    }

    /// One candidate per title, keeping the first (the conversation's own Insight).
    private static func unique(_ candidates: [ConceptDefinition]) -> [ConceptDefinition] {
        var seen = Set<String>()
        return candidates.filter { !$0.isLibraryQuote && seen.insert($0.word.lowercased()).inserted }
    }
}
