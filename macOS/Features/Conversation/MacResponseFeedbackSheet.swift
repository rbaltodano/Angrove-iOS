import SwiftUI

/// Only the note and version metadata are sent unless the person explicitly includes the turn.
struct MacResponseFeedbackSheet: View {
    let report: ResponseFeedbackReport?
    var onSent: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var feedback = ""
    @State private var includesResponse = false
    @State private var isSending = false
    @State private var hasFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            MacPageHeading(title: "Report a Response")
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("What went wrong with this response? Sending this report shares your note plus your app version, build number, and macOS version. Nothing is sent unless you choose Send Report. Please leave out anything private.")
                        .paragraphFont()
                    TextEditor(text: $feedback)
                        .font(AngroveTheme.Typography.body)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(height: 150)
                        .background(AngroveTheme.Colors.canvasSecondary, in: RoundedRectangle(cornerRadius: AngroveTheme.Spacing.smallCardRadius))
                        .accessibilityLabel("What went wrong with this response")
                    if let report {
                        Toggle("Include this response and the question before it", isOn: $includesResponse)
                        if includesResponse {
                            Text("This text will be sent with your report:").paragraphFont()
                            Text("Question\n\(report.question)\n\nResponse\n\(report.response)")
                                .paragraphFont()
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(AngroveTheme.Colors.canvasSecondary, in: RoundedRectangle(cornerRadius: AngroveTheme.Spacing.smallCardRadius))
                        }
                    }
                    if hasFailed {
                        Text("We couldn’t send your feedback. Check your connection and try again, or email bugreport@angrove.app directly.")
                            .paragraphFont()
                            .foregroundStyle(AngroveTheme.Colors.accentRed)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(isSending)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSending)
                Button(isSending ? "Sending…" : "Send Report", action: send)
                    .disabled(isSending || feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .font(AngroveTheme.Typography.body)
        .foregroundStyle(AngroveTheme.Colors.paragraphText)
        .tint(AngroveTheme.Colors.lightGreen)
        .padding(28)
        .frame(width: 520, height: 580)
        .background(AngroveTheme.Colors.canvas)
        .interactiveDismissDisabled(isSending)
    }

    private func send() {
        guard !isSending, !feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let fields = MacResponseFeedbackSubmission.fields(note: feedback, report: report, includesResponse: includesResponse)
        isSending = true
        hasFailed = false
        Task {
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

enum MacResponseFeedbackSubmission {
    static func fields(note: String, report: ResponseFeedbackReport?, includesResponse: Bool) -> [String: String] {
        let info = Bundle.main.infoDictionary
        var fields = [
            "_subject": "Angrove response feedback (thumbs down)",
            "description": note.trimmingCharacters(in: .whitespacesAndNewlines),
            "steps": "Thumbs down on a model response",
            "app_version": info?["CFBundleShortVersionString"] as? String ?? "Unknown",
            "app_build": info?["CFBundleVersion"] as? String ?? "Unknown",
            "operating_system": "macOS " + ProcessInfo.processInfo.operatingSystemVersionString
        ]
        if includesResponse, let report {
            fields["flagged_question"] = report.question
            fields["flagged_response"] = report.response
        }
        return fields
    }
}
