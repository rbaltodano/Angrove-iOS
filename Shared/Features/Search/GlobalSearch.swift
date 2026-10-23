//
//  GlobalSearch.swift
//  Angrove
//

import Foundation

/// The filter row beneath the global search field.
enum GlobalSearchScope: String, CaseIterable, Identifiable {
    case all, conversations, insights, studyTopics

    var id: Self { self }

    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .conversations: String(localized: "Conversations")
        case .insights: String(localized: "Insights")
        case .studyTopics: String(localized: "Study Topics")
        }
    }

    func emptyMessage(for query: String) -> String {
        switch self {
        case .all: String(localized: "Nothing in your conversations, Insights, or Study Topics matches “\(query)”.")
        case .conversations: String(localized: "No conversation matches “\(query)”.")
        case .insights: String(localized: "No saved Insight matches “\(query)”.")
        case .studyTopics: String(localized: "No Study Topic matches “\(query)”.")
        }
    }
}

/// An app page that search can open, found by its name followed by “Page”.
enum GlobalSearchPage: Int, CaseIterable {
    case home = 1, insights, conversations, library, studyTopics, boards, settings

    /// Boards exist only on the Mac.
    static let iPhonePages: [Self] = [.home, .library, .insights, .conversations, .studyTopics, .settings]
    static let macPages: [Self] = [.home, .insights, .conversations, .library, .studyTopics, .boards, .settings]

    var title: String {
        switch self {
        case .home: String(localized: "Home Page")
        case .insights: String(localized: "Insights Page")
        case .conversations: String(localized: "Conversations Page")
        case .library: String(localized: "Library Page")
        case .studyTopics: String(localized: "Study Topics Page")
        case .boards: String(localized: "Boards Page")
        case .settings: String(localized: "Settings Page")
        }
    }

    var iconName: String {
        switch self {
        case .home: AppPage.home.sidebarIconName
        case .insights: AppPage.insights.sidebarIconName
        case .conversations: AppPage.openConversations.sidebarIconName
        case .library: AppPage.library.sidebarIconName
        case .studyTopics: AppPage.studyTopics.sidebarIconName
        // Matches the Mac sidebar's Boards symbol (`MacIcon.worktree`).
        case .boards: "square.on.square.dashed"
        case .settings: AppPage.settings.sidebarIconName
        }
    }

    /// A fixed identity, so a page keeps its row while the query changes.
    var id: UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", rawValue))!
    }
}

/// One row in the global search results.
struct GlobalSearchResult: Identifiable, Equatable {
    enum Kind: Equatable {
        case conversation, insight, studyTopic
        case page(GlobalSearchPage)
    }

    let id: UUID
    let kind: Kind
    /// The text the row shows: a title, or a passage from a conversation's messages.
    let text: String
    /// `true` when `text` is quoted from a conversation's messages rather than its title.
    let isPassage: Bool
    /// Where the query appears in `text`, used to bold the matching words.
    let matches: [Range<String.Index>]

    var iconName: String {
        switch kind {
        case .conversation: AppPage.openConversations.sidebarIconName
        // The word bubble Insights use everywhere else, not the Insights page's symbol.
        case .insight: "text.bubble.fill"
        case .studyTopic: AppPage.studyTopics.sidebarIconName
        case .page(let page): page.iconName
        }
    }

    /// Conversations and Insights can be dragged onto a page (Mac).
    var isDraggable: Bool {
        kind == .conversation || kind == .insight
    }
}

/// Matches a query against conversations, saved Insights, and Study Topics.
/// Matching ignores case and diacritics; every occurrence is reported for highlighting.
enum GlobalSearch {
    static let resultLimit = 30
    /// Characters of leading context kept before a match inside a long passage.
    static let passageLeadingContext = 24

    static func results(
        for query: String,
        scope: GlobalSearchScope,
        conversations: [InquiryConversation],
        insights: [ConceptDefinition],
        studyTopics: [StudyTopic],
        pages: [GlobalSearchPage] = []
    ) -> [GlobalSearchResult] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }

        var results: [GlobalSearchResult] = []
        if scope == .all || scope == .conversations {
            results += conversations
                .filter { !$0.isStudyTopic }
                .compactMap { conversationResult($0, needle: needle) }
        }
        if scope == .all || scope == .insights {
            results += insights.compactMap { insight in
                titleResult(id: insight.id, kind: .insight, title: insight.word, needle: needle)
            }
        }
        if scope == .all || scope == .studyTopics {
            results += studyTopics.compactMap { topic in
                titleResult(id: topic.id, kind: .studyTopic, title: topic.title, needle: needle)
            }
        }
        if scope == .all {
            results += pages.compactMap { page in
                titleResult(id: page.id, kind: .page(page), title: page.title, needle: needle)
            }
        }
        // Stable, so equally ranked rows keep the conversation → Insight → topic order.
        let ranked = results.enumerated().sorted { lhs, rhs in
            let left = rank(lhs.element), right = rank(rhs.element)
            return left == right ? lhs.offset < rhs.offset : left < right
        }
        return Array(ranked.prefix(resultLimit).map(\.element))
    }

    /// Lower is better: the whole title, then a title that starts with the query, then a match
    /// at the start of a word, then anywhere in a title, then a passage inside a conversation.
    static func rank(_ result: GlobalSearchResult) -> Int {
        guard !result.isPassage, let first = result.matches.first else { return 4 }
        if first == result.text.startIndex..<result.text.endIndex { return 0 }
        if first.lowerBound == result.text.startIndex { return 1 }
        let previous = result.text[result.text.index(before: first.lowerBound)]
        return previous.isLetter || previous.isNumber ? 3 : 2
    }

    /// Every range of `needle` in `text`, ignoring case and diacritics.
    static func ranges(of needle: String, in text: String) -> [Range<String.Index>] {
        guard !needle.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(
                of: needle,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchStart..<text.endIndex
              ) {
            ranges.append(range)
            searchStart = range.upperBound
        }
        return ranges
    }

    private static func titleResult(
        id: UUID,
        kind: GlobalSearchResult.Kind,
        title: String,
        needle: String
    ) -> GlobalSearchResult? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = ranges(of: needle, in: title)
        guard !matches.isEmpty else { return nil }
        return GlobalSearchResult(id: id, kind: kind, text: title, isPassage: false, matches: matches)
    }

    /// A conversation matches on its title first, then on any question or response in it.
    private static func conversationResult(
        _ conversation: InquiryConversation,
        needle: String
    ) -> GlobalSearchResult? {
        if let result = titleResult(id: conversation.id, kind: .conversation, title: conversation.title, needle: needle) {
            return result
        }
        for branch in conversation.branches {
            for block in branch.activeChatBlocks {
                let message: String
                switch block {
                case .user(let question, _, _): message = question
                case .text(let response): message = response
                }
                guard let passage = passage(in: message, around: needle) else { continue }
                return GlobalSearchResult(
                    id: conversation.id,
                    kind: .conversation,
                    text: passage,
                    isPassage: true,
                    matches: ranges(of: needle, in: passage)
                )
            }
        }
        return nil
    }

    /// A single-line excerpt of `message` that starts shortly before the first match,
    /// so the highlighted words stay visible in a truncated row.
    static func passage(in message: String, around needle: String) -> String? {
        let flattened = plainText(message)
        guard let first = ranges(of: needle, in: flattened).first else { return nil }
        let leading = flattened.distance(from: flattened.startIndex, to: first.lowerBound)
        guard leading > passageLeadingContext else { return flattened }

        var start = flattened.index(first.lowerBound, offsetBy: -passageLeadingContext)
        // Begin at a word boundary rather than mid-word.
        if let space = flattened[start..<first.lowerBound].firstIndex(of: " ") {
            start = flattened.index(after: space)
        }
        return "…" + flattened[start...]
    }

    /// Collapses Markdown emphasis, headings, and line breaks into one readable line.
    private static func plainText(_ message: String) -> String {
        message
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "#", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
