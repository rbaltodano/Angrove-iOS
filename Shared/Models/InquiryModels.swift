//
//  InquiryModels.swift
//  Angrove-iOS
//

import Foundation
import SwiftUI

// MARK: - Inquiry Data

/// One vertical conversation lane. Branches can begin from an insight chip or a copied model response.
nonisolated struct ChatBranch: Identifiable, Codable, Equatable {
    let id: UUID
    let startingConcept: ConceptDefinition?
    let parentBranchID: UUID?
    var parentResponseIndex: Int?
    let duplicatedResponse: String?
    var yOffset: CGFloat = 0
    var activeChatBlocks: [ChatBlock] = []
    var topQuestionText: String = ""
    var topQuestionUploads: [UploadedFile] = []
    var topQuestionSubmitted: Bool = false
    var bottomQuestionText: String = ""
    var showBottomInput: Bool = false
    /// The first Insight quoted into the follow-up question. Stored alone under its original key
    /// so earlier builds still read one quote; use `attachedConcepts` to read or change quotes.
    private(set) var attachedConcept: ConceptDefinition? = nil
    private(set) var additionalAttachedConcepts: [ConceptDefinition] = []
    /// The first Insight quoted into the branch's first question, stored like `attachedConcept`.
    private(set) var branchContextConcept: ConceptDefinition? = nil
    private(set) var additionalBranchContextConcepts: [ConceptDefinition] = []
    var generatedBranchTitle: String? = nil
    /// Hidden model context produced by `/compact`. The visible transcript remains untouched.
    var compactedContext: String? = nil
    /// Number of `activeChatBlocks` represented by `compactedContext`.
    /// Optional so conversations persisted before compaction support continue to decode.
    var compactedThroughBlockCount: Int? = nil
    /// Invisible product context attached to special entry points such as Question of the Day.
    var hiddenPromptContext: String? = nil
    /// The literal question text pinned as this branch's big header title (e.g. the Question of
    /// the Day prompt), permanently — independent of the conversation's own title, which can be
    /// renamed or auto-generated afterward without changing what's shown here.
    var pinnedHeaderQuestion: String? = nil
    /// Persisted user-facing approach summaries for completed model responses. Optional so
    /// conversations saved before this metadata existed continue to decode.
    var responsePresentations: [ResponsePresentationMetadata]? = nil

    init(
        id: UUID = UUID(),
        startingConcept: ConceptDefinition?,
        parentBranchID: UUID? = nil,
        parentResponseIndex: Int? = nil,
        duplicatedResponse: String? = nil,
        yOffset: CGFloat = 0,
        hiddenPromptContext: String? = nil
    ) {
        self.id = id
        self.startingConcept = startingConcept
        self.parentBranchID = parentBranchID
        self.parentResponseIndex = parentResponseIndex
        self.duplicatedResponse = duplicatedResponse
        self.yOffset = yOffset
        self.hiddenPromptContext = hiddenPromptContext
    }

    /// Insights quoted into the follow-up question, in the order they were added.
    var attachedConcepts: [ConceptDefinition] {
        get { (attachedConcept.map { [$0] } ?? []) + additionalAttachedConcepts }
        set {
            attachedConcept = newValue.first
            additionalAttachedConcepts = Array(newValue.dropFirst())
        }
    }

    /// Insights quoted into the branch's first question, in the order they were added.
    var branchContextConcepts: [ConceptDefinition] {
        get { (branchContextConcept.map { [$0] } ?? []) + additionalBranchContextConcepts }
        set {
            branchContextConcept = newValue.first
            additionalBranchContextConcepts = Array(newValue.dropFirst())
        }
    }

    /// The most Insights one question can quote, keeping the on-device prompt small.
    static let maximumQuotedInsights = 5

    /// Quotes on the question currently being written: the first question until it is sent,
    /// then the follow-up.
    var editableQuestionQuotes: [ConceptDefinition] {
        isEditingFirstQuestion ? branchContextConcepts : attachedConcepts
    }

    /// Whether the current editable question can take another quote.
    var canQuoteAnotherInsight: Bool {
        editableQuestionQuotes.count < Self.maximumQuotedInsights
    }

    private var isEditingFirstQuestion: Bool { !topQuestionSubmitted && activeChatBlocks.isEmpty }

    /// Quotes use the current editable question. An unanswered first question never needs
    /// a second composer just to hold an attachment. Quoting an Insight already quoted, or one
    /// past the limit, leaves the quotes unchanged.
    mutating func attachQuote(_ concept: ConceptDefinition) {
        if isEditingFirstQuestion {
            branchContextConcepts = Self.adding(concept, to: branchContextConcepts)
            attachedConcepts = []
            showBottomInput = false
        } else {
            attachedConcepts = Self.adding(concept, to: attachedConcepts)
            showBottomInput = true
        }
    }

    private static func adding(_ concept: ConceptDefinition, to quotes: [ConceptDefinition]) -> [ConceptDefinition] {
        guard !quotes.contains(where: { $0.id == concept.id }),
              quotes.count < maximumQuotedInsights else { return quotes }
        return quotes + [concept]
    }

    func responsePresentation(at responseIndex: Int) -> ResponsePresentationMetadata? {
        responsePresentations?.first { $0.responseIndex == responseIndex }
    }

    mutating func setResponsePresentation(
        _ presentation: ResponsePresentationMetadata
    ) {
        var presentations = responsePresentations ?? []
        presentations.removeAll { $0.responseIndex == presentation.responseIndex }
        presentations.append(presentation)
        responsePresentations = presentations
    }

    mutating func removeResponsePresentation(at responseIndex: Int) {
        responsePresentations?.removeAll { $0.responseIndex == responseIndex }
        if responsePresentations?.isEmpty == true {
            responsePresentations = nil
        }
    }
}

nonisolated struct ResponsePresentationMetadata: Codable, Equatable {
    let responseIndex: Int
    let showsThinking: Bool
    let thinkingSummary: [String]
    /// Actual elapsed preparation time before the first answer text. Missing in older saves.
    var thinkingDurationSeconds: TimeInterval? = nil
    /// The passages retrieval actually supplied for this answer, kept so **Show Thinking** can
    /// list them again after the fact. Optional because synthesized `Codable` decoding fails on a
    /// missing key rather than falling back to a property's default value, so presentations
    /// persisted before this field existed would otherwise stop decoding.
    var groundingSources: [GroundingSourceSummary]? = nil
    /// A small provenance disclosure for ordinary no-source answers. Optional so saved
    /// conversations written before this existed continue to decode.
    var evidenceBasis: ResponseEvidenceBasis? = nil
    /// Missing on historical responses, which predate explicit model failure outcomes.
    var outcome: ModelResponseOutcome? = nil
}

/// A saved top-level conversation canvas. This is in-memory prototype persistence.
nonisolated struct InquiryConversation: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String = "New Conversation"
    /// `true` for conversations that act as study topic containers.
    /// Study topics are distinct from regular conversations — they don't
    /// appear in Open Conversations and their detail view lists child
    /// conversations tagged with `studyTopicID`.
    /// Defaults to `false` so existing persisted data deserialises safely.
    var isStudyTopic: Bool = false
    /// Non-nil when this conversation lives inside a study topic.
    /// The value is the `id` of the parent topic (`InquiryConversation`).
    var studyTopicID: UUID? = nil
    /// Pinned conversations sort to the top of Recents and show a pin indicator.
    var isPinned: Bool = false
    var branches: [ChatBranch] = [ChatBranch(startingConcept: nil)]
    var promotedInsightIDs: [UUID] = []
    /// When this conversation was created — drives the "Date" filter's day-based grouping in
    /// Open Conversations. Defaults so existing persisted data without this field decodes safely.
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        title: String = "New Conversation",
        isStudyTopic: Bool = false,
        studyTopicID: UUID? = nil,
        isPinned: Bool = false,
        branches: [ChatBranch] = [ChatBranch(startingConcept: nil)],
        promotedInsightIDs: [UUID] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.isStudyTopic = isStudyTopic
        self.studyTopicID = studyTopicID
        self.isPinned = isPinned
        self.branches = branches
        self.promotedInsightIDs = promotedInsightIDs
        self.createdAt = createdAt
    }
}

extension InquiryConversation {
    /// The side menu's Current Topic label for a conversation started from a Home daily
    /// prompt, read from the root branch's persisted prompt source tag.
    var dailyPromptTopicTitle: String? {
        guard let context = branches.first(where: { $0.parentBranchID == nil })?.hiddenPromptContext else {
            return nil
        }
        if context.localizedCaseInsensitiveContains("<question of the day>") {
            return String(localized: "Question of the Day")
        }
        if context.localizedCaseInsensitiveContains("<today in history>") {
            return String(localized: "Today in History")
        }
        return nil
    }
}

/// Decides whether an otherwise new conversation contains user work worth retaining.
/// Empty drafts are intentionally ephemeral, but text, uploads, Insight context, and explicit
/// organization choices all make a conversation meaningful.
enum ConversationDraftRetention {
    /// A conversation started from a pinned prompt (Question of the Day, Today in History) that
    /// the user left before typing anything. The card that started it stays on Home, so the draft
    /// is recreated on demand rather than restored as a special empty-prompt conversation.
    static func isUntouchedPromptDraft(_ conversation: InquiryConversation) -> Bool {
        guard !conversation.isStudyTopic,
              conversation.studyTopicID == nil,
              !conversation.isPinned,
              conversation.promotedInsightIDs.isEmpty,
              conversation.branches.count == 1,
              let branch = conversation.branches.first,
              let pinned = branch.pinnedHeaderQuestion?.trimmingCharacters(in: .whitespacesAndNewlines),
              !pinned.isEmpty,
              conversation.title == pinned || conversation.title == "New Conversation" else {
            return false
        }
        return branch.parentBranchID == nil
            && branch.startingConcept == nil
            && branch.duplicatedResponse == nil
            && !branch.topQuestionSubmitted
            && branch.activeChatBlocks.isEmpty
            && branch.topQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && branch.topQuestionUploads.isEmpty
            && branch.bottomQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && branch.attachedConcepts.isEmpty
            && branch.branchContextConcepts.isEmpty
            && branch.compactedContext == nil
    }

    static func shouldKeep(
        _ conversation: InquiryConversation,
        transientAttachedConcept: ConceptDefinition? = nil,
        hasSavedInsights: Bool = false
    ) -> Bool {
        guard transientAttachedConcept == nil else { return true }
        if !hasSavedInsights, isUntouchedPromptDraft(conversation) { return false }
        guard !conversation.isStudyTopic,
              conversation.studyTopicID == nil,
              !conversation.isPinned,
              conversation.title == "New Conversation",
              conversation.promotedInsightIDs.isEmpty,
              !hasSavedInsights else {
            return true
        }

        return conversation.branches.contains { branch in
            branch.startingConcept != nil ||
            branch.duplicatedResponse?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ||
            branch.topQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ||
            !branch.topQuestionUploads.isEmpty ||
            branch.bottomQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ||
            !branch.attachedConcepts.isEmpty ||
            !branch.branchContextConcepts.isEmpty ||
            branch.compactedContext?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ||
            branch.hiddenPromptContext?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ||
            branch.pinnedHeaderQuestion?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ||
            branch.activeChatBlocks.contains(where: hasMeaningfulContent)
        }
    }

    nonisolated private static func hasMeaningfulContent(_ block: ChatBlock) -> Bool {
        switch block {
        case .text(let text):
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .user(let text, let concepts, let uploads):
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !concepts.isEmpty ||
            !uploads.isEmpty
        }
    }
}

/// Atomic handoff from an Insight Tree into an existing conversation. A Study Topic origin is
/// retained when present so canceling the quote can reopen that tree and restore its selection.
/// Opens a conversation's Insight Tree with one Node Concept selected (Home's Loose Thread).
struct ConversationNodeFocusRequest: Identifiable, Equatable {
    let id = UUID()
    let conversationID: UUID
    let nodeID: UUID
}

struct InsightConversationQuoteRequest: Identifiable, Equatable {
    let id: UUID
    let topicID: UUID?
    let conversationID: UUID
    let insight: ConceptDefinition

    init(
        id: UUID = UUID(),
        topicID: UUID? = nil,
        conversationID: UUID,
        insight: ConceptDefinition
    ) {
        self.id = id
        self.topicID = topicID
        self.conversationID = conversationID
        self.insight = insight
    }
}

/// Starts a fresh conversation with an Insight already attached to its composer.
struct NewConversationInsightQuoteRequest: Equatable {
    let insight: ConceptDefinition
    let topicID: UUID?

    init(insight: ConceptDefinition, topicID: UUID? = nil) {
        self.insight = insight
        self.topicID = topicID
    }
}

/// Requests reopening a Study Topic tree with a specific Insight selected.
struct StudyTopicTreeSelectionRequest: Identifiable, Equatable {
    let id: UUID
    let topicID: UUID
    let insightID: UUID

    init(id: UUID = UUID(), topicID: UUID, insightID: UUID) {
        self.id = id
        self.topicID = topicID
        self.insightID = insightID
    }
}

extension ChatBranch {
    /// Every Insight surfaced in these branches — starting, attached, and context concepts,
    /// quoted chips, and inline Insights in responses — deduplicated by term, in order.
    static func mentionedInsights(in branches: [ChatBranch]) -> [ConceptDefinition] {
        var seen = Set<String>()
        var result: [ConceptDefinition] = []
        func add(_ concept: ConceptDefinition) {
            if seen.insert(concept.word.lowercased()).inserted { result.append(concept) }
        }
        for branch in branches {
            ([branch.startingConcept].compactMap { $0 } + branch.attachedConcepts + branch.branchContextConcepts)
                .forEach(add)
            for block in branch.activeChatBlocks {
                switch block {
                case .user(_, let concepts, _):
                    concepts.forEach(add)
                case .text(let text):
                    InlineInsightMarkup.insights(in: text).forEach(add)
                }
            }
        }
        return result
    }

    /// Passage identity is the quote's ID: several excerpts from the same work stay distinct.
    static func quotedLibraryPassages(in branches: [ChatBranch]) -> [ConceptDefinition] {
        var seen = Set<UUID>()
        var result: [ConceptDefinition] = []
        func add(_ concept: ConceptDefinition) {
            guard concept.isLibraryQuote, seen.insert(concept.id).inserted else { return }
            result.append(concept)
        }
        for branch in branches {
            ([branch.startingConcept].compactMap { $0 } + branch.branchContextConcepts + branch.attachedConcepts)
                .forEach(add)
            for block in branch.activeChatBlocks {
                if case .user(_, let concepts, _) = block { concepts.forEach(add) }
            }
        }
        return result
    }

    /// Only bookmarked definitions belong in the tree. Saved definitions are authoritative;
    /// response markup may contain an older copy or ID.
    static func resolvedConversationInsights(
        in branches: [ChatBranch],
        savedInsights: [ConceptDefinition],
        manuallySavedIDs: Set<UUID>
    ) -> [ConceptDefinition] {
        var result: [ConceptDefinition] = []
        var seen = Set<UUID>()
        for mentioned in mentionedInsights(in: branches) where !mentioned.isLibraryQuote {
            let saved = savedInsights.first { $0.id == mentioned.id }
                ?? savedInsights.first { $0.word.caseInsensitiveCompare(mentioned.word) == .orderedSame }
            guard let resolved = saved else { continue }
            if seen.insert(resolved.id).inserted { result.append(resolved) }
        }
        for saved in savedInsights where manuallySavedIDs.contains(saved.id) && !saved.isLibraryQuote {
            if seen.insert(saved.id).inserted { result.append(saved) }
        }
        return result
    }
}

let questionCanceledResponseText = "Question canceled"

nonisolated enum ChatBlock: Hashable, Codable {
    /// A model-generated response card.
    case text(String)

    /// A submitted user question, including its quoted Insight chips and uploaded files.
    case user(String, [ConceptDefinition], [UploadedFile])

    // Earlier builds stored one optional quote as `_1`. It is still written as the first quote
    // so those builds can read new conversations; the full list is under `quotes`.
    private enum CodingKeys: String, CodingKey { case text, user }
    private enum TextKeys: String, CodingKey { case _0 }
    private enum UserKeys: String, CodingKey { case _0, _1, _2, quotes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.text) {
            let text = try c.nestedContainer(keyedBy: TextKeys.self, forKey: .text)
            self = .text(try text.decode(String.self, forKey: ._0))
            return
        }
        let user = try c.nestedContainer(keyedBy: UserKeys.self, forKey: .user)
        let quotes = try user.decodeIfPresent([ConceptDefinition].self, forKey: .quotes)
            ?? (try user.decodeIfPresent(ConceptDefinition.self, forKey: ._1)).map { [$0] }
            ?? []
        self = .user(
            try user.decode(String.self, forKey: ._0),
            quotes,
            try user.decode([UploadedFile].self, forKey: ._2)
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            var text = c.nestedContainer(keyedBy: TextKeys.self, forKey: .text)
            try text.encode(value, forKey: ._0)
        case .user(let question, let quotes, let uploads):
            var user = c.nestedContainer(keyedBy: UserKeys.self, forKey: .user)
            try user.encode(question, forKey: ._0)
            try user.encodeIfPresent(quotes.first, forKey: ._1)
            try user.encode(uploads, forKey: ._2)
            if quotes.count > 1 { try user.encode(quotes, forKey: .quotes) }
        }
    }
}
