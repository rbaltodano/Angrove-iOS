import SwiftUI

/// A Study Topic: the serif title, its description and the first few conversations filed inside,
/// as a ruled index.
struct MacStudyTopicCard: View {
    let topic: StudyTopic
    let members: [InquiryConversation]
    let memberTitle: (InquiryConversation) -> String
    var onSelect: () -> Void
    var onRename: () -> Void
    var onDelete: () -> Void
    var onOpenConversation: (InquiryConversation) -> Void

    private static let previewCount = 3

    private var menuEntries: [MacMenuEntry] { [
        MacMenuEntry("Open", symbol: "arrow.up.right", action: onSelect),
        MacMenuEntry("Rename", symbol: "pencil.line", action: onRename), .divider,
        MacMenuEntry("Delete", symbol: "trash", destructive: true, action: onDelete)
    ] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack")
                    .angroveIcon(.medium)
                Text(members.count == 1 ? "1 CONVERSATION" : "\(members.count) CONVERSATIONS")
                    .font(AngroveTheme.Typography.uiLabel)
                    .monospacedDigit()
                Spacer(minLength: 8)
                MacActionMenu(entries: { menuEntries }) { MacCollectionCardOptionsLabel() }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Topic options")
            }
            .foregroundStyle(AngroveTheme.Colors.lightGreen)

            Text(MacStudyTopicsView.displayTitle(topic))
                .font(AngroveTheme.Typography.title)
                .foregroundStyle(AngroveTheme.Colors.headingText)
                .lineSpacing(4)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)

            if !topic.description.isEmpty {
                Text(topic.description)
                    .paragraphFont()
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
                    .lineSpacing(5)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }

            Spacer(minLength: 20)

            if members.isEmpty {
                Text("No conversations filed yet.")
                    .font(AngroveTheme.Typography.body)
                    .foregroundStyle(AngroveTheme.Colors.placeholderText)
                    .padding(.vertical, 10)
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
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(MacRowHoverStyle())
                        .overlay(alignment: .top) { rule }
                    }
                    if members.count > Self.previewCount {
                        Text("+ \(members.count - Self.previewCount) more")
                            .font(AngroveTheme.Typography.uiLabel)
                            .foregroundStyle(AngroveTheme.Colors.lightGreen)
                            .padding(.top, 10)
                            .overlay(alignment: .top) { rule }
                    }
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        .macCollectionCard()
        .onTapGesture(perform: onSelect)
        .macCardHover()
        .macContextMenu { menuEntries }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Open"), onSelect)
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

/// One conversation in a topic's ruled index: its number, title, latest line and date.
struct MacTopicConversationRow: View {
    let index: Int
    let title: String
    let preview: String
    let date: Date
    let isPinned: Bool
    var onOpen: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 20) {
                Text(index.formatted(.number.precision(.integerLength(2))))
                    .font(AngroveTheme.Typography.heading)
                    .foregroundStyle(AngroveTheme.Colors.lightGreen)
                    .monospacedDigit()
                    .frame(width: 32, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if isPinned {
                            Image(systemName: "pin.fill")
                                .angroveIcon(.xSmall)
                                .foregroundStyle(AngroveTheme.Colors.lightGreen)
                        }
                        Text(title)
                            .font(AngroveTheme.Typography.uiHeading)
                            .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                            .lineLimit(1)
                    }
                    Text(verbatim: preview)
                        .font(AngroveTheme.Typography.body)
                        .foregroundStyle(AngroveTheme.Colors.placeholderText)
                        .lineLimit(1)
                }
                Spacer(minLength: 16)
                Text(MacCollectionDate.short(date))
                    .font(AngroveTheme.Typography.chipLabel)
                    .foregroundStyle(AngroveTheme.Colors.placeholderText)
                Image(systemName: "chevron.right")
                    .angroveIcon(.small, .strong)
                    .foregroundStyle(isHovered ? AngroveTheme.Colors.lightGreen : AngroveTheme.Colors.placeholderText)
                    .offset(x: isHovered ? 2 : 0)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AngroveTheme.Colors.systemSelection.opacity(isHovered ? 1 : 0))
                    .padding(.horizontal, 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.springQuick, value: isHovered)
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
