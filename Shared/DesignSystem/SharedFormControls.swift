import SwiftUI

/// Search fields and headings shared by iPhone and Mac pages.
struct StudyTopicsSearchField: View {
    @Binding var searchText: String
    var prompt: Text = Text("Search")
    var dismissFocusRequest = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            GlobalSearchGlass()

            TextField("", text: $searchText, prompt: SearchFieldPrompt.native(prompt))
                .textFieldStyle(.plain)
                .focusEffectDisabled()
                .font(GlobalSearchBarStyle.font)
                .searchFieldPrompt(prompt, isShown: searchText.isEmpty)
                .tint(AngroveTheme.Colors.secondaryMuted)
                .submitLabel(.search)
                .focused($isFocused)
                .onSubmit { isFocused = false }
                .onChange(of: dismissFocusRequest) { _, _ in isFocused = false }
        }
        .foregroundStyle(AngroveTheme.Colors.paragraphText)
        .modifier(GlobalSearchBarStyle())
    }
}

/// macOS ignores a styled `TextField` prompt and draws its own gray, so the Mac draws the prompt
/// itself in the placeholder color; iOS keeps the native, styled prompt.
enum SearchFieldPrompt {
    static func native(_ prompt: Text) -> Text? {
        #if os(macOS)
        nil
        #else
        prompt.foregroundStyle(AngroveTheme.Colors.placeholderText)
        #endif
    }
}

extension View {
    /// Apply after the field's font so the drawn prompt matches the typed text.
    @ViewBuilder func searchFieldPrompt(_ prompt: Text, isShown: Bool) -> some View {
        #if os(macOS)
        overlay(alignment: .leading) {
            if isShown {
                prompt
                    .foregroundStyle(AngroveTheme.Colors.placeholderText)
                    .lineLimit(1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(prompt)
        #else
        self
        #endif
    }
}

struct SettingsDetailHeading: View {
    let title: LocalizedStringResource

    var body: some View {
        let words = String(localized: title).split(separator: " ", omittingEmptySubsequences: false)
        let headingText = words.enumerated().reduce(Text(verbatim: "")) { text, word in
            text + Text(verbatim: (word.offset == 0 ? "" : " ") + String(word.element))
                .customAttribute(SettingsRevealWord(index: word.offset))
        }
        SettingsAnimatedHeading(
            text: headingText,
            wordCount: words.count,
            accessibilityLabel: String(localized: title)
        )
        .font(AngroveTheme.Typography.settingsDetailTitle)
        .tracking(AngroveTheme.Typography.settingsDetailTitleTracking)
        .foregroundStyle(AngroveTheme.Colors.headingText)
        .lineSpacing(AngroveTheme.Typography.settingsGuideTitleLineSpacing)
        .multilineTextAlignment(.leading)
        .lineLimit(words.count == 1 ? 1 : nil)
        .minimumScaleFactor(0.75)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
