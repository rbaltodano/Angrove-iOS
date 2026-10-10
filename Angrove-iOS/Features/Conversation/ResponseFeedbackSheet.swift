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

/// Asks what was wrong with a response after a thumbs down and sends the note to the bug report
/// inbox. The flagged response and its question are attached only when the person switches on
/// "Include this response and its question", which is off by default and previews the exact text.
struct ResponseFeedbackSheet: View {
    /// The flagged response and its question the person may choose to attach; `nil` offers no option.
    var report: ResponseFeedbackReport? = nil
    /// Called once the report is sent, so the thumbs down can stay selected.
    var onSent: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var feedback = ""
    /// Off by default: the response and its question leave the device only if this is turned on.
    @State private var includesResponse = false
    @State private var isSending = false
    @State private var hasFailed = false
    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !isSending && !feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            // Scrolls so the attachment preview and keyboard fit on small phones.
            ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Report a Bug")
                    .font(AngroveTheme.Typography.settingsDetailTitle)
                    .foregroundStyle(AngroveTheme.Colors.headingText)
                    .lineSpacing(AngroveTheme.Typography.settingsGuideTitleLineSpacing)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("What went wrong with this response? This app runs on your device. Sending this report is the one exception. It shares your note plus your app version, build number, and iOS version. Nothing is sent unless you tap Send Report. Please leave out anything private.")
                    .settingsGuideParagraph()
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
                    .fixedSize(horizontal: false, vertical: true)

                TextEditor(text: $feedback)
                    .font(AngroveTheme.Typography.settingsGuideParagraph)
                    .lineSpacing(AngroveTheme.Typography.settingsGuideLineSpacing)
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
                                isFocused ? AngroveTheme.Colors.lightGreen : AngroveTheme.Colors.controlBorder,
                                lineWidth: isFocused ? 1.5 : 1
                            )
                    }
                    .overlay(alignment: .topLeading) {
                        if feedback.isEmpty {
                            Text("Tell us what was wrong or unhelpful")
                                .font(AngroveTheme.Typography.settingsGuideParagraph)
                                .lineSpacing(AngroveTheme.Typography.settingsGuideLineSpacing)
                                .foregroundStyle(AngroveTheme.Colors.paragraphText.opacity(0.55))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel("What went wrong with this response")

                if let report {
                    attachmentOption(report)
                }

                if hasFailed {
                    Text("We couldn’t send your feedback. Check your connection and try again, or email bugreport@angrove.app directly.")
                        .font(AngroveTheme.Typography.settingsGuideParagraph)
                        .lineSpacing(AngroveTheme.Typography.settingsGuideLineSpacing)
                        .foregroundStyle(AngroveTheme.Colors.accentRed)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AngroveTheme.Colors.canvas.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSending ? "Sending…" : "Send Report", action: send)
                        .disabled(!canSend)
                }
            }
        }
        .presentationDetents([.large])
    }

    /// The opt-in to attach the flagged response and its question, with the exact text shown
    /// while the option is on so the person knows what would be sent.
    private func attachmentOption(_ report: ResponseFeedbackReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $includesResponse) {
                Text("Include this response and the question before it")
                    .settingsText(.control)
                    .lineSpacing(AngroveTheme.Typography.settingsGuideLineSpacing)
                    .foregroundStyle(AngroveTheme.Colors.primaryReadable)
            }
            .tint(AngroveTheme.Colors.lightGreen)

            if includesResponse {
                Text("This text will be sent with your report:")
                    .settingsGuideParagraph()
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
                ScrollView {
                    Text("Question\n\(report.question)\n\nResponse\n\(report.response)")
                        .font(AngroveTheme.Typography.settingsGuideParagraph)
                        .lineSpacing(AngroveTheme.Typography.settingsGuideLineSpacing)
                        .foregroundStyle(AngroveTheme.Colors.paragraphText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .frame(maxHeight: 140)
                .background(AngroveTheme.Colors.canvasSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AngroveTheme.Colors.controlBorder, lineWidth: 1)
                }
            }
        }
        .animation(.default, value: includesResponse)
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
        if includesResponse, let report {
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
