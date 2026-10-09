//
//  ResponseFeedbackSheet.swift
//  Angrove-iOS
//

import SwiftUI

extension EnvironmentValues {
    /// Builds the chat log attached to thumbs-down feedback. Empty where no chat is available.
    @Entry var responseFeedbackTranscript: () -> String = { "" }
}

extension ChatBranch {
    /// The branch as plain text, with the flagged response marked. Attachments appear by name only.
    func feedbackTranscript(flaggedResponseIndex: Int, characterLimit: Int = 60_000) -> String {
        var lines: [String] = []
        if !topQuestionText.isEmpty { lines.append("User: \(topQuestionText)") }
        for (index, block) in activeChatBlocks.enumerated() {
            switch block {
            case .text(let text):
                let marker = index == flaggedResponseIndex ? " [THUMBS DOWN]" : ""
                lines.append("Angrove\(marker): \(text)")
            case .user(let text, let concept, let files):
                var line = "User: \(text)"
                if let concept { line += " (quoting: \(concept.word))" }
                if !files.isEmpty { line += " (attached: \(files.map(\.name).joined(separator: ", ")))" }
                lines.append(line)
            }
        }
        let log = lines.joined(separator: "\n\n")
        // Keep the most recent exchange if a very long chat has to be trimmed.
        return log.count > characterLimit ? "…" + String(log.suffix(characterLimit)) : log
    }
}

/// Asks what was wrong with a response after a thumbs down and sends it, with the chat log,
/// to the bug report inbox.
struct ResponseFeedbackSheet: View {
    /// The chat log to attach; empty when none is available.
    var transcript: String = ""
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
                Text("What went wrong with this response? Your note, basic app details\(transcript.isEmpty ? "" : ", and this conversation’s chat log") go to the Angrove team. Please leave out anything private.")
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
        if !transcript.isEmpty { fields["chat_log"] = transcript }
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
