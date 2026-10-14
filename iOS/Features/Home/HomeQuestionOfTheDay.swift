//
//  HomeQuestionOfTheDay.swift
//  Angrove-iOS
//

import Foundation
import WidgetKit

enum HomeQuestionOfTheDayStore {
    private static let key = "aquinas.home.questionOfTheDay.v1"

    static func load() -> HomeQuestionOfTheDay? {
        guard let question = PrivatePreferences.standard.decoded(HomeQuestionOfTheDay.self, forKey: key) else {
            return nil
        }
        publishToWidget(question)
        return question
    }

    static func loadPending(at date: Date = Date()) -> HomeQuestionOfTheDay? {
        guard let question = load(), question.isPending(at: date) else {
            return nil
        }
        return question
    }

    static func isEligibleForRefresh(
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        nextEligibleRefreshDate(calendar: calendar) <= date
    }

    static func nextEligibleRefreshDate(
        calendar: Calendar = .current
    ) -> Date {
        guard let question = load() else { return .distantPast }
        return question.nextEligibleRefreshDate(calendar: calendar)
    }

    static func save(_ question: HomeQuestionOfTheDay) {
        guard let data = try? JSONEncoder().encode(question) else { return }
        PrivatePreferences.standard.set(data, forKey: key)
        publishToWidget(question)
    }

    /// Refresh existing widget views after an app update, even if the question is unchanged.
    static func reloadWidgetTimeline() {
        WidgetCenter.shared.reloadTimelines(ofKind: DailyQuestionWidgetStore.kind)
    }

    private static func publishToWidget(_ question: HomeQuestionOfTheDay) {
        guard HomeQuestionOfTheDay.isValidQuestionText(question.question),
              DailyQuestionWidgetStore.save(question.question) else { return }
        reloadWidgetTimeline()
    }
}

struct DailyQuestionSource {
    let conversation: InquiryConversation
    let context: ConversationContext
    let insights: [ConceptDefinition]
}

enum DailyQuestionSourceSelector {
    static func select(
        conversations: [InquiryConversation],
        savedInsights: [ConceptDefinition]
    ) -> DailyQuestionSource? {
        var generator = SystemRandomNumberGenerator()
        return select(
            conversations: conversations,
            savedInsights: savedInsights,
            using: &generator
        )
    }

    static func select<Generator: RandomNumberGenerator>(
        conversations: [InquiryConversation],
        savedInsights: [ConceptDefinition],
        using generator: inout Generator
    ) -> DailyQuestionSource? {
        // Limit the window before checking transcripts so older conversations cannot leak in.
        // Shuffling gives every eligible conversation in that window the same chance.
        let recentConversations = conversations
            .filter { !$0.isStudyTopic }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(5)
            .shuffled(using: &generator)

        for conversation in recentConversations {
            for branch in conversation.branches.reversed() {
                var transcript: [ChatBlock] = []
                let topQuestion = branch.topQuestionText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                if branch.topQuestionSubmitted, !topQuestion.isEmpty {
                    transcript.append(
                        .user(topQuestion, branch.branchContextConcept, branch.topQuestionUploads)
                    )
                }
                transcript.append(contentsOf: branch.activeChatBlocks)

                let hasQuestion = transcript.contains {
                    guard case .user(let text, _, _) = $0 else { return false }
                    return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                let hasAnswer = transcript.contains {
                    guard case .text(let text) = $0 else { return false }
                    return text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 80
                }
                guard hasQuestion, hasAnswer else { continue }

                return DailyQuestionSource(
                    conversation: conversation,
                    context: ConversationContext(
                        compactedContext: branch.compactedContext,
                        transcript: transcript
                    ),
                    insights: relevantInsights(
                        for: conversation,
                        savedInsights: savedInsights
                    )
                )
            }
        }
        return nil
    }

    private static func relevantInsights(
        for conversation: InquiryConversation,
        savedInsights: [ConceptDefinition]
    ) -> [ConceptDefinition] {
        var conceptWords = Set<String>()
        for branch in conversation.branches {
            for concept in [
                branch.startingConcept,
                branch.attachedConcept,
                branch.branchContextConcept,
            ].compactMap({ $0 }) {
                conceptWords.insert(concept.word.lowercased())
            }
            for block in branch.activeChatBlocks {
                if case .user(_, let concept?, _) = block {
                    conceptWords.insert(concept.word.lowercased())
                }
            }
        }

        var seenWords = Set<String>()
        return savedInsights.filter { insight in
            let key = insight.word.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).lowercased()
            guard !key.isEmpty,
                  conceptWords.contains(key),
                  !seenWords.contains(key) else {
                return false
            }
            seenWords.insert(key)
            return true
        }
    }
}

/// Picks a conversation to scope Home's conversation-based discovery sections to (Loose Thread,
/// Terms You Glossed Over, Your Quote). Excludes Study Topics and prefers the active conversation,
/// then the most recently created, without the daily question's random selection or transcript
/// requirement.
enum HomeSectionSourceSelector {
    static func selectConversationID(
        conversations: [InquiryConversation],
        activeConversationID: UUID?
    ) -> UUID? {
        conversations
            .filter { !$0.isStudyTopic }
            .sorted { left, right in
                let leftIsActive = left.id == activeConversationID
                let rightIsActive = right.id == activeConversationID
                if leftIsActive != rightIsActive { return leftIsActive }
                return left.createdAt > right.createdAt
            }
            .first?.id
    }
}
