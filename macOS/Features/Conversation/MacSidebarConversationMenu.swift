import SwiftUI

enum MacSidebarConversationMenuAction: CaseIterable {
    case rename, pin, topic, delete

    func title(for conversation: InquiryConversation) -> LocalizedStringKey {
        switch self {
        case .rename: "Rename"
        case .pin: conversation.isPinned ? "Unpin" : "Pin"
        case .topic: conversation.studyTopicID == nil ? "Add to Study Topic" : "Remove from Study Topic"
        case .delete: "Delete"
        }
    }

    func symbol(for conversation: InquiryConversation) -> String {
        switch self {
        case .rename: "pencil.line"
        case .pin: conversation.isPinned ? "pin.slash" : "pin"
        case .topic: "square.stack"
        case .delete: "trash"
        }
    }
}

struct MacSidebarMenuAnchorKey: PreferenceKey {
    static var defaultValue: [UUID: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct MacSidebarConversationRow: View {
    let conversation: InquiryConversation
    let isSelected: Bool
    let isMenuOpen: Bool
    var isLoading = false
    let onOpen: () -> Void
    let onMenu: () -> Void
    @State private var isHovered = false
    @FocusState private var optionsFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    if conversation.isPinned {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(AngroveTheme.Colors.lightGreen)
                    }
                    Text(conversation.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isLoading {
                        ContextUsageIcon(progress: 0,
                            color: AngroveTheme.Colors.paragraphText.opacity(0.75), isSpinning: true)
                            .frame(width: 14, height: 14)
                            .accessibilityLabel("Model working")
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            Button(action: onMenu) {
                MacIconView(icon: .ellipsis)
                    .frame(width: 28, height: 32)
                    .contentShape(Rectangle())
            }
            .focused($optionsFocused)
            .opacity(isHovered || isMenuOpen || optionsFocused ? 1 : 0)
            .accessibilityLabel("Conversation options for \(conversation.title)")
            .help("Conversation options")
            .anchorPreference(key: MacSidebarMenuAnchorKey.self, value: .bounds) { [conversation.id: $0] }
        }
        .font(AngroveTheme.Typography.body)
        .foregroundStyle(AngroveTheme.Colors.paragraphText)
        .padding(.horizontal, 12)
        .background(isSelected || isHovered || isMenuOpen ? AngroveTheme.Colors.systemSelection : .clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}

struct MacSidebarConversationMenuOverlay: View {
    let conversations: [InquiryConversation]
    @Binding var menuID: UUID?
    let anchors: [UUID: Anchor<CGRect>]
    let onAction: (MacSidebarConversationMenuAction, InquiryConversation) -> Void
    @State private var menuHeight: CGFloat = 181

    var body: some View {
        GeometryReader { geometry in
            if let menuID, let anchor = anchors[menuID],
               let conversation = conversations.first(where: { $0.id == menuID }) {
                let bounds = geometry[anchor]
                let width: CGFloat = 260
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { self.menuID = nil }
                        .accessibilityLabel("Dismiss conversation menu")
                        .accessibilityAddTraits(.isButton)
                    MacSidebarConversationMenu(conversation: conversation) { action in
                        onAction(action, conversation)
                    }
                    .frame(width: width)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { menuHeight = $0 }
                    .offset(x: min(max(12, bounds.maxX - width), max(12, geometry.size.width - width - 12)),
                            y: min(max(12, bounds.maxY + 8), max(12, geometry.size.height - menuHeight - 12)))
                }
            }
        }
    }
}

private struct MacSidebarConversationMenu: View {
    let conversation: InquiryConversation
    let onAction: (MacSidebarConversationMenuAction) -> Void

    var body: some View {
        VStack(spacing: 4) {
            ForEach(MacSidebarConversationMenuAction.allCases, id: \.self) { action in
                if action == .delete {
                    Rectangle().fill(AngroveTheme.Colors.border).frame(height: 1)
                }
                MacSidebarConversationMenuButton(action: action, conversation: conversation,
                                                onSelect: { onAction(action) })
            }
        }
        .padding(12)
        .background(AngroveTheme.Colors.canvasSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AngroveTheme.Colors.border, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .buttonStyle(.plain)
    }
}

private struct MacSidebarConversationMenuButton: View {
    let action: MacSidebarConversationMenuAction
    let conversation: InquiryConversation
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(role: action == .delete ? .destructive : nil, action: onSelect) {
            Label(action.title(for: conversation), systemImage: action.symbol(for: conversation))
                .font(AngroveTheme.Typography.body)
                .foregroundStyle(action == .delete ? AngroveTheme.Colors.accentRed : AngroveTheme.Colors.paragraphText)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .padding(.horizontal, 8)
                .background(isHovered ? AngroveTheme.Colors.systemSelection : .clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .onHover { isHovered = $0 }
    }
}
