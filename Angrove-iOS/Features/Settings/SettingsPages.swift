//
//  SettingsPages.swift
//  Angrove-iOS
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct AppearanceSettingsView: View {
    @Binding var colorSchemeOverride: ColorScheme?
    @AppStorage(SettingsStorageKey.conversationBackground) private var conversationBackground: CanvasBackgroundOption = .system
    @AppStorage(SettingsStorageKey.insightTreeBackground) private var insightTreeBackground: CanvasBackgroundOption = .system

    private var selectedAppearance: AppearanceOption {
        switch colorSchemeOverride {
        case .light: .light
        case .dark: .dark
        default: .system
        }
    }

    var body: some View {
        SettingsDetailScaffold(title: "Appearance") {
            VStack(alignment: .leading, spacing: 24) {
                SettingsControlCard {
                    SettingsLabeledControl(title: "Color Scheme") {
                        HStack(spacing: 8) {
                            ForEach(AppearanceOption.allCases) { option in
                                AppearanceButton(
                                    option: option,
                                    isSelected: option == selectedAppearance
                                ) {
                                    SettingsHaptics.playSelection()
                                    withAnimation(.springQuick) {
                                        colorSchemeOverride = option.colorScheme
                                    }
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Backgrounds")
                        .font(AngroveTheme.Typography.settingsHeading)
                        .foregroundStyle(AngroveTheme.Colors.headingText)

                    VStack(spacing: 12) {
                        BackgroundSettingsCard(title: "Conversation", surface: .conversation, selection: $conversationBackground)
                        BackgroundSettingsCard(title: "Insight Tree", surface: .insightTree, selection: $insightTreeBackground)
                    }
                }

                AppIconSettingsCard()
            }
        }
    }
}

struct AppExperienceSettingsView: View {
    @AppStorage(SettingsStorageKey.defaultStartScreen)
    private var defaultStartScreen: DefaultStartScreenOption = .home
    @AppStorage(SettingsStorageKey.hapticFeedback)
    private var hapticFeedback = true

    let onReset: () -> Void
    @State private var showsResetConfirmation = false

    var body: some View {
        SettingsDetailScaffold(title: "App Experience") {
            VStack(alignment: .leading, spacing: 24) {
                SettingsControlCard {
                    SettingsChoiceRow(
                        title: "Default Start Screen",
                        selection: $defaultStartScreen,
                        options: Array(DefaultStartScreenOption.allCases)
                    )

                    SettingsToggleRow(
                        title: "Haptic Feedback",
                        isOn: $hapticFeedback
                    )
                }

                SettingsControlCard {
                    Button(role: .destructive) {
                        showsResetConfirmation = true
                    } label: {
                        Text("Reset Settings")
                            .settingsText(.label)
                            .foregroundStyle(AngroveTheme.Colors.accentRed)
                            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .confirmationDialog(
            "Reset all settings?",
            isPresented: $showsResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Settings", role: .destructive) {
                onReset()
                defaultStartScreen = .home
                hapticFeedback = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Conversations, memories, Study Topics, and Insights will not be deleted.")
        }
    }
}

struct NotificationSettingsView: View {
    @AppStorage(SettingsStorageKey.dailyQuestionNotifications)
    private var dailyQuestionNotifications = false
    @AppStorage(SettingsStorageKey.completedResponseNotifications)
    private var completedResponseNotifications = false
    @AppStorage(SettingsStorageKey.dailyQuestionReminderTime)
    private var dailyQuestionReminderSeconds = 9.0 * 60.0 * 60.0

    var body: some View {
        SettingsDetailScaffold(title: "Notifications") {
            SettingsControlCard {
                SettingsToggleRow(
                    title: "Question of the Day",
                    detail: "Receive one daily reminder.",
                    isOn: $dailyQuestionNotifications
                )

                if dailyQuestionNotifications {
                    SettingsLabeledControl(title: "Reminder Time") {
                        DatePicker(
                            "Reminder Time",
                            selection: reminderTime,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .tint(AngroveTheme.Colors.darkGreen)
                    }
                }

                SettingsToggleRow(
                    title: "Completed Responses",
                    detail: "Notify me when an answer finishes outside the app.",
                    isOn: $completedResponseNotifications
                )
            }
        }
        .onChange(of: dailyQuestionNotifications) { _, isEnabled in
            Task {
                await updateDailyQuestionNotifications(isEnabled: isEnabled)
            }
        }
        .onChange(of: completedResponseNotifications) { _, isEnabled in
            guard isEnabled else { return }
            Task {
                let granted = await AngroveSystemNotifications.requestAuthorization()
                if !granted {
                    completedResponseNotifications = false
                }
            }
        }
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.startOfDay(for: Date())
                    .addingTimeInterval(dailyQuestionReminderSeconds)
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                dailyQuestionReminderSeconds =
                    Double((components.hour ?? 9) * 60 * 60 + (components.minute ?? 0) * 60)
                Task {
                    await AngroveSystemNotifications.scheduleDailyQuestionReminder(
                        secondsFromMidnight: dailyQuestionReminderSeconds
                    )
                }
            }
        )
    }

    @MainActor
    private func updateDailyQuestionNotifications(isEnabled: Bool) async {
        if isEnabled {
            let granted = await AngroveSystemNotifications.requestAuthorization()
            guard granted else {
                dailyQuestionNotifications = false
                return
            }
            await AngroveSystemNotifications.scheduleDailyQuestionReminder(
                secondsFromMidnight: dailyQuestionReminderSeconds
            )
        } else {
            AngroveSystemNotifications.removeDailyQuestionReminder()
        }
    }
}

struct PrivacyAndDataSettingsView: View {
    @AppStorage(SettingsStorageKey.appLock)
    private var appLock = false
    @AppStorage(SettingsStorageKey.appLockGracePeriod)
    private var appLockGracePeriod: AppLockGracePeriodOption = .immediately
    @State private var exportDocument: AngroveConversationDocument?
    @State private var isExportingConversations = false
    @State private var isImportingConversations = false
    @State private var pendingImport: PendingConversationImport?
    @State private var dataTransferError: String?
    @State private var showsClearInsightTreeConfirmation = false
    var onClearInsightTree: () -> Void = {}

    var body: some View {
        SettingsDetailScaffold(title: "Privacy & Data") {
            VStack(alignment: .leading, spacing: 24) {
                SettingsSubsection(title: "Security") {
                    SettingsToggleRow(title: "App Lock", isOn: $appLock)

                    if appLock {
                        SettingsChoiceRow(
                            title: "Lock Grace Period",
                            selection: $appLockGracePeriod,
                            options: Array(AppLockGracePeriodOption.allCases)
                        )
                    }
                }

                SettingsSubsection(title: "Data Controls") {
                    Text("Your saved personal data is fully encrypted on this device. Conversation exports are readable JSON files; anyone with an exported file can read it.")
                        .settingsText(.label)
                        .foregroundStyle(AngroveTheme.Colors.paragraphText)

                    Button(action: exportConversations) {
                        SettingsNavigationLabel(title: "Export Conversations")
                    }
                    .buttonStyle(.plain)

                    Button {
                        isImportingConversations = true
                    } label: {
                        SettingsNavigationLabel(title: "Import Conversations")
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        showsClearInsightTreeConfirmation = true
                    } label: {
                        Text("Clear Insight Tree")
                            .settingsText(.label)
                            .foregroundStyle(AngroveTheme.Colors.accentRed)
                            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    SettingsUnavailableActionRow(title: "Delete All Conversations", isDestructive: true)
                    SettingsUnavailableActionRow(title: "Delete Memories", isDestructive: true)
                    SettingsUnavailableActionRow(title: "Delete All App Data", isDestructive: true)
                }
            }
        }
        .confirmationDialog(
            "Clear the Insight Tree?",
            isPresented: $showsClearInsightTreeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Insight Tree", role: .destructive, action: onClearInsightTree)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every saved Insight and the whole tree on this device. Conversations are kept. This can’t be undone. Fully quit and reopen Angrove afterward.")
        }
        .fileExporter(
            isPresented: $isExportingConversations,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Angrove Conversations"
        ) { result in
            if case .failure(let error) = result {
                dataTransferError = error.localizedDescription
            }
            exportDocument = nil
        }
        .confirmationDialog(
            "Replace Your Conversations?",
            isPresented: Binding(
                get: { pendingImport != nil },
                set: { if !$0 { pendingImport = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingImport
        ) { pending in
            Button("Replace Conversations", role: .destructive) { commitImport(pending) }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: { pending in
            Text(pending.message)
        }
        .fileImporter(
            isPresented: $isImportingConversations,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            importConversations(from: result)
        }
        .alert(
            "Couldn’t Transfer Conversations",
            isPresented: Binding(
                get: { dataTransferError != nil },
                set: { if !$0 { dataTransferError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(dataTransferError ?? "Please try again.")
        }
    }

    private func exportConversations() {
        Task {
            do {
                exportDocument = AngroveConversationDocument(data: try await InquiryPersistenceStore.exportDataAsync())
                isExportingConversations = true
            } catch { dataTransferError = error.localizedDescription }
        }
    }

    private func importConversations(from result: Result<[URL], any Error>) {
        Task {
            do {
                guard let url = try result.get().first else { return }
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                let data = try await Task.detached(priority: .utility) { try Data(contentsOf: url) }.value
                let incoming = try await Task.detached(priority: .utility) {
                    try InquirySnapshotFileStore.decodeImport(data).conversations.count
                }.value
                pendingImport = PendingConversationImport(
                    data: data,
                    incomingCount: incoming,
                    currentCount: InquiryPersistenceStore.load()?.conversations.count ?? 0
                )
            } catch { dataTransferError = error.localizedDescription }
        }
    }

    private func commitImport(_ pending: PendingConversationImport) {
        pendingImport = nil
        Task {
            do {
                let snapshot = try await InquiryPersistenceStore.importDataAsync(pending.data)
                NotificationCenter.default.post(name: .angroveConversationStoreDidImport, object: snapshot)
            } catch { dataTransferError = error.localizedDescription }
        }
    }
}

/// A decoded export awaiting the person's confirmation before it replaces their conversations.
private struct PendingConversationImport {
    let data: Data
    let incomingCount: Int
    let currentCount: Int

    var message: String {
        func count(_ n: Int) -> String { n == 1 ? "1 conversation" : "\(n) conversations" }
        return "Your \(count(currentCount)) will be replaced by the \(count(incomingCount)) in this file. A backup of your current conversations is kept on this iPhone."
    }
}

private struct AngroveConversationDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw InquiryPersistenceError.invalidImport
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension Notification.Name {
    static let angroveConversationStoreDidImport = Notification.Name(
        "aquinas.conversation-store.did-import"
    )
}

struct ModelBehaviorSettingsView: View {
    @Binding var userName: String

    var body: some View {
        SettingsDetailScaffold(title: "Model Behavior") {
            SettingsControlCard {
                SettingsTextInputRow(
                    title: "Name",
                    placeholder: "John Appleseed",
                    text: $userName
                )
            }
        }
    }
}

private struct ResearchAndCitationsSettingsView: View {
    @AppStorage(SettingsStorageKey.citationPreference)
    private var citationPreference: CitationPreferenceOption = .whenHelpful
    @AppStorage(SettingsStorageKey.citationFormat)
    private var citationFormat: CitationFormatOption = .inlineLinks
    @AppStorage(SettingsStorageKey.linkHandling)
    private var linkHandling: LinkHandlingOption = .inApp

    var body: some View {
        SettingsDetailScaffold(title: "Research & Citations") {
            SettingsControlCard {
                SettingsChoiceRow(
                    title: "Citation Preference",
                    selection: $citationPreference,
                    options: Array(CitationPreferenceOption.allCases)
                )
                SettingsChoiceRow(
                    title: "Citation Format",
                    selection: $citationFormat,
                    options: Array(CitationFormatOption.allCases)
                )
                SettingsChoiceRow(
                    title: "Link Handling",
                    selection: $linkHandling,
                    options: Array(LinkHandlingOption.allCases)
                )
            }
        }
    }
}

struct ModelActivitySettingsView: View {
    @AppStorage(SettingsStorageKey.modelActivityDisplay)
    private var modelActivityDisplay: ModelActivityDisplayOption = .detailed

    var body: some View {
        SettingsDetailScaffold(title: "Model Activity") {
            SettingsControlCard {
                SettingsChoiceRow(
                    title: "Activity Display",
                    selection: $modelActivityDisplay,
                    options: Array(ModelActivityDisplayOption.allCases)
                )

                ModelActivityPreview(display: modelActivityDisplay)
            }
        }
    }
}

private struct ModelActivityPreview: View {
    let display: ModelActivityDisplayOption

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .settingsText(.label)
                .foregroundStyle(AngroveTheme.Colors.paragraphText)

            switch display {
            case .detailed:
                Text("Thinking...")
                    .settingsText(.control)
                    .foregroundStyle(AngroveTheme.Colors.primaryReadable)
            case .compact:
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(AngroveTheme.Colors.primaryReadable)
                            .frame(width: 4, height: 4)
                    }
                }
                .accessibilityLabel("Model active")
            case .hidden:
                Text("No visual activity indicator")
                    .settingsText(.detail)
                    .foregroundStyle(AngroveTheme.Colors.placeholderText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TextAndDisplaySettingsView: View {
    @Binding var conversationFontSize: ConversationFontSizeOption
    @Binding var conversationTextAlignment: ConversationTextAlignmentOption
    @Binding var inputFont: ConversationFontOption
    @Binding var responseFont: ConversationFontOption

    var body: some View {
        SettingsDetailScaffold(title: "Text & Display") {
            SettingsControlCard {
                SettingsLabeledControl(title: "Font Size") {
                    FontSizeSegmentedControl(selection: $conversationFontSize)
                }
                SettingsLabeledControl(title: "Conversation Text Alignment") {
                    ConversationAlignmentSegmentedControl(selection: $conversationTextAlignment)
                }
                SettingsLabeledControl(title: "Input Font") {
                    FontSegmentedControl(selection: $inputFont)
                }
                SettingsLabeledControl(title: "Response Font") {
                    FontSegmentedControl(selection: $responseFont)
                }
            }
        }
    }
}

struct AudioSettingsView: View {
    @AppStorage(SettingsStorageKey.autoReadResponses)
    private var readsAutomatically = false
    @AppStorage(SettingsStorageKey.readAnswersElsewhere)
    private var readsAnswersElsewhere = true
    @AppStorage(SettingsStorageKey.playAudioInBackground)
    private var playsInBackground = false
    @AppStorage(SettingsStorageKey.showReaderInControls)
    private var showsReaderInControls = true

    var body: some View {
        SettingsDetailScaffold(title: "Audio") {
            SettingsControlCard {
                SettingsToggleRow(
                    title: "Read Responses Automatically",
                    detail: "Read each answer aloud as soon as it finishes.",
                    isOn: $readsAutomatically
                )

                SettingsToggleRow(
                    title: "Read Answers Finished Elsewhere",
                    detail: "When a question is answered while you're on another page, read the answer aloud.",
                    isOn: $readsAnswersElsewhere
                )

                SettingsToggleRow(
                    title: "Play When Leaving App or Locking Screen",
                    detail: "Keep reading aloud in the background, with playback controls on the Lock Screen.",
                    isOn: $playsInBackground
                )

                SettingsToggleRow(
                    title: "Show Reader in Model Controls",
                    detail: "Show a speaker button and the Reading card in the Model Controls while a response is read aloud.",
                    isOn: $showsReaderInControls
                )
            }
        }
    }
}

struct ConversationDefaultsSettingsView: View {
    @AppStorage(SettingsStorageKey.conversationTitles)
    private var conversationTitles: ConversationTitleOption = .automatic

    var body: some View {
        SettingsDetailScaffold(title: "Conversation Defaults") {
            SettingsControlCard {
                SettingsChoiceRow(
                    title: "Conversation Titles",
                    detail: "Automatic creates a concise title after the first answer. First Question titles immediately. Manual waits for you to rename it.",
                    selection: $conversationTitles,
                    options: Array(ConversationTitleOption.allCases)
                )
            }
        }
    }
}

private struct InsightsAndDailyStudySettingsView: View {
    @AppStorage(SettingsStorageKey.insightMapping)
    private var insightMapping: InsightMappingOption = .adaptive
    @AppStorage(SettingsStorageKey.definitionHighlights)
    private var definitionHighlights: DefinitionHighlightsOption = .adaptive
    @AppStorage(SettingsStorageKey.dailyQuestionFocus)
    private var dailyQuestionFocus: DailyQuestionFocusOption = .varied

    var body: some View {
        SettingsDetailScaffold(title: "Insights & Daily Study") {
            VStack(alignment: .leading, spacing: 24) {
                SettingsSubsection(title: "Insight Tree") {
                    SettingsChoiceRow(
                        title: "Automatic Insight Mapping",
                        selection: $insightMapping,
                        options: Array(InsightMappingOption.allCases)
                    )
                    SettingsChoiceRow(
                        title: "Definition Highlights",
                        selection: $definitionHighlights,
                        options: Array(DefinitionHighlightsOption.allCases)
                    )
                }

                SettingsSubsection(title: "Question of the Day") {
                    SettingsChoiceRow(
                        title: "Focus",
                        selection: $dailyQuestionFocus,
                        options: Array(DailyQuestionFocusOption.allCases)
                    )
                }
            }
        }
    }
}

struct SettingsInformationView: View {
    let title: LocalizedStringResource
    let message: LocalizedStringResource

    var body: some View {
        SettingsDetailScaffold(title: title) {
            SettingsControlCard {
                Text(message)
                    .settingsText(.paragraph)
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct BugReportSettingsView: View {
    private enum Field { case description, steps, email }

    @State private var description = ""
    @State private var steps = ""
    @State private var replyEmail = ""
    @State private var isSending = false
    @State private var hasSent = false
    @State private var hasFailed = false
    @State private var statusMessage = ""
    @FocusState private var focusedField: Field?

    private var canSend: Bool {
        !isSending && !hasSent
            && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        SettingsDetailScaffold(title: "Report a Bug") {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AngroveTheme.Colors.accentGreen)
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)
                    Text("Tell us what went wrong. Your report and basic app details go to the Angrove bug report inbox. Please leave out passwords or private conversations.")
                        .settingsText(.paragraph)
                        .foregroundStyle(AngroveTheme.Colors.paragraphText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                reportField(
                    title: "What happened?",
                    badge: "Required",
                    isFocused: focusedField == .description
                ) {
                    multilineInput(
                        text: $description,
                        prompt: "Describe the problem you ran into",
                        minHeight: 140,
                        field: .description,
                        label: "What happened?"
                    )
                }

                reportField(
                    title: "Steps to reproduce",
                    badge: "Optional",
                    isFocused: focusedField == .steps
                ) {
                    multilineInput(
                        text: $steps,
                        prompt: "What did you do right before it happened?",
                        minHeight: 100,
                        field: .steps,
                        label: "Steps to reproduce, optional"
                    )
                }

                reportField(
                    title: "Your email",
                    badge: "Optional",
                    footnote: "Only if you’d like a reply.",
                    isFocused: focusedField == .email
                ) {
                    TextField("you@example.com", text: $replyEmail)
                        .settingsText(.control)
                        .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .accessibilityLabel("Your email, optional")
                }

                VStack(alignment: .leading, spacing: 14) {
                    Button(action: sendReport) {
                        HStack(spacing: 10) {
                            Image(systemName: hasSent ? "checkmark.circle" : "paperplane")
                            Text(isSending ? "Sending…" : hasSent ? "Report Sent" : "Send Report")
                                .settingsText(.label)
                        }
                        .foregroundStyle(AngroveTheme.Colors.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(AngroveTheme.Colors.darkGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .opacity(canSend || hasSent || isSending ? 1 : 0.55)

                    if !statusMessage.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: hasFailed ? "exclamationmark.circle" : hasSent ? "checkmark.circle" : "ellipsis.circle")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(hasFailed ? AngroveTheme.Colors.accentRed : AngroveTheme.Colors.accentGreen)
                                .accessibilityHidden(true)
                            Text(statusMessage)
                                .settingsText(.paragraph)
                                .foregroundStyle(AngroveTheme.Colors.paragraphText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.updatesFrequently)
                    }
                }
            }
            .animation(.springQuick, value: statusMessage)
        }
    }

    /// A label above a bordered input that picks up the accent color while focused.
    private func reportField<Input: View>(
        title: LocalizedStringResource,
        badge: LocalizedStringResource,
        footnote: LocalizedStringResource? = nil,
        isFocused: Bool,
        @ViewBuilder input: () -> Input
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .settingsText(.label)
                    .foregroundStyle(AngroveTheme.Colors.headingText)
                Spacer(minLength: 8)
                Text(badge)
                    .font(.custom("Figtree-Bold", size: 12))
                    .foregroundStyle(AngroveTheme.Colors.paragraphText.opacity(0.7))
            }

            input()
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AngroveTheme.Colors.canvasSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            isFocused ? AngroveTheme.Colors.accentGreen : AngroveTheme.Colors.controlBorder,
                            lineWidth: isFocused ? 1.5 : 1
                        )
                }
                .animation(.springQuick, value: isFocused)

            if let footnote {
                Text(footnote)
                    .settingsText(.paragraph)
                    .foregroundStyle(AngroveTheme.Colors.paragraphText.opacity(0.8))
            }
        }
    }

    private func multilineInput(
        text: Binding<String>,
        prompt: LocalizedStringResource,
        minHeight: CGFloat,
        field: Field,
        label: String
    ) -> some View {
        TextEditor(text: text)
            .settingsText(.control)
            .foregroundStyle(AngroveTheme.Colors.primaryReadable)
            .scrollContentBackground(.hidden)
            .focused($focusedField, equals: field)
            .frame(minHeight: minHeight)
            .padding(.horizontal, -5)
            .padding(.vertical, -8)
            .overlay(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(prompt)
                        .settingsText(.control)
                        .foregroundStyle(AngroveTheme.Colors.paragraphText.opacity(0.55))
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel(label)
    }

    private func sendReport() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = info?["CFBundleVersion"] as? String ?? "Unknown"
        let system = ProcessInfo.processInfo.operatingSystemVersionString
        let trimmedSteps = steps.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = replyEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        var fields = [
            "_subject": "Angrove bug report",
            "description": description.trimmingCharacters(in: .whitespacesAndNewlines),
            "steps": trimmedSteps.isEmpty ? "Not provided" : trimmedSteps,
            "app_version": version,
            "app_build": build,
            "operating_system": system
        ]
        if !trimmedEmail.isEmpty {
            fields["_replyto"] = trimmedEmail
        }

        isSending = true
        hasFailed = false
        focusedField = nil
        statusMessage = "Sending your report…"
        Task { @MainActor in
            do {
                try await BugReportSubmission.send(fields: fields)
                hasSent = true
                description = ""
                steps = ""
                replyEmail = ""
                statusMessage = "Thanks. Your report was sent to the Angrove team."
            } catch {
                hasFailed = true
                statusMessage = "We couldn’t send your report. Check your connection and try again, or email bugreport@angrove.app directly."
            }
            isSending = false
        }
    }
}

/// Posts to the Angrove bug report inbox (bugreport@angrove.app). Shared by the Settings
/// bug report form and the response thumbs-down feedback sheet.
enum BugReportSubmission {
    private static let endpoint = URL(string: "https://formspree.io/f/xnpjppgj")!

    static func send(fields: [String: String]) async throws {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = multipartBody(fields: fields, boundary: boundary)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private static func multipartBody(fields: [String: String], boundary: String) -> Data {
        var body = Data()
        for key in fields.keys.sorted() {
            guard let value = fields[key] else { continue }
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }
}
