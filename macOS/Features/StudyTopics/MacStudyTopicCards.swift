import SwiftUI

/// A Study Topic in the editorial collection card: its title, description and the first
/// conversations filed inside, as a ruled index.
struct MacStudyTopicCard: View {
    let topic: StudyTopic
    let members: [InquiryConversation]
    let memberTitle: (InquiryConversation) -> String
    var onSelect: () -> Void
    var onRename: () -> Void
    var onDelete: () -> Void
    var onOpenConversation: (InquiryConversation) -> Void

    private static let previewCount = 2

    private var menuEntries: [MacMenuEntry] { [
        MacMenuEntry("Open", symbol: "arrow.up.right", action: onSelect),
        MacMenuEntry("Rename", symbol: "pencil.line", action: onRename), .divider,
        MacMenuEntry("Delete", symbol: "trash", destructive: true, action: onDelete)
    ] }

    var body: some View {
        MacEditorialCard(kind: "Study Topic", symbol: "square.stack", date: topic.createdAt, height: 300) {
            MacActionMenu(entries: { menuEntries }) { MacCollectionCardOptionsLabel() }
                .buttonStyle(.plain)
                .accessibilityLabel("Topic options")
        } content: {
            Text(MacStudyTopicsView.displayTitle(topic))
                .font(AngroveTheme.Typography.heading)
                .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                .lineSpacing(2)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if !topic.description.isEmpty {
                Text(topic.description)
                    .paragraphFont()
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
                    .lineSpacing(5)
                    .lineLimit(2)
            }
            memberIndex
                .padding(.top, 4)
        } footer: {
            Image(systemName: "text.bubble")
            Text(members.count == 1 ? "1 conversation" : "\(members.count) conversations")
                .monospacedDigit()
            if members.count > Self.previewCount {
                Text(verbatim: "·")
                Text("\(members.count - Self.previewCount) more")
            }
            Spacer(minLength: 8)
        }
        .onTapGesture(perform: onSelect)
        .macCardHover()
        .macContextMenu { menuEntries }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Open"), onSelect)
    }

    @ViewBuilder private var memberIndex: some View {
        if members.isEmpty {
            Text("No conversations filed yet.")
                .font(AngroveTheme.Typography.body)
                .foregroundStyle(AngroveTheme.Colors.placeholderText)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { rule }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(members.prefix(Self.previewCount)) { conversation in
                    Button { onOpenConversation(conversation) } label: {
                        HStack(spacing: 10) {
                            Text(memberTitle(conversation))
                                .font(AngroveTheme.Typography.uiSubheading)
                                .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .angroveIcon(.xSmall, .strong)
                                .foregroundStyle(AngroveTheme.Colors.placeholderText)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(MacRowHoverStyle())
                    .overlay(alignment: .top) { rule }
                }
            }
        }
    }

    private var rule: some View {
        Rectangle().fill(AngroveTheme.Colors.divider).frame(height: 1)
    }
}

/// Rows inside a card darken their text slightly on hover rather than lifting.
struct MacRowHoverStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MacRowHoverBody(configuration: configuration)
    }
}

private struct MacRowHoverBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : isHovered ? 0.8 : 1)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

/// The first Study Topic, offered as a dashed blank volume.
struct MacStudyTopicPlaceholderGrid: View {
    var onCreate: () -> Void

    var body: some View {
        Button(action: onCreate) {
            HStack(alignment: .center, spacing: 28) {
                Image(systemName: "square.stack")
                    .angroveIcon(.hero)
                    .foregroundStyle(AngroveTheme.Colors.lightGreen)
                    .frame(width: 64, height: 64)
                    .background(AngroveTheme.Colors.canvasSecondary, in: Circle())
                    .overlay(Circle().stroke(AngroveTheme.Colors.controlBorder, lineWidth: 1))
                VStack(alignment: .leading, spacing: 8) {
                    Text("Begin your first Study Topic")
                        .font(AngroveTheme.Typography.title)
                        .foregroundStyle(AngroveTheme.Colors.headingText)
                    Text("Name a subject, such as the Desert Fathers or a summer Bible study, then file conversations under it from the sidebar.")
                        .paragraphFont()
                        .foregroundStyle(AngroveTheme.Colors.paragraphText)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.leading)
            .padding(36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: AngroveTheme.Spacing.cardRadius, style: .continuous)
                    .strokeBorder(AngroveTheme.Colors.controlBorder, style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
            }
            .contentShape(RoundedRectangle(cornerRadius: AngroveTheme.Spacing.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .macCardHover()
    }
}

/// An empty topic's conversation list, inviting the first one.
struct MacTopicEmptyConversations: View {
    var onStart: () -> Void

    var body: some View {
        Button(action: onStart) {
            HStack(spacing: 16) {
                Image(systemName: "plus")
                    .angroveIcon(.medium, .strong)
                    .foregroundStyle(AngroveTheme.Colors.lightGreen)
                    .frame(width: 40, height: 40)
                    .background(AngroveTheme.Colors.canvasSecondary, in: Circle())
                    .overlay(Circle().stroke(AngroveTheme.Colors.controlBorder, lineWidth: 1))
                VStack(alignment: .leading, spacing: 4) {
                    Text("No conversations yet")
                        .font(AngroveTheme.Typography.uiHeading)
                        .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                    Text("Start one here, or add an existing conversation using the controls below.")
                        .paragraphFont()
                        .foregroundStyle(AngroveTheme.Colors.paragraphText)
                }
                Spacer(minLength: 0)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: AngroveTheme.Spacing.cardRadius, style: .continuous)
                    .strokeBorder(AngroveTheme.Colors.controlBorder, style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
            }
            .contentShape(RoundedRectangle(cornerRadius: AngroveTheme.Spacing.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// A saved reference image, larger than the composer's strip, with removal on hover.
struct MacTopicImageTile: View {
    let file: UploadedFile
    var onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        MacAttachmentThumbnail(file: file)
            .aspectRatio(1, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: AngroveTheme.Spacing.smallCardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AngroveTheme.Spacing.smallCardRadius, style: .continuous)
                .stroke(AngroveTheme.Colors.quietBorder, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .angroveIcon(.xLarge)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(AngroveTheme.Colors.canvas, AngroveTheme.Colors.lightGreen)
                }
                .buttonStyle(.plain)
                .padding(8)
                .opacity(isHovered ? 1 : 0)
                .accessibilityLabel("Remove \(file.name)")
                .help("Remove image")
            }
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: 0.2), value: isHovered)
            .accessibilityLabel(file.name)
    }
}
