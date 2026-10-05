//
//  SettingsComponents.swift
//  Angrove-iOS
//

import SwiftUI
import UIKit

// MARK: - Shared Layout

struct SettingsPageScaffold<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: LocalizedStringResource
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            AngroveTheme.Colors.canvas
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .center, spacing: 48) {
                    Text(title)
                        .font(AngroveTheme.Typography.settingsTitle)
                        .foregroundStyle(AngroveTheme.Colors.headingText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? -24 : 0)

                    content
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 80)
                }
                .padding(.horizontal, 24)
                .padding(.top, 96)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }
}

struct SettingsDetailScaffold<Content: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder let content: Content

    var body: some View {
        SettingsPageScaffold(title: title) {
            content
        }
    }
}

struct SettingsControlCard<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(dynamicTypeSize.isAccessibilitySize
            ? AngroveTheme.Spacing.screenPadding
            : AngroveTheme.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AngroveTheme.Colors.canvasSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

struct SettingsSubsection<Content: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AngroveTheme.Typography.settingsHeading)
                .foregroundStyle(AngroveTheme.Colors.headingText)

            SettingsControlCard {
                content
            }
        }
    }
}

struct SettingsLabeledControl<Content: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .settingsText(.label)
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
                    .fixedSize()
                Spacer(minLength: 8)
                content.fixedSize()
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .settingsText(.label)
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
                    .fixedSize(horizontal: false, vertical: true)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
    }
}

struct SettingsChoiceRow<Option: SettingsChoice>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: LocalizedStringResource
    var detail: LocalizedStringResource?
    @Binding var selection: Option
    let options: [Option]

    init(
        title: LocalizedStringResource,
        detail: LocalizedStringResource? = nil,
        selection: Binding<Option>,
        options: [Option]
    ) {
        self.title = title
        self.detail = detail
        _selection = selection
        self.options = options
    }

    var body: some View {
        settingsRowLayout(isVertical: dynamicTypeSize.isAccessibilitySize).callAsFunction {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .settingsText(.label)
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)

                if let detail {
                    Text(detail)
                        .settingsText(.detail)
                        .foregroundStyle(AngroveTheme.Colors.placeholderText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 8)
            }

            Menu {
                ForEach(options) { option in
                    Button {
                        SettingsHaptics.playSelection()
                        selection = option
                    } label: {
                        HStack {
                            Text(option.title)
                            if option == selection {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    BlurSwapText(Text(selection.title), value: selection)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .settingsText(.label)
                .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                .animation(.springStandard, value: selection)
            }
            .buttonStyle(.plain)
            .pulsesOnChange(of: selection, anchor: .trailing)
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
    }
}

struct SettingsToggleRow: View {
    let title: LocalizedStringResource
    var detail: LocalizedStringResource?
    @Binding var isOn: Bool

    init(
        title: LocalizedStringResource,
        detail: LocalizedStringResource? = nil,
        isOn: Binding<Bool>
    ) {
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .settingsText(.label)
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)

                if let detail {
                    Text(detail)
                        .settingsText(.detail)
                        .foregroundStyle(AngroveTheme.Colors.placeholderText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(AngroveTheme.Colors.darkGreen)
        .onChange(of: isOn) { _, _ in
            SettingsHaptics.playSelection()
        }
    }
}

struct SettingsTextInputRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: LocalizedStringResource
    let placeholder: LocalizedStringResource
    @Binding var text: String

    var body: some View {
        settingsRowLayout(isVertical: dynamicTypeSize.isAccessibilitySize).callAsFunction {
            Text(title)
                .settingsText(.label)
                .foregroundStyle(AngroveTheme.Colors.paragraphText)

            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 8)
            }

            TextField("", text: $text, prompt: Text(placeholder))
                .settingsText(.control)
                .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                .tint(AngroveTheme.Colors.darkGreen)
        }
        .frame(minHeight: 32)
    }
}

struct SettingsNavigationLabel: View {
    let title: LocalizedStringResource
    var detail: LocalizedStringResource?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .settingsText(.label)
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)

                if let detail {
                    Text(detail)
                        .settingsText(.detail)
                        .foregroundStyle(AngroveTheme.Colors.placeholderText)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AngroveTheme.Colors.placeholderText)
        }
        .frame(maxWidth: .infinity, minHeight: 32)
        .contentShape(Rectangle())
    }
}

struct SettingsUnavailableActionRow: View {
    let title: LocalizedStringResource
    var isDestructive = false

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .settingsText(.label)
                .foregroundStyle(
                    isDestructive
                        ? AngroveTheme.Colors.accentRed.opacity(0.45)
                        : AngroveTheme.Colors.paragraphText.opacity(0.45)
                )

            Spacer()

            Text("Coming Soon")
                .settingsText(.detail)
                .foregroundStyle(AngroveTheme.Colors.placeholderText)
        }
        .frame(maxWidth: .infinity, minHeight: 28)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Unavailable")
    }
}

// MARK: - Segmented Controls

struct AppearanceButton: View {
    let option: AppearanceOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: option.iconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(
                    isSelected
                        ? AngroveTheme.Colors.lightGreen
                        : AngroveTheme.Colors.placeholderText
                )
                .frame(width: 28, height: 28)
                .background(
                    isSelected
                        ? AngroveTheme.Colors.deepSurface
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct PersonalitySegmentedControl: View {
    @Binding var selection: ConversationPersonality
    @Namespace private var selectionNamespace
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        settingsSegmentLayout(isVertical: dynamicTypeSize.isAccessibilitySize).callAsFunction {
            ForEach(ConversationPersonality.allCases) { option in
                Button {
                    guard selection != option else { return }
                    SettingsHaptics.playSelection()
                    withAnimation(.springQuick) {
                        selection = option
                    }
                } label: {
                    Text(option.displayName)
                        .settingsText(.label)
                        .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background {
                            if selection == option {
                                Capsule()
                                    .fill(AngroveTheme.Colors.canvas)
                                    .matchedGeometryEffect(
                                        id: "personality-selection",
                                        in: selectionNamespace
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.displayName)
                .accessibilityHint(option.shortDescription)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(4)
        .overlay {
            Capsule()
                .stroke(AngroveTheme.Colors.border, lineWidth: 1)
        }
    }
}

struct ConversationAlignmentSegmentedControl: View {
    @Binding var selection: ConversationTextAlignmentOption
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ConversationTextAlignmentOption.allCases) { option in
                Button {
                    guard selection != option else { return }
                    SettingsHaptics.playSelection()
                    withAnimation(.springQuick) {
                        selection = option
                    }
                } label: {
                    Image(systemName: option.iconName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                        .frame(width: 44, height: 26)
                        .background {
                            if selection == option {
                                Capsule()
                                    .fill(AngroveTheme.Colors.canvas)
                                    .matchedGeometryEffect(
                                        id: "conversation-alignment-selection",
                                        in: selectionNamespace
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.accessibilityLabel)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(4)
        .overlay {
            Capsule()
                .stroke(AngroveTheme.Colors.border, lineWidth: 1)
        }
    }
}

struct FontSizeSegmentedControl: View {
    @Binding var selection: ConversationFontSizeOption
    @Namespace private var selectionNamespace
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        settingsSegmentLayout(isVertical: dynamicTypeSize.isAccessibilitySize).callAsFunction {
            ForEach(ConversationFontSizeOption.allCases) { option in
                Button {
                    guard selection != option else { return }
                    SettingsHaptics.playSelection()
                    withAnimation(.springQuick) {
                        selection = option
                    }
                } label: {
                    Text(option.rawValue)
                        .settingsText(.label)
                        .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                        .padding(.horizontal, 8)
                        .frame(minWidth: 54, minHeight: 30)
                        .background {
                            if selection == option {
                                Capsule()
                                    .fill(AngroveTheme.Colors.canvas)
                                    .matchedGeometryEffect(
                                        id: "font-size-selection",
                                        in: selectionNamespace
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(4)
        .overlay {
            Capsule()
                .stroke(AngroveTheme.Colors.border, lineWidth: 1)
        }
    }
}

struct FontSegmentedControl: View {
    @Binding var selection: ConversationFontOption
    @Namespace private var selectionNamespace
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        settingsSegmentLayout(isVertical: dynamicTypeSize.isAccessibilitySize).callAsFunction {
            ForEach(ConversationFontOption.allCases) { option in
                Button {
                    guard selection != option else { return }
                    SettingsHaptics.playSelection()
                    withAnimation(.springQuick) {
                        selection = option
                    }
                } label: {
                    Text(option.rawValue)
                        .settingsText(.label)
                        .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                        .padding(.horizontal, 8)
                        .frame(minWidth: 54, minHeight: 30)
                        .background {
                            if selection == option {
                                Capsule()
                                    .fill(AngroveTheme.Colors.canvas)
                                    .matchedGeometryEffect(
                                        id: "font-selection",
                                        in: selectionNamespace
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(4)
        .overlay {
            Capsule()
                .stroke(AngroveTheme.Colors.border, lineWidth: 1)
        }
    }
}

private func settingsSegmentLayout(isVertical: Bool) -> AnyLayout {
    isVertical
        ? AnyLayout(VStackLayout(spacing: 4))
        : AnyLayout(HStackLayout(spacing: 4))
}

private func settingsRowLayout(isVertical: Bool) -> AnyLayout {
    isVertical
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
        : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
}

enum SettingsHaptics {
    static var isEnabled: Bool {
        let defaults = PrivatePreferences.standard
        guard defaults.object(forKey: SettingsStorageKey.hapticFeedback) != nil else {
            return true
        }
        return defaults.bool(forKey: SettingsStorageKey.hapticFeedback)
    }

    static func playSelection() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func playDoubleSelection() async {
        guard isEnabled else { return }
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.prepare()
        feedback.impactOccurred()
        do {
            try await Task.sleep(for: .milliseconds(100))
        } catch {
            return
        }
        guard isEnabled else { return }
        feedback.impactOccurred()
    }
}
