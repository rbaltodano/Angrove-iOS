import AppKit
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
    var isRenaming = false
    let onRename: () -> Void
    let onFinishRename: (String?) -> Void
    @State private var isHovered = false
    @FocusState private var optionsFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                if conversation.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(AngroveTheme.Colors.lightGreen)
                }
                if isRenaming {
                    MacSidebarRenameField(title: conversation.title, onFinish: onFinishRename)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                } else {
                    Button(action: onOpen) {
                        Text(conversation.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .highPriorityGesture(TapGesture(count: 2).onEnded { onRename() })
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityAction(named: Text("Rename"), onRename)
                    .help("Double-click to rename")
                }
                if isLoading {
                    ContextUsageIcon(progress: 0,
                        color: AngroveTheme.Colors.paragraphText.opacity(0.75), isSpinning: true)
                        .frame(width: 14, height: 14)
                        .accessibilityLabel("Model working")
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
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

/// Native field editing selects the entire title and preserves standard Mac text shortcuts.
struct MacSidebarRenameField: NSViewRepresentable {
    let title: String
    let onFinish: (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeNSView(context: Context) -> TitleField {
        let field = TitleField(string: title)
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.font = NSFont(name: "Figtree-Regular", size: BrandTypography.pointSize(MacConversationStyle.bodyFontSize.pointSize))
        field.textColor = NSColor(AngroveTheme.Colors.paragraphText)
        field.setAccessibilityLabel("Conversation name")
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: TitleField, context: Context) {
        context.coordinator.onFinish = onFinish
        field.textColor = NSColor(AngroveTheme.Colors.paragraphText)
    }

    static func dismantleNSView(_ field: TitleField, coordinator: Coordinator) {
        field.stopMonitoringClicks()
    }

    final class TitleField: NSTextField {
        private var clickMonitor: Any?

        func stopMonitoringClicks() {
            if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
            clickMonitor = nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoringClicks()
            guard window != nil else { return }
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                if let self, event.window === self.window,
                   self.currentEditor() != nil,
                   !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                    self.window?.makeFirstResponder(nil)
                }
                return event
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.selectText(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var onFinish: (String?) -> Void
        private var finished = false

        init(onFinish: @escaping (String?) -> Void) { self.onFinish = onFinish }

        private func finish(_ title: String?) {
            guard !finished else { return }
            finished = true
            onFinish(title)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            finish(field.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                finish(nil)
            } else if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                finish(textView.string)
            } else {
                return false
            }
            control.window?.makeFirstResponder(nil)
            return true
        }
    }
}
