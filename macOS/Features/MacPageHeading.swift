import SwiftUI

/// Mac headings use the same word renderer and visibility gate as the iPhone.
/// A changed title gets a fresh reveal, while scrolling back to it keeps it visible.
struct MacPageHeading: View {
    // Page titles use the app’s full 40pt scale, bypassing the desktop body-font cap.
    static let pageFont = Font.custom("LibreBaskerville-Regular", fixedSize: 40)

    let title: String
    var font: Font = AngroveTheme.Typography.uiHeading
    var color: Color = AngroveTheme.Colors.headingText

    var body: some View {
        SettingsAnimatedHeading(title: title, font: font, color: color)
            .id(title)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct MacPageIntroduction: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            MacPageHeading(title: title, font: MacPageHeading.pageFont)
                .lineSpacing(AngroveTheme.Typography.settingsGuideTitleLineSpacing)
            Text(description)
                .macStaticParagraph()
                .foregroundStyle(AngroveTheme.Colors.paragraphText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
