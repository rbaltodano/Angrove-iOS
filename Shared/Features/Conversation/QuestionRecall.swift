//
//  QuestionRecall.swift
//  Angrove-iOS
//

import Foundation

extension ChatBranch {
    /// Questions the user has sent in this branch, oldest first.
    var submittedQuestions: [String] {
        var questions: [String] = []
        if topQuestionSubmitted { questions.append(topQuestionText) }
        for case .user(let text, _, _) in activeChatBlocks { questions.append(text) }
        return questions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

/// A recalled question the field can show before it commits to it, so an interactive swipe
/// can be abandoned without moving the recall position.
struct QuestionRecallStep {
    let text: String
    let commit: () -> Void
}

/// Steps the question field through earlier questions. Recall only replaces an empty
/// field or an unedited recalled question, so a typed draft is never overwritten.
struct QuestionRecall {
    private var position: Int?
    private var recalledText: String?

    /// Returns the next older question, or nil when the field should stay as it is.
    mutating func older(in history: [String], current: String) -> String? {
        guard !history.isEmpty, canRecall(over: current) else { return nil }
        let next = position.map { $0 - 1 } ?? history.count - 1
        guard next >= 0 else { return nil }
        return select(next, in: history)
    }

    /// Returns the next newer question, or an empty string after the newest one.
    mutating func newer(in history: [String], current: String) -> String? {
        guard canRecall(over: current), let position, position < history.count else { return nil }
        guard position + 1 < history.count else {
            reset()
            return ""
        }
        return select(position + 1, in: history)
    }

    mutating func reset() {
        position = nil
        recalledText = nil
    }

    private mutating func canRecall(over current: String) -> Bool {
        if current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // A cleared field starts again from the newest question.
            reset()
            return true
        }
        return position != nil && current == recalledText
    }

    private mutating func select(_ index: Int, in history: [String]) -> String {
        position = index
        recalledText = history[index]
        return history[index]
    }
}
