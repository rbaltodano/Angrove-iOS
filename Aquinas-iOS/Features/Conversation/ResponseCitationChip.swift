import SwiftUI

// MARK: - Source Citation Chip

/// Inline chip naming the corpus passage a sentence quotes; tapping opens it in the Library.
struct ResponseCitationChip: View {
    let link: ParsedInsightLink
    let textFont: Font
    let fontSize: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Text(link.leadingPunctuation)
                .font(textFont)
                .foregroundColor(AquinasTheme.Colors.bodyText)
            Button(action: open) {
                Text(link.title)
                    .font(.custom("Figtree-Bold", size: max(12, fontSize - 3)))
                    .foregroundStyle(AquinasTheme.Colors.lightGreen)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
                    // The capsule overhangs the text vertically without taking layout space, so
                    // the chip keeps the line's height and its punctuation stays on the prose baseline.
                    .background(
                        Capsule()
                            .fill(AquinasTheme.Colors.systemSelection)
                            .padding(.vertical, -4)
                    )
                    .contentShape(Capsule().inset(by: -4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Source: \(link.title)")
            .accessibilityHint("Opens the passage in the Library")
            Text(link.trailingPunctuation)
                .font(textFont)
                .foregroundColor(AquinasTheme.Colors.bodyText)
        }
    }

    private func open() {
        guard let target = ResponseCitationMarkup.target(from: link.url) else { return }
        NotificationCenter.default.post(
            name: .openGroundingSourceInLibrary,
            object: LibraryNavigationRequest(
                sourceTitle: link.title,
                sourceName: link.title,
                sourceID: target.sourceID,
                chunkIndex: target.chunkIndex
            )
        )
    }
}
