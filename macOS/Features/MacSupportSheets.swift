import SwiftUI

/// The iPhone's bug report form. It is the app's one outbound request and sends only what the
/// person types, an optional reply email, and the app and macOS versions.
struct MacBugReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var steps = ""
    @State private var replyEmail = ""
    @State private var isSending = false
    @State private var status: String?
    @State private var hasSent = false

    private var canSend: Bool {
        !isSending && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            MacPageHeading(title: "Report a Problem")
            Text("Tell us what went wrong. Angrove runs on your Mac; sending this report is the one exception. It shares what you write below plus your app version, build number, and macOS version. Nothing is sent unless you choose Send Report. Please leave out passwords or private conversations.")
                .paragraphFont()
                .foregroundStyle(AngroveTheme.Colors.paragraphText)
                .fixedSize(horizontal: false, vertical: true)
            field("What happened?", text: $description, minHeight: 110)
            field("Steps to reproduce (optional)", text: $steps, minHeight: 70)
            VStack(alignment: .leading, spacing: 6) {
                Text("Your email (optional, for a reply)").font(AngroveTheme.Typography.uiLabel)
                    .foregroundStyle(AngroveTheme.Colors.placeholderText)
                TextField("you@example.com", text: $replyEmail)
                    .macPlainField()
                    .textContentType(.emailAddress)
            }
            if let status {
                Text(status)
                    .font(AngroveTheme.Typography.body)
                    .foregroundStyle(hasSent ? AngroveTheme.Colors.lightGreen : AngroveTheme.Colors.paragraphText)
            }
            HStack {
                Spacer()
                Button { dismiss() } label: { BlurSwapText(hasSent ? "Done" : "Cancel") }
                    .keyboardShortcut(.cancelAction)
                    .pulsesOnChange(of: hasSent)
                if !hasSent {
                    Button(action: send) { BlurSwapText(isSending ? "Sending…" : "Send Report") }
                        .pulsesOnChange(of: isSending)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSend)
                }
            }
        }
        .padding(28)
        .frame(width: 520)
        .background(AngroveTheme.Colors.canvas)
    }

    private func field(_ title: String, text: Binding<String>, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(AngroveTheme.Typography.uiLabel).foregroundStyle(AngroveTheme.Colors.placeholderText)
            TextEditor(text: text)
                .font(AngroveTheme.Typography.body)
                .scrollContentBackground(.hidden)
                .focusEffectDisabled()
                .tint(AngroveTheme.Colors.lightGreen)
                .frame(minHeight: minHeight)
        }
    }

    private func send() {
        let info = Bundle.main.infoDictionary
        let trimmedSteps = steps.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = replyEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        var fields = [
            "_subject": "Angrove bug report (Mac)",
            "description": description.trimmingCharacters(in: .whitespacesAndNewlines),
            "steps": trimmedSteps.isEmpty ? "Not provided" : trimmedSteps,
            "app_version": info?["CFBundleShortVersionString"] as? String ?? "Unknown",
            "app_build": info?["CFBundleVersion"] as? String ?? "Unknown",
            "operating_system": "macOS " + ProcessInfo.processInfo.operatingSystemVersionString,
        ]
        if !email.isEmpty { fields["_replyto"] = email }
        isSending = true
        status = "Sending your report…"
        Task {
            do {
                try await BugReportSubmission.send(fields: fields)
                hasSent = true
                status = "Thanks. Your report was sent."
            } catch {
                status = "We couldn’t send your report. Check your connection and try again, or email bugreport@angrove.app directly."
            }
            isSending = false
        }
    }
}

/// Models, software, fonts and Library editions that ship inside Angrove, with their licenses.
struct MacLicensesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var license: BundledLicense?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                if license != nil {
                    Button("Licenses", systemImage: "chevron.left") { license = nil }
                        .buttonStyle(.plain)
                        .foregroundStyle(AngroveTheme.Colors.lightGreen)
                        .macBackButtonEntrance()
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let license {
                        MacPageHeading(title: String(localized: license.title))
                        ForEach(Array(license.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            Text(paragraph).paragraphFont().foregroundStyle(AngroveTheme.Colors.paragraphText)
                                .textSelection(.enabled)
                        }
                    } else {
                        MacPageHeading(title: "Licenses")
                        Text("Angrove is built on openly licensed models, open-source software, open fonts, and public-domain Library texts. Thank you to their authors.")
                            .paragraphFont().foregroundStyle(AngroveTheme.Colors.paragraphText)
                        section("Models", AcknowledgedWork.models)
                        section("Software", AcknowledgedWork.software)
                        section("Fonts", AcknowledgedWork.fonts)
                        section("Library", AcknowledgedWork.library)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(28)
        .frame(width: 560, height: 620)
        .background(AngroveTheme.Colors.canvas)
    }

    private func section(_ title: String, _ works: [AcknowledgedWork]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MacPageHeading(title: title)
            ForEach(works) { work in
                Button { license = work.license } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(work.name).font(AngroveTheme.Typography.uiSubheading)
                                .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                            Text(work.detail).font(AngroveTheme.Typography.settingsDetail)
                                .foregroundStyle(AngroveTheme.Colors.placeholderText)
                        }
                        Spacer()
                        Text(work.license.title).font(AngroveTheme.Typography.settingsDetail)
                            .foregroundStyle(AngroveTheme.Colors.lightGreen)
                    }
                    .multilineTextAlignment(.leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
