//
//  SettingsView.swift
//  Angrove-iOS
//

import SwiftUI

// MARK: - Settings

struct SettingsView: View {
    @Binding var colorSchemeOverride: ColorScheme?
    @Binding var userName: String
    @Binding var customInstructions: String
    @Binding var conversationFontSize: ConversationFontSizeOption
    @Binding var conversationTextAlignment: ConversationTextAlignmentOption
    @Binding var inputFont: ConversationFontOption
    @Binding var responseFont: ConversationFontOption
    @Binding var conversationPersonality: ConversationPersonality
    @Binding var collectedDefinitions: [ConceptDefinition]
    var onOpenMenu: () -> Void
    var onDetailVisibilityChange: (Bool) -> Void = { _ in }
    var onClearInsightTree: () -> Void = {}
    /// Set by other pages (Home's Start Here card) to open the User Guide; cleared once handled.
    var opensUserGuide: Binding<Bool> = .constant(false)

    @State private var path: [SettingsRoute] = []
    @State private var guideSavedTerms: [String] = []

    var body: some View {
        ZStack(alignment: .topLeading) {
            NavigationStack(path: $path) {
                SettingsHubView(
                    colorSchemeOverride: colorSchemeOverride,
                    conversationFontSize: conversationFontSize,
                    responseFont: responseFont
                ) { route in
                    path.append(route)
                }
                .navigationDestination(for: SettingsRoute.self) { route in
                    SettingsDestinationView(
                        route: route,
                        colorSchemeOverride: $colorSchemeOverride,
                        userName: $userName,
                        customInstructions: $customInstructions,
                        conversationFontSize: $conversationFontSize,
                        conversationTextAlignment: $conversationTextAlignment,
                        inputFont: $inputFont,
                        responseFont: $responseFont,
                        collectedDefinitions: $collectedDefinitions,
                        guideSavedTerms: $guideSavedTerms,
                        onReset: resetSettings,
                        onClearInsightTree: onClearInsightTree,
                        onSelectUserGuideTopic: { path.append(.userGuideTopic($0)) }
                    )
                    .navigationBarBackButtonHidden(true)
                    .toolbar(.hidden, for: .navigationBar)
                }
                .toolbar(.hidden, for: .navigationBar)
            }
            .background(AngroveTheme.Colors.canvas)
            .onChange(of: opensUserGuide.wrappedValue, initial: true) { _, opens in
                guard opens else { return }
                path = [.userGuide]
                opensUserGuide.wrappedValue = false
            }

            HStack(spacing: 8) {
                AngroveNavButton(onMenuTap: onOpenMenu)
                if !path.isEmpty {
                    NavBackCapsuleButton(title: backTitle) {
                        guard !path.isEmpty else { return }
                        path.removeLast()
                    }
                    .transition(.studyExitGrow)
                }
            }
            .animation(.springStandard, value: path.isEmpty)
            .padding(.top, 24)
            .padding(.leading, 24)
            .zIndex(2)
        }
        .simultaneousGesture(settingsBackGesture)
        .onAppear {
            onDetailVisibilityChange(!path.isEmpty)
        }
        .onChange(of: path) { _, newPath in
            onDetailVisibilityChange(!newPath.isEmpty)
        }
        .onDisappear {
            onDetailVisibilityChange(false)
        }
    }

    /// Back returns one level, so from a guide topic it leads to the User Guide, not Settings.
    private var backTitle: String {
        if case .userGuideTopic = path.last { return "User Guide" }
        return "Settings"
    }

    private var settingsBackGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onEnded { value in
                guard !path.isEmpty,
                      value.startLocation.x < 30,
                      value.translation.width > 60,
                      abs(value.translation.width) > abs(value.translation.height) else {
                    return
                }

                SettingsHaptics.playSelection()
                path.removeLast()
            }
    }

    private func resetSettings() {
        for key in SettingsStorageKey.allResettableKeys {
            PrivatePreferences.standard.removeObject(forKey: key)
        }

        colorSchemeOverride = nil
        userName = ""
        customInstructions = ""
        conversationFontSize = .medium
        conversationTextAlignment = .left
        inputFont = .serif
        responseFont = .serif
        conversationPersonality = .default
    }
}

private enum SettingsRoute: Hashable {
    case appearance
    case appExperience
    case notifications
    case privacyAndData
    case modelBehavior
    case modelActivity
    case modelDownload
    case textAndDisplay
    case conversationDefaults
    case audio
    case userGuide
    case userGuideTopic(UserGuideTopic.ID)
    case reportBug
}

// MARK: - Hub

/// The Settings home reads like a book's table of contents: italic part titles, serif entries, and
/// each entry's current state noted beneath it.
private struct SettingsHubView: View {
    let colorSchemeOverride: ColorScheme?
    let conversationFontSize: ConversationFontSizeOption
    let responseFont: ConversationFontOption
    let onSelect: (SettingsRoute) -> Void

    var body: some View {
        ZStack {
            AngroveTheme.Colors.canvas.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 48) {
                    SettingsHubHeader()

                    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                        SettingsHubPart(
                            title: part.title,
                            rows: part.rows,
                            onSelect: onSelect
                        )
                    }

                    SettingsColophon()
                }
                .padding(.horizontal, 24)
                // Clears the floating menu button, matching the Library home.
                .padding(.top, 96)
                .padding(.bottom, 120)
            }
        }
    }

    private var appearanceDetail: LocalizedStringResource {
        switch colorSchemeOverride {
        case .light: "Light"
        case .dark: "Dark"
        default: "Matches system"
        }
    }

    private var parts: [(title: LocalizedStringResource, rows: [SettingsHubItem])] {
        [
            ("General", [
                SettingsHubItem(title: "Appearance", detail: appearanceDetail, iconName: "paintpalette", route: .appearance),
                SettingsHubItem(title: "App Experience", detail: "Start screen and haptics", iconName: "sparkles", route: .appExperience),
                SettingsHubItem(title: "Notifications", detail: "Daily question and finished responses", iconName: "bell", route: .notifications),
                SettingsHubItem(title: "Privacy & Data", detail: "App lock, export, and import", iconName: "lock.shield", route: .privacyAndData)
            ]),
            ("Conversations", [
                SettingsHubItem(title: "Audio", detail: "Read-aloud playback", iconName: "speaker.wave.2", route: .audio),
                SettingsHubItem(
                    title: "Text & Display",
                    detail: "\(responseFont.rawValue) · \(conversationFontSize.rawValue)",
                    iconName: "textformat.size",
                    route: .textAndDisplay
                ),
                SettingsHubItem(title: "Conversation Defaults", detail: "Titles and daily study", iconName: "bubble.left.and.bubble.right", route: .conversationDefaults)
            ]),
            ("Model", [
                SettingsHubItem(title: "On-device Model", detail: "Download, readiness, and recovery", iconName: "arrow.down.circle", route: .modelDownload),
                SettingsHubItem(
                    title: "Model Behavior",
                    detail: "Your name",
                    iconName: "brain",
                    route: .modelBehavior
                ),
                SettingsHubItem(title: "Model Activity", detail: "How on-device work is shown", iconName: "waveform.circle", route: .modelActivity)
            ]),
            ("Support", [
                SettingsHubItem(title: "User Guide", detail: "How each part of Angrove works", iconName: "book", route: .userGuide),
                SettingsHubItem(title: "Report a Bug", detail: "Tell us what went wrong", iconName: "ladybug", route: .reportBug)
            ])
        ]
    }
}

private struct SettingsHubHeader: View {
    var body: some View {
        Text("Settings")
            .font(AngroveTheme.Typography.titleXLarge)
            .foregroundStyle(AngroveTheme.Colors.primaryReadable)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct SettingsHubItem: Identifiable {
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let iconName: String
    let route: SettingsRoute

    var id: SettingsRoute { route }
}

/// One part of the contents: an italic serif title over its entries on a flat bordered card.
private struct SettingsHubPart: View {
    let title: LocalizedStringResource
    let rows: [SettingsHubItem]
    let onSelect: (SettingsRoute) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.custom("LibreBaskerville-Italic", size: 24))
                .foregroundStyle(AngroveTheme.Colors.headingText)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Rectangle()
                            .fill(AngroveTheme.Colors.divider)
                            .frame(height: 1)
                            .padding(.leading, 36)
                    }
                    SettingsHubRow(item: row) { onSelect(row.route) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
            .background {
                let shape = RoundedRectangle(cornerRadius: AngroveTheme.Spacing.cardRadius, style: .continuous)
                shape
                    .fill(AngroveTheme.Colors.canvasSecondary)
                    .overlay(shape.stroke(AngroveTheme.Colors.quietBorder, lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsHubRow: View {
    let item: SettingsHubItem
    let action: () -> Void

    var body: some View {
        Button {
            SettingsHaptics.playSelection()
            action()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: item.iconName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AngroveTheme.Colors.lightGreen)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.custom("LibreBaskerville-Regular", size: 16))
                        .foregroundStyle(AngroveTheme.Colors.primaryReadable)

                    Text(item.detail)
                        .font(.custom("Figtree-Regular", size: 12))
                        .foregroundStyle(AngroveTheme.Colors.placeholderText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AngroveTheme.Colors.placeholderText)
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: AngroveTheme.Spacing.controlHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this settings menu")
    }
}

/// A closing colophon, as at the end of a printed book.
private struct SettingsColophon: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 8) {
            AppIconImage(size: 14)
                .accessibilityHidden(true)
                .padding(.bottom, 4)

            Text("Angrove")
                .font(AngroveTheme.Typography.quote)
                .foregroundStyle(AngroveTheme.Colors.headingText)

            Text("Version \(version) · Runs entirely on this device")
                .font(.custom("Figtree-Regular", size: 11))
                .foregroundStyle(AngroveTheme.Colors.placeholderText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Destinations

private struct SettingsDestinationView: View {
    let route: SettingsRoute
    @Binding var colorSchemeOverride: ColorScheme?
    @Binding var userName: String
    @Binding var customInstructions: String
    @Binding var conversationFontSize: ConversationFontSizeOption
    @Binding var conversationTextAlignment: ConversationTextAlignmentOption
    @Binding var inputFont: ConversationFontOption
    @Binding var responseFont: ConversationFontOption
    @Binding var collectedDefinitions: [ConceptDefinition]
    @Binding var guideSavedTerms: [String]
    let onReset: () -> Void
    var onClearInsightTree: () -> Void = {}
    var onSelectUserGuideTopic: (UserGuideTopic.ID) -> Void = { _ in }

    var body: some View {
        switch route {
        case .appearance:
            AppearanceSettingsView(colorSchemeOverride: $colorSchemeOverride)
        case .appExperience:
            AppExperienceSettingsView(onReset: onReset)
        case .notifications:
            NotificationSettingsView()
        case .privacyAndData:
            PrivacyAndDataSettingsView(onClearInsightTree: onClearInsightTree)
        case .modelBehavior:
            ModelBehaviorSettingsView(userName: $userName)
        case .modelDownload:
            ModelDownloadSettingsView()
        case .modelActivity:
            ModelActivitySettingsView()
        case .textAndDisplay:
            TextAndDisplaySettingsView(
                conversationFontSize: $conversationFontSize,
                conversationTextAlignment: $conversationTextAlignment,
                inputFont: $inputFont,
                responseFont: $responseFont
            )
        case .conversationDefaults:
            ConversationDefaultsSettingsView()
        case .audio:
            AudioSettingsView()
        case .userGuide:
            UserGuideSettingsView(onSelectTopic: onSelectUserGuideTopic, savedTerms: $guideSavedTerms)
        case .userGuideTopic(let id):
            if let topic = UserGuideTopic.topic(id: id) {
                UserGuideTopicView(topic: topic, collectedDefinitions: $collectedDefinitions, savedTerms: $guideSavedTerms)
            }
        case .reportBug:
            BugReportSettingsView()
        }
    }
}
