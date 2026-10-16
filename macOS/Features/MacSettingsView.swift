import SwiftUI

/// All preferences stay on one page; only the guide has its own destination.
struct MacSettingsView: View {
    @State private var showsGuide: Bool
    @State private var showsHotKeys = false

    init(startsInGuide: Bool = false) {
        _showsGuide = State(initialValue: startsInGuide)
    }

    var body: some View {
        if showsHotKeys {
            ScrollView {
                MacHotKeys()
                    .frame(maxWidth: MacConversationStyle.pageContentMaxWidth, alignment: .leading)
                    .padding(.horizontal, MacConversationStyle.pageHorizontalPadding)
                    .padding(.top, MacConversationStyle.pageTopPadding)
                    .padding(.bottom, 48)
                    .frame(maxWidth: .infinity)
            }
            .macSettingsScrollEdges()
            .overlay(alignment: .topLeading) {
                MacBackCapsule(title: "Settings") { showsHotKeys = false }
            }
            .font(AngroveTheme.Typography.body)
            .foregroundStyle(AngroveTheme.Colors.paragraphText)
            .tint(AngroveTheme.Colors.lightGreen)
            .background(AngroveTheme.Colors.canvas)
        } else if showsGuide {
            MacUserGuideView(onExit: { showsGuide = false })
                .font(AngroveTheme.Typography.body)
                .foregroundStyle(AngroveTheme.Colors.paragraphText)
                .tint(AngroveTheme.Colors.lightGreen)
        } else {
            settingsPage
        }
    }

    private var settingsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                    MacPageIntroduction(title: "Settings", description: "Choose how Angrove looks, works, and fits your conversations.")
                    MacPersonalizationSettings()
                    MacAppearanceSettings()
                    MacResponseSettings()
                    MacAudioSettings()
                    MacNotificationSettings()
                    MacPrivacySettings()
                    MacModelSettings()
                    MacDataSettings()
                    MacSupportSettings(openGuide: { showsGuide = true }, openHotKeys: { showsHotKeys = true })
            }
            .frame(maxWidth: MacConversationStyle.pageContentMaxWidth, alignment: .leading)
            .padding(.horizontal, MacConversationStyle.pageHorizontalPadding)
            .padding(.top, MacConversationStyle.pageTopPadding)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
        .macSettingsScrollEdges()
        .font(AngroveTheme.Typography.body)
        .foregroundStyle(AngroveTheme.Colors.paragraphText)
        .tint(AngroveTheme.Colors.lightGreen)
        .background(AngroveTheme.Colors.canvas)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The iPhone's back capsule: a 48 pt pill with a chevron and the parent page's title.
struct MacBackCapsule: View {
    let title: String
    var isPadded = true
    /// Off where Escape already has a job, such as the Worktree canvas deselecting.
    var leavesOnEscape = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AngroveTheme.Colors.darkGreen)
                    .frame(width: 14, height: 14)
                BlurSwapText(title)
                    .font(AngroveTheme.Typography.uiSubheading)
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
                    .lineLimit(1)
            }
            .animation(.springStandard, value: title)
            .padding(.horizontal, 19)
            .frame(height: 48)
            .background(AngroveTheme.Colors.canvasSecondary, in: Capsule())
            .overlay(Capsule().strokeBorder(AngroveTheme.Colors.controlBorder, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pulsesOnChange(of: title, anchor: .leading)
        .keyboardShortcut(leavesOnEscape ? .cancelAction : nil)
        .background(Button("", action: action).keyboardShortcut("[", modifiers: .command)
            .opacity(0).allowsHitTesting(false).accessibilityHidden(true))
        .padding(.top, isPadded ? 24 : 0)
        .padding(.leading, isPadded ? 24 : 0)
        .macBackButtonEntrance()
        .accessibilityLabel("Back to \(title)")
    }
}

/// The conversation thread's edge fades, scaled by how far the page has scrolled: each fully
/// disappears at its own end, so the page never looks cut off at rest.
struct MacScrollEdgeFades: View {
    let top: CGFloat
    let bottom: CGFloat

    var body: some View {
        ZStack {
            MacConversationEdgeFade(top: true)
                .opacity(top)
                .frame(maxHeight: .infinity, alignment: .top)
            MacConversationEdgeFade(top: false)
                .opacity(bottom)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct MacScrollEdgeAmounts: Equatable {
    var top: CGFloat = 0
    var bottom: CGFloat = 0
}

private struct MacSettingsScrollEdges: ViewModifier {
    @State private var amounts = MacScrollEdgeAmounts()

    func body(content: Content) -> some View {
        content
            .ignoresSafeArea()
            .onScrollGeometryChange(for: MacScrollEdgeAmounts.self) { geometry in
                let offset = geometry.contentOffset.y + geometry.contentInsets.top
                let remaining = geometry.contentSize.height - geometry.containerSize.height
                    + geometry.contentInsets.bottom - geometry.contentOffset.y
                func amount(_ distance: CGFloat) -> CGFloat { (min(max(distance, 0) / 48, 1) * 20).rounded() / 20 }
                return MacScrollEdgeAmounts(top: amount(offset), bottom: amount(remaining))
            } action: { _, new in
                amounts = new
            }
            .overlay { MacScrollEdgeFades(top: amounts.top, bottom: amounts.bottom) }
    }
}

extension View {
    /// Settings pages run to the window's top and bottom, fading content at whichever edge has more to scroll.
    func macSettingsScrollEdges() -> some View { modifier(MacSettingsScrollEdges()) }
}

enum MacSettingsAppearance {
    static func scheme(_ value: String) -> ColorScheme? {
        switch value {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}

struct MacSettingsSection<Content: View>: View {
    let title: String
    let description: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(AngroveTheme.Typography.uiHeading)
                    .foregroundStyle(AngroveTheme.Colors.headingText)
                Text(description)
                    .macStaticParagraph()
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
            }
            VStack(spacing: 0) { content }
                .padding(.horizontal, 20)
                .background(AngroveTheme.Colors.canvasSecondary,
                            in: RoundedRectangle(cornerRadius: AngroveTheme.Spacing.smallCardRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: AngroveTheme.Spacing.smallCardRadius)
                        .stroke(AngroveTheme.Colors.border, lineWidth: 1)
                }
        }
    }
}

/// Settings paragraphs that stay still: only a page's own heading animates in.
extension View {
    func macStaticParagraph() -> some View {
        settingsText(.paragraph)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct MacSettingsRow<Control: View>: View {
    let title: String
    let description: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).foregroundStyle(AngroveTheme.Colors.headingText)
                Text(description).font(AngroveTheme.Typography.settingsDetail)
                    .foregroundStyle(AngroveTheme.Colors.placeholderText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control.frame(width: 160, alignment: .trailing)
        }
        .padding(.vertical, 18)
    }
}

private struct MacPersonalizationSettings: View {
    @EncryptedStringStorage(MacPersonalization.userNameKey) private var userName = ""
    var body: some View {
        MacSettingsSection(title: "Personalization", description: "Tell Angrove how to greet you.") {
            MacSettingsRow(title: "Your name", description: "Used in Home’s greeting. Stored encrypted on this Mac.") {
                TextField("Name", text: $userName, prompt: Text(MacPersonalization.accountGivenName))
                    .macPlainField()
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

enum MacPersonalization {
    /// The same encrypted preference the iPhone app uses for its greeting.
    static let userNameKey = "aquinas.settings.userName"

    static var accountGivenName: String {
        NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
    }

    /// The saved name, then the Mac account's given name, then the iPhone's "friend".
    static var greetingName: String {
        let saved = SerializedPersonalStore.shared.string(for: userNameKey, defaultValue: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !saved.isEmpty { return saved }
        return accountGivenName.isEmpty ? "friend" : accountGivenName
    }
}

private struct MacAppearanceSettings: View {
    @AppStorage(SettingsStorageKey.colorScheme) private var appearance = "system"
    @AppStorage(SettingsStorageKey.conversationBackground) private var conversationBackground: CanvasBackgroundOption = .system
    @AppStorage(SettingsStorageKey.insightTreeBackground) private var treeBackground: CanvasBackgroundOption = .system
    var body: some View {
        MacSettingsSection(title: "Appearance", description: "Make Angrove feel at home on your Mac.") {
            MacSettingsRow(title: "Theme", description: "Choose a light or dark appearance, or follow your Mac.") {
                MacMenuPicker(title: "Theme", selection: $appearance, options: [("system", String(localized: "System")), ("light", String(localized: "Light")), ("dark", String(localized: "Dark"))])
            }
            Divider()
            MacSettingsRow(title: "Conversation background", description: "Light, Dark, your theme, or Clouds behind the transcript.") {
                MacMenuPicker(title: "Conversation background", selection: $conversationBackground,
                              options: CanvasBackgroundOption.allCases.map { ($0, String(localized: $0.title)) })
            }
            Divider()
            MacSettingsRow(title: "Insight Tree background", description: "The canvas behind every Insight Tree.") {
                MacMenuPicker(title: "Insight Tree background", selection: $treeBackground,
                              options: CanvasBackgroundOption.allCases.map { ($0, String(localized: $0.title)) })
            }
        }
    }
}

private struct MacResponseSettings: View {
    @AppStorage("aquinas.settings.responseFont") private var font: ConversationFontOption = .serif
    @AppStorage("aquinas.settings.conversationFontSize") private var size: ConversationFontSizeOption = .medium
    @AppStorage(MacConversationStyle.questionFontKey) private var questionFont: ConversationFontOption = .serif
    @AppStorage(SettingsStorageKey.conversationTitles) private var titles: ConversationTitleOption = .automatic
    @AppStorage(SettingsStorageKey.defaultStartScreen) private var startScreen: DefaultStartScreenOption = .home
    var body: some View {
        MacSettingsSection(title: "Conversations", description: "Choose how conversations look, are titled, and where Angrove opens.") {
            MacSettingsRow(title: "Response font", description: "The typeface used for Angrove’s answers.") {
                MacMenuPicker(title: "Response font", selection: $font, options: ConversationFontOption.allCases.map { ($0, $0.rawValue) })
            }
            Divider()
            MacSettingsRow(title: "Text size", description: "Adjust the reading size of conversation responses.") {
                MacMenuPicker(title: "Text size", selection: $size, options: ConversationFontSizeOption.allCases.map { ($0, $0.rawValue) })
            }
            Divider()
            MacSettingsRow(title: "Question font", description: "The typeface used for your questions.") {
                MacMenuPicker(title: "Question font", selection: $questionFont, options: ConversationFontOption.allCases.map { ($0, $0.rawValue) })
            }
            Divider()
            MacSettingsRow(title: "Conversation titles", description: "Automatic writes a short title, First Question uses your question, and Manual waits for you to rename it.") {
                MacMenuPicker(title: "Conversation titles", selection: $titles, options: ConversationTitleOption.allCases.map { ($0, String(localized: $0.title)) })
            }
            Divider()
            MacSettingsRow(title: "Open Angrove to", description: "Where Angrove starts when you open it.") {
                MacMenuPicker(title: "Open Angrove to", selection: $startScreen, options: DefaultStartScreenOption.allCases.map { ($0, String(localized: $0.title)) })
            }
        }
    }
}

private struct MacAudioSettings: View {
    @AppStorage(SettingsStorageKey.autoReadResponses) private var autoRead = false
    @AppStorage(SettingsStorageKey.showReaderInControls) private var controls = true
    @AppStorage(SettingsStorageKey.readAnswersElsewhere) private var readsElsewhere = false
    var body: some View {
        MacSettingsSection(title: "Read Aloud", description: "Listen to answers, Insights, and passages.") {
            MacSettingsRow(title: "Read responses automatically", description: "Begin reading when an answer finishes.") {
                Toggle("Read responses automatically", isOn: $autoRead).labelsHidden().toggleStyle(.switch)
            }
            Divider()
            MacSettingsRow(title: "Read answers finished elsewhere", description: "When an answer finishes while you’re on another page, read it aloud.") {
                Toggle("Read answers finished elsewhere", isOn: $readsElsewhere).labelsHidden().toggleStyle(.switch)
            }
            Divider()
            MacSettingsRow(title: "Show reader in Model Controls", description: "Keep the reading controls available while listening.") {
                Toggle("Show reader in Model Controls", isOn: $controls).labelsHidden().toggleStyle(.switch)
            }
        }
    }
}

private struct MacNotificationSettings: View {
    @AppStorage(SettingsStorageKey.dailyQuestionNotifications) private var dailyQuestion = false
    @AppStorage(SettingsStorageKey.completedResponseNotifications) private var completedResponses = false
    @AppStorage(SettingsStorageKey.dailyQuestionReminderTime) private var reminderSeconds = 9.0 * 60.0 * 60.0

    var body: some View {
        MacSettingsSection(title: "Notifications", description: "Choose when Angrove lets you know something is ready.") {
            MacSettingsRow(title: "Completed responses", description: "Notify me when an answer finishes while I’m on another page or app.") {
                Toggle("Completed responses", isOn: $completedResponses).labelsHidden().toggleStyle(.switch)
            }
            Divider()
            MacSettingsRow(title: "Question of the Day", description: "Receive one daily reminder.") {
                Toggle("Question of the Day", isOn: $dailyQuestion).labelsHidden().toggleStyle(.switch)
            }
            if dailyQuestion {
                Divider()
                MacSettingsRow(title: "Reminder time", description: "When the daily reminder arrives.") {
                    DatePicker("Reminder time", selection: reminderTime, displayedComponents: .hourAndMinute).labelsHidden()
                }
            }
        }
        .onChange(of: completedResponses) { _, enabled in
            guard enabled else { return }
            Task { if !(await AngroveSystemNotifications.requestAuthorization()) { completedResponses = false } }
        }
        .onChange(of: dailyQuestion) { _, _ in updateReminder() }
        .onChange(of: reminderSeconds) { _, _ in updateReminder() }
    }

    private var reminderTime: Binding<Date> {
        Binding(get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(reminderSeconds) },
                set: { date in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                    reminderSeconds = Double((parts.hour ?? 9) * 3_600 + (parts.minute ?? 0) * 60)
                })
    }

    private func updateReminder() {
        Task {
            if dailyQuestion {
                await AngroveSystemNotifications.scheduleDailyQuestionReminder(secondsFromMidnight: reminderSeconds)
                if !(await AngroveSystemNotifications.requestAuthorization()) { dailyQuestion = false }
            } else {
                AngroveSystemNotifications.removeDailyQuestionReminder()
            }
        }
    }
}

private struct MacPrivacySettings: View {
    @AppStorage(SettingsStorageKey.appLock) private var appLock = false
    @AppStorage(SettingsStorageKey.appLockGracePeriod) private var gracePeriod: AppLockGracePeriodOption = .immediately

    var body: some View {
        MacSettingsSection(title: "Privacy", description: "Protect access to your conversations on this Mac.") {
            MacSettingsRow(title: "App Lock", description: "Require Touch ID or your Mac password when you return to Angrove.") {
                Toggle("App Lock", isOn: $appLock).labelsHidden().toggleStyle(.switch)
            }
            if appLock {
                Divider()
                MacSettingsRow(title: "Lock after", description: "How long Angrove can be in the background, hidden, or asleep before it locks.") {
                    MacMenuPicker(title: "Lock after", selection: $gracePeriod, options: AppLockGracePeriodOption.allCases.map { ($0, String(localized: $0.title)) })
                }
            }
        }
    }
}

/// Model choice. A switch takes effect between model tasks; Model Tasks offers the same menu.
private struct MacModelSettings: View {
    private let runtime = MacApplicationRuntime.shared

    var body: some View {
        MacSettingsSection(title: "Model", description: "Choose the on-device model Angrove answers with.") {
            MacSettingsRow(title: "Model size", description: runtime.modelTier.detail) {
                MacMenuPicker(
                    title: "Model size",
                    selection: Binding(get: { runtime.modelTier }, set: { runtime.selectModel($0) }),
                    options: runtime.availableTiers.map { ($0, $0.title) }
                )
            }
        }
    }
}

/// The trailing chevron that marks a settings row as a page it opens.
private struct MacSettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AngroveTheme.Colors.lightGreen)
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
    }
}

private struct MacSupportSettings: View {
    let openGuide: () -> Void
    let openHotKeys: () -> Void
    @State private var showsReport = false
    @State private var showsLicenses = false
    @State private var confirmsReset = false
    var body: some View {
        MacSettingsSection(title: "Support & Privacy", description: "Get to know Angrove and manage your preferences.") {
            Button(action: openGuide) {
                MacSettingsRow(title: "User Guide", description: "Learn about conversations, the Insight Tree, and keyboard shortcuts.") {
                    MacSettingsChevron()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            Divider()
            Button(action: openHotKeys) {
                MacSettingsRow(title: "Hot Keys", description: "Keyboard shortcuts for conversations, the Insight Tree, navigation, and Model Tasks.") {
                    MacSettingsChevron()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            Divider()
            MacSettingsRow(title: "Report a problem", description: "Send a description of what went wrong. Nothing else is shared.") {
                Button("Report…") { showsReport = true }
            }
            Divider()
            MacSettingsRow(title: "Licenses", description: "Models, software, fonts and Library editions that ship with Angrove.") {
                Button("View…") { showsLicenses = true }
            }
            Divider()
            MacSettingsRow(title: "On-device privacy", description: "Generation, retrieval, and your saved content stay on your Mac.") {
                Link(destination: URL(string: "https://angrove.app/privacy.html")!) {
                    HStack(spacing: 6) {
                        Text("Privacy Policy")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
            }
            Divider()
            MacSettingsRow(title: "Reset settings", description: "Restore default preferences. Your conversations and saved content are preserved.") {
                Button("Reset Settings") { confirmsReset = true }
            }
        }
        .sheet(isPresented: $showsReport) { MacBugReportSheet() }
        .sheet(isPresented: $showsLicenses) { MacLicensesSheet() }
        .confirmationDialog("Reset settings to their defaults?", isPresented: $confirmsReset) {
            Button("Reset Settings", role: .destructive) {
                for key in SettingsStorageKey.allResettableKeys { UserDefaults.standard.removeObject(forKey: key) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}


private struct MacHotKeys: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            MacPageIntroduction(title: "Hot Keys", description: "Keyboard shortcuts for moving through Angrove without leaving the keys.")
            MacSettingsSection(title: "Conversations", description: "Follow a question wherever it leads.") {
                MacSettingsRow(title: "Ask and follow up", description: "Press Command-N for a new conversation. Command-Return focuses the question field; Return submits and Shift-Return adds a line.") { Text("⌘N · ⌘↵") }
                Divider()
                MacSettingsRow(title: "Context and Thinking", description: "Command-Shift-C toggles Context. Show Thinking reveals the approach and sources, and native model thoughts when enabled.") { Text("⇧⌘C") }
            }
            MacSettingsSection(title: "Insight Tree", description: "Connect ideas and explore what they mean.") {
                MacSettingsRow(title: "Explore your tree", description: "Command-T toggles the conversation’s secondary pane. Select an idea to see its card, save it, quote it, or study it. Command-Shift-T toggles the global tree and returns to your previous page.") { Text("⌘T · ⇧⌘T") }
                Divider()
                MacSettingsRow(title: "Arrange your workspace", description: "Command-S swaps the conversation and tree. Command-P pins or unpins the panes.") { Text("⌘S · ⌘P") }
            }
            MacSettingsSection(title: "Navigation & Model Tasks", description: "Move around without losing your place.") {
                MacSettingsRow(title: "Recent pages", description: "Command-R goes back and Command-Shift-R goes forward. Command-1 through Command-9 selects a recent conversation.") { Text("⌘R · ⇧⌘R") }
                Divider()
                MacSettingsRow(title: "Home", description: "Command-Shift-H opens Home: your month at a glance, the Question of the Day, and where you left off.") { Text("⇧⌘H") }
                Divider()
                MacSettingsRow(title: "Model Tasks", description: "Command-M toggles the task queue. Review pending work, cancel a task, or change the order of upcoming tasks.") { Text("⌘M") }
            }
        }
        .lineSpacing(4)
    }
}
