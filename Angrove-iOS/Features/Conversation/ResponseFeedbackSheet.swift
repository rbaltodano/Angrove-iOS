//
//  ResponseFeedbackSheet.swift
//  Angrove-iOS
//

import SwiftUI

/// What a thumbs down sends along with the person's note: just the flagged response and the
/// question that prompted it, never the rest of the chat.
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

/// Asks what was wrong with a response after a thumbs down and sends it, with the response and its question,
/// to the bug report inbox.
struct ResponseFeedbackSheet: View {
    /// The flagged response and its question to attach; `nil` sends only the note.
    var report: ResponseFeedbackReport? = nil
    /// Called once the report is sent, so the thumbs down can stay selected.
    var onSent: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var feedback = ""
    @State private var isSending = false
    @State private var hasFailed = false
    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !isSending && !feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("What went wrong with this response? Your note, basic app details\(report == nil ? "" : ", this response, and the question before it") go to the Angrove team. Please leave out anything private.")
                    .settingsText(.paragraph)
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
                    .fixedSize(horizontal: false, vertical: true)

                TextEditor(text: $feedback)
                    .settingsText(.control)
                    .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .frame(minHeight: 140, maxHeight: 220)
                    .background(AngroveTheme.Colors.canvasSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                isFocused ? AngroveTheme.Colors.accentGreen : AngroveTheme.Colors.controlBorder,
                                lineWidth: isFocused ? 1.5 : 1
                            )
                    }
                    .overlay(alignment: .topLeading) {
                        if feedback.isEmpty {
                            Text("Tell us what was wrong or unhelpful")
                                .settingsText(.control)
                                .foregroundStyle(AngroveTheme.Colors.paragraphText.opacity(0.55))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel("What went wrong with this response")

                if hasFailed {
                    Text("We couldn’t send your feedback. Check your connection and try again, or email bugreport@angrove.app directly.")
                        .settingsText(.paragraph)
                        .foregroundStyle(AngroveTheme.Colors.accentRed)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .background(AngroveTheme.Colors.canvas.ignoresSafeArea())
            .navigationTitle("Response Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSending ? "Sending…" : "Send", action: send)
                        .disabled(!canSend)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { isFocused = true }
    }

    private func send() {
        let info = Bundle.main.infoDictionary
        var fields = [
            "_subject": "Angrove response feedback (thumbs down)",
            "description": feedback.trimmingCharacters(in: .whitespacesAndNewlines),
            "steps": "Thumbs down on a model response",
            "app_version": info?["CFBundleShortVersionString"] as? String ?? "Unknown",
            "app_build": info?["CFBundleVersion"] as? String ?? "Unknown",
            "operating_system": ProcessInfo.processInfo.operatingSystemVersionString
        ]
        if let report {
            fields["flagged_question"] = report.question
            fields["flagged_response"] = report.response
        }
        isSending = true
        hasFailed = false
        Task { @MainActor in
            do {
                try await BugReportSubmission.send(fields: fields)
                onSent()
                dismiss()
            } catch {
                hasFailed = true
                isSending = false
            }
        }
    }
}
