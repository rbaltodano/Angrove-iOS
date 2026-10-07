//
//  ConceptDefinition.swift
//  Angrove-iOS
//

import Foundation

nonisolated struct InsightDefinition: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    let context: String
    let meaning: String

    init(id: UUID? = nil, context: String, meaning: String) {
        let cleanedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedMeaning = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id ?? stableUUID(
            from: "insight-definition:\(cleanedContext.lowercased()):\(cleanedMeaning.lowercased())"
        )
        self.context = cleanedContext
        self.meaning = cleanedMeaning
    }

    /// Context labels identify the source, not a new meaning. Keep the first saved entry/ID
    /// when a later lookup repeats it with different punctuation or minor wording changes.
    fileprivate func repeatsMeaning(of other: InsightDefinition) -> Bool {
        let lhs = Self.words(meaning), rhs = Self.words(other.meaning)
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        if lhs == rhs { return true }
        // Short definitions need exact matching; a single changed word can reverse the meaning.
        guard min(lhs.count, rhs.count) >= 20 else { return false }
        let negations: Set<String> = ["not", "no", "never", "neither", "without", "cannot"]
        guard lhs.filter({ negations.contains($0) }) == rhs.filter({ negations.contains($0) }) else {
            return false
        }
        let overlap = Self.orderedOverlap(lhs, rhs)
        if overlap >= 0.90 { return true }

        // Long restatements can share the same defining sentence but add different elaboration.
        let first = Self.words(meaning.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).first ?? "")
        let second = Self.words(other.meaning.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).first ?? "")
        return min(first.count, second.count) >= 28
            && Self.orderedOverlap(first, second) >= 0.94
            && overlap >= 0.70
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Dice similarity of the longest common token sequence: word order and repeated words count.
    private static func orderedOverlap(_ lhs: [String], _ rhs: [String]) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        var previous = Array(repeating: 0, count: rhs.count + 1)
        for word in lhs {
            var current = Array(repeating: 0, count: rhs.count + 1)
            for index in rhs.indices {
                current[index + 1] = word == rhs[index]
                    ? previous[index] + 1
                    : max(previous[index + 1], current[index])
            }
            previous = current
        }
        return 2 * Double(previous[rhs.count]) / Double(lhs.count + rhs.count)
    }

    fileprivate static func unique(_ definitions: [InsightDefinition]) -> [InsightDefinition] {
        var result: [InsightDefinition] = []
        for definition in definitions {
            if !result.contains(where: { definition.repeatsMeaning(of: $0) }) {
                result.append(definition)
            }
        }
        return result
    }
}

nonisolated struct ConceptDefinition: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    let word: String
    let partOfSpeech: String
    let pronunciation: String
    let meaning: String
    let example: String
    let definitions: [InsightDefinition]
    let isLibraryQuote: Bool
    let libraryAttribution: String?

    init(
        id: UUID = UUID(),
        word: String,
        partOfSpeech: String,
        pronunciation: String,
        meaning: String,
        example: String,
        context: String = "",
        definitions: [InsightDefinition]? = nil,
        isLibraryQuote: Bool = false,
        libraryAttribution: String? = nil
    ) {
        self.id = id
        self.word = word
        self.partOfSpeech = partOfSpeech
        self.pronunciation = pronunciation
        self.meaning = meaning
        self.example = example
        self.isLibraryQuote = isLibraryQuote
        self.libraryAttribution = libraryAttribution
        self.definitions = InsightDefinition.unique(definitions ?? (
            meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? []
                : [InsightDefinition(context: context, meaning: meaning)]
        ))
    }

    var contextualDefinitions: [InsightDefinition] {
        definitions.isEmpty && !meaning.isEmpty
            ? [InsightDefinition(context: "", meaning: meaning)]
            : definitions
    }

    var semanticDefinition: String {
        contextualDefinitions.map { definition in
            definition.context.isEmpty
                ? definition.meaning
                : "\(definition.context): \(definition.meaning)"
        }
        .joined(separator: "\n")
    }

    func containsDefinitions(from other: ConceptDefinition) -> Bool {
        let saved = contextualDefinitions
        let incoming = other.contextualDefinitions
        return !incoming.isEmpty
            && incoming.allSatisfy { candidate in
                saved.contains { candidate.repeatsMeaning(of: $0) }
            }
    }

    func mergingDefinitions(from other: ConceptDefinition) -> ConceptDefinition {
        let merged = InsightDefinition.unique(contextualDefinitions + other.contextualDefinitions)
        return ConceptDefinition(
            id: id,
            word: word,
            partOfSpeech: "",
            pronunciation: "",
            meaning: merged.first?.meaning ?? meaning,
            example: "",
            definitions: merged,
            isLibraryQuote: isLibraryQuote,
            libraryAttribution: libraryAttribution
        )
    }

    /// A stable id derived from the term's canonical text, so re-defining/re-saving the same term
    /// (tapping it again in a different message, or after removing and re-saving it) always
    /// resolves to the same Insight instead of a duplicate with a fresh random id. Use this rather
    /// than the default random `id` whenever a concept originates from a highlighted term.
    static func stableID(forTerm term: String) -> UUID {
        stableUUID(from: "term:\(term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())")
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case word
        case partOfSpeech
        case pronunciation
        case meaning
        case example
        case definitions
        case isLibraryQuote
        case libraryAttribution
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        word = try container.decode(String.self, forKey: .word)
        partOfSpeech = try container.decodeIfPresent(String.self, forKey: .partOfSpeech) ?? ""
        pronunciation = try container.decodeIfPresent(String.self, forKey: .pronunciation) ?? ""
        meaning = try container.decodeIfPresent(String.self, forKey: .meaning) ?? ""
        example = try container.decodeIfPresent(String.self, forKey: .example) ?? ""
        definitions = InsightDefinition.unique(try container.decodeIfPresent(
            [InsightDefinition].self,
            forKey: .definitions
        ) ?? (
            meaning.isEmpty ? [] : [InsightDefinition(context: "", meaning: meaning)]
        ))
        isLibraryQuote = try container.decodeIfPresent(Bool.self, forKey: .isLibraryQuote) ?? false
        libraryAttribution = try container.decodeIfPresent(String.self, forKey: .libraryAttribution)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(word, forKey: .word)
        try container.encode(partOfSpeech, forKey: .partOfSpeech)
        try container.encode(pronunciation, forKey: .pronunciation)
        try container.encode(meaning, forKey: .meaning)
        try container.encode(example, forKey: .example)
        try container.encode(definitions, forKey: .definitions)
        try container.encode(isLibraryQuote, forKey: .isLibraryQuote)
        try container.encodeIfPresent(libraryAttribution, forKey: .libraryAttribution)
    }
}
