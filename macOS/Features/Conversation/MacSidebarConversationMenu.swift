import AppKit
import SwiftUI

enum MacSidebarConversationMenuAction: CaseIterable {
    case rename, pin, topic, delete

    func title(for conversation: InquiryConversation) -> LocalizedStringResource {
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
    var shortcutNumber: Int? = nil
    var showsShortcut = false
    var isLoading = false
    let onOpen: () -> Void
    let onMenu: () -> Void
    var isRenaming = false
    let onRename: () -> Void
    let onFinishRename: (String?) -> Void
    var contextEntries: () -> [MacMenuEntry] = { [] }
    @State private var isHovered = false
    @State private var shortcutVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var optionsFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                if conversation.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(AngroveTheme.Colors.lightGreen)
                }
                ZStack(alignment: .leading) {
                    if isRenaming {
                        MacSidebarRenameField(title: conversation.title, onFinish: onFinishRename)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .transition(reduceMotion ? .opacity : .blurFade)
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
                        // A new identity per title, so a rename blurs the old name out and the new one in.
                        .id(conversation.title)
                        .transition(reduceMotion ? .opacity : .blurFade)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.3), value: isRenaming)
                .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.3), value: conversation.title)
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
        .padding(.leading, shortcutVisible ? 44 : 16)
        .padding(.trailing, 16)
        .background(isSelected || isHovered || isMenuOpen ? AngroveTheme.Colors.sideMenuSelection : .clear,
                    in: RoundedRectangle(cornerRadius: AngroveTheme.Spacing.selectionRadius, style: .continuous))
        .overlay(alignment: .leading) {
            Text(shortcutNumber.map { "⌘\($0)" } ?? "")
                .font(AngroveTheme.Typography.body)
                .foregroundStyle(AngroveTheme.Colors.paragraphText)
                .frame(width: 24)
                .padding(.leading, 12)
                .opacity(shortcutVisible ? 0.5 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .macContextMenu { isRenaming ? [] : contextEntries() }
        .onHover { isHovered = $0 }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
        .task(id: ShortcutPresentation(number: shortcutNumber, isHeld: showsShortcut)) {
            guard showsShortcut, let shortcutNumber else {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { shortcutVisible = false }
                return
            }
            if !reduceMotion {
                do {
                    try await Task.sleep(for: .seconds(Double(shortcutNumber - 1) * 0.05))
                } catch { return }
            }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.15)) { shortcutVisible = true }
        }
    }

    private struct ShortcutPresentation: Equatable {
        let number: Int?
        let isHeld: Bool
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

struct MacSidebarConversationMenu: View {
    let conversation: InquiryConversation
    let onAction: (MacSidebarConversationMenuAction) -> Void

    static func entries(for conversation: InquiryConversation, onAction: @escaping (MacSidebarConversationMenuAction) -> Void) -> [MacMenuEntry] {
        MacSidebarConversationMenuAction.allCases.flatMap { action -> [MacMenuEntry] in
            let entry = MacMenuEntry(action.title(for: conversation), symbol: action.symbol(for: conversation), destructive: action == .delete) { onAction(action) }
            return action == .delete ? [.divider, entry] : [entry]
        }
    }
    var body: some View {
        MacMenuContent(entries: Self.entries(for: conversation, onAction: onAction)) { $0.action() }
            .modifier(MacMenuScaleIn())
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
                // The sidebar can re-attach the field; selectText on a field already being
                // edited ends that edit first, which would commit and close the rename.
                guard let self, self.window != nil, self.currentEditor() == nil else { return }
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
