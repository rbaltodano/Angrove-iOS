import SwiftUI

/// Search fields and headings shared by iPhone and Mac pages.
struct StudyTopicsSearchField: View {
    @Binding var searchText: String
    var prompt: Text = Text("Search")
    var dismissFocusRequest = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AngroveTheme.Colors.searchIcon)
                .frame(width: 16, height: 16)

            TextField("", text: $searchText, prompt: prompt)
                .textFieldStyle(.plain)
                .focusEffectDisabled()
                .paragraphFont()
                .foregroundColor(AngroveTheme.Colors.paragraphText)
                .tint(AngroveTheme.Colors.secondaryMuted)
                .submitLabel(.search)
                .focused($isFocused)
                .onSubmit { isFocused = false }
                .onChange(of: dismissFocusRequest) { _, _ in isFocused = false }
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
        .background(AngroveTheme.Colors.canvas)
        .clipShape(RoundedRectangle(cornerRadius: AngroveTheme.Spacing.selectionRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AngroveTheme.Spacing.selectionRadius, style: .continuous)
                .stroke(AngroveTheme.Colors.sideMenuSearchBorder, lineWidth: 1)
        )
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
