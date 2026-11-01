import SwiftUI

/// Pure presentation shared by the collection's resume and grid cards.
struct MacConversationCardContent<Options: View>: View {
    let title: String
    let preview: String
    let createdAt: Date
    let topicTitle: String?
    let answerCount: Int
    let isPinned: Bool
    @ViewBuilder var options: Options

    var body: some View {
        MacEditorialCard(kind: "Conversation", symbol: "bubble.left.and.bubble.right", date: createdAt) {
            options
        } content: {
            Text(title)
                .font(AngroveTheme.Typography.heading)
                .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                .lineSpacing(2)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: preview)
                .paragraphFont()
                .foregroundStyle(AngroveTheme.Colors.paragraphText)
                .lineSpacing(5)
                .lineLimit(3)
        } footer: {
            if let topicTitle {
                Label(topicTitle, systemImage: "folder")
            } else {
                Image(systemName: "text.bubble")
                if answerCount == 1 {
                    Text("1 answer")
                } else {
                    Text("\(answerCount) answers")
                }
            }
            Spacer(minLength: 8)
            if isPinned {
                Image(systemName: "pin.fill")
                    .accessibilityLabel("Pinned")
            }
        }
    }
}

/// The editorial collection card: a kind-and-date strip, a rule, then the card's own content
/// above a green footer that ends in the open arrow. Conversations, Study Topics and Boards share it.
struct MacEditorialCard<Options: View, Content: View, Footer: View>: View {
    let kind: LocalizedStringKey
    let symbol: String
    let date: Date
    var height: CGFloat = 270
    @ViewBuilder var options: Options
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            MacEditorialCardMetadata(kind: kind, symbol: symbol, date: date, options: options)
            Rectangle()
                .fill(AngroveTheme.Colors.controlBorder)
                .frame(height: 1)
            VStack(alignment: .leading, spacing: 10) {
                content
                Spacer(minLength: 16)
                HStack(spacing: 6) {
                    footer
                    Image(systemName: "arrow.up.right")
                        .accessibilityHidden(true)
                }
                .font(AngroveTheme.Typography.body)
                .foregroundStyle(AngroveTheme.Colors.lightGreen)
                .lineLimit(1)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(AngroveTheme.Colors.canvasSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AngroveTheme.Spacing.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AngroveTheme.Spacing.cardRadius, style: .continuous)
                .stroke(AngroveTheme.Colors.controlBorder, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: AngroveTheme.Spacing.cardRadius, style: .continuous))
    }
}

private struct MacEditorialCardMetadata<Options: View>: View {
    let kind: LocalizedStringKey
    let symbol: String
    let date: Date
    let options: Options

    var body: some View {
        HStack(spacing: 6) {
            Label(kind, systemImage: symbol)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 4)
            Text(date, format: .dateTime.month(.abbreviated).day().year())
                .lineLimit(1)
                .truncationMode(.tail)
            options
        }
        .font(AngroveTheme.Typography.body)
        .foregroundStyle(AngroveTheme.Colors.placeholderText)
        .padding(.leading, 28)
        .padding(.trailing, 14)
    }
}
