//
//  StudyTopic.swift
//  Angrove-iOS
//

import Foundation

struct StudyTopic: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var description: String
    var files: [UploadedFile]
    /// When this topic was created — drives the "Date" filter's day-based grouping.
    /// Defaults so existing persisted data without this field decodes safely.
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        title: String = "",
        description: String = "",
        files: [UploadedFile] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.files = files
        self.createdAt = createdAt
    }
}

enum StudyTopicStore {
    private static let key = "aquinas.study-topics.v1"

    /// Decoded topics, kept in memory because many screens reload topics every time they appear.
    /// `save` is the only writer of this key, so it keeps the cache current.
    private static var cachedTopics: [StudyTopic]?

    static func load() -> [StudyTopic] {
        if let cachedTopics { return cachedTopics }
        let topics = UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([StudyTopic].self, from: $0) } ?? []
        cachedTopics = topics
        return topics
    }

    static func save(_ topics: [StudyTopic]) {
        cachedTopics = topics
        guard let data = try? JSONEncoder().encode(topics) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

/// Persists the last user-approved aggregate Insight Tree input for each Study Topic.
/// Keeping this snapshot separate from the live Insight Library ensures a topic tree changes
/// only after the user accepts the refresh prompt shown when entering that topic.
enum StudyTopicInsightTreeStore {
    private static let key = "aquinas.study-topic.insight-trees.v1"

    static func load() -> [String: [ConceptDefinition]] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let snapshots = try? JSONDecoder().decode(
                [String: [ConceptDefinition]].self,
                from: data
              ) else {
            return [:]
        }
        return snapshots
    }

    static func save(_ snapshots: [String: [ConceptDefinition]]) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

@MainActor
enum StudyTopicInsightTreeBuilder {
    /// Every bookmarked Insight from every conversation in the topic: those saved from the
    /// conversation, plus any bookmarked Insight that appears in its transcript (chips, inline
    /// Insights, branch concepts) however it was bookmarked.
    static func snapshot(
        topicID: UUID,
        conversations: [InquiryConversation],
        savedInsights: [ConceptDefinition],
        insightIDs: @MainActor (UUID) -> Set<UUID> = ConversationInsightMembershipStore.insightIDs(for:)
    ) -> [ConceptDefinition] {
        let topicConversations = conversations.filter { $0.studyTopicID == topicID }
        var topicInsightIDs = Set<UUID>()
        var topicInsightTerms = Set<String>()
        for conversation in topicConversations {
            topicInsightIDs.formUnion(insightIDs(conversation.id))
            for insight in ChatBranch.mentionedInsights(in: conversation.branches) {
                topicInsightIDs.insert(insight.id)
                topicInsightTerms.insert(term(insight.word))
            }
        }

        return savedInsights
            .filter { topicInsightIDs.contains($0.id) || topicInsightTerms.contains(term($0.word)) }
            .uniquedByWord()
            .sorted {
                $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending
            }
    }

    private static func term(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
