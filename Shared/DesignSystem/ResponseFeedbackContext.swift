//
//  ResponseFeedbackSheet.swift
//  Angrove-iOS
//

import SwiftUI

/// What a thumbs down can send along with the person's note: just the flagged response and the
/// question that prompted it, never the rest of the chat. Nothing here is sent unless the person
/// turns on the "Include" option in the feedback sheet, which shows this text first.
struct ResponseFeedbackReport {
    var question: String
    var response: String
}

extension EnvironmentValues {
    /// Set only on the latest response of a conversation; `nil` hides the thumbs down.
    @Entry var responseFeedbackReport: (() -> ResponseFeedbackReport)? = nil
}

extension ChatBranch {
    /// The flagged response and the user question immediately before it.
    func feedbackReport(flaggedResponseIndex: Int) -> ResponseFeedbackReport {
        var question = topQuestionText
        for block in activeChatBlocks.prefix(flaggedResponseIndex).reversed() {
            if case .user(let text, _, _) = block { question = text; break }
        }
        var response = ""
        if activeChatBlocks.indices.contains(flaggedResponseIndex),
           case .text(let text) = activeChatBlocks[flaggedResponseIndex] {
            response = text
        }
        return ResponseFeedbackReport(question: question, response: response)
    }
}
