import AppKit
import SwiftUI

struct MacMenuEntry: Identifiable {
    let id = UUID()
    var title: String
    var symbol: String = ""
    var image: NSImage?
    var destructive = false
    var enabled = true
    var separator = false
    var isNavigationBack = false
    /// Shown dimmed at the trailing edge, as a native menu shows a key equivalent.
    var shortcut: String?
    var children: [MacMenuEntry] = []
    var action: () -> Void = {}

    init(_ title: LocalizedStringResource, symbol: String = "", destructive: Bool = false, enabled: Bool = true,
         shortcut: String? = nil, action: @escaping () -> Void) {
        self.title = String(localized: title)
        self.symbol = symbol
        self.shortcut = shortcut
        self.destructive = destructive
        self.enabled = enabled
        self.action = action
    }
    private init(separator: Bool) { title = ""; self.separator = separator }
    static var divider: Self { Self(separator: true) }

    static func native(_ menu: NSMenu) -> [Self] {
        menu.update()
        return menu.items.enumerated().filter { !$0.element.isHidden }.map { index, item in
            if item.isSeparatorItem { return .divider }
            var entry = Self(LocalizedStringResource(stringLiteral: item.title), enabled: item.isEnabled) {
                menu.performActionForItem(at: index)
            }
            entry.image = item.image
            if let submenu = item.submenu { entry.children = native(submenu) }
            let symbols = ["copy:": "doc.on.doc", "cut:": "scissors", "paste:": "doc.on.clipboard", "selectAll:": "selection.pin.in.out"]
            if let selector = item.action { entry.symbol = symbols[NSStringFromSelector(selector)] ?? "" }
            if item.state == .on { entry.symbol = "checkmark" }
            return entry
        }
    }
}

/// Menus open together: the surface scales up from its anchor while the text blurs and fades in.
struct MacMenuScaleIn: ViewModifier {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown || reduceMotion ? 1 : 0.92, anchor: .top)
            .onAppear {
                withAnimation(reduceMotion ? nil : MacMenuAppearance.animation) { shown = true }
            }
    }
}

struct MacMenuTextReveal: ViewModifier {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .blur(radius: shown || reduceMotion ? 0 : 6)
            .onAppear {
                withAnimation(reduceMotion ? nil : MacMenuAppearance.animation) { shown = true }
            }
    }
}

enum MacMenuAppearance {
    static let animation = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.22)
}

/// Shared by the sidebar overlay and every other in-app menu.
struct MacMenuContent: View {
    let entries: [MacMenuEntry]
    var selectedID: UUID? = nil
    let select: (MacMenuEntry) -> Void

    var body: some View {
        VStack(spacing: 4) {
            ForEach(entries) { entry in
                if entry.separator {
                    Rectangle().fill(AngroveTheme.Colors.border).frame(height: 1)
                } else {
                    MacMenuRow(entry: entry, selected: selectedID == entry.id, select: { select(entry) })
                }
            }
        }
        .modifier(MacMenuTextReveal())
        .padding(12)
        .frame(width: 260)
        .background(AngroveTheme.Colors.canvasSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AngroveTheme.Colors.border, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .buttonStyle(.plain)
    }
}

private struct MacMenuRow: View {
    let entry: MacMenuEntry
    let selected: Bool
    let select: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(role: entry.destructive ? .destructive : nil, action: select) {
            HStack(spacing: 8) {
                if !entry.symbol.isEmpty { Image(systemName: entry.symbol).frame(width: 16) }
                else if let image = entry.image { Image(nsImage: image).resizable().renderingMode(.template).scaledToFit().frame(width: 16, height: 16) }
                else { Color.clear.frame(width: 16, height: 16).accessibilityHidden(true) }
                Text(entry.title).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let shortcut = entry.shortcut { Text(verbatim: shortcut).opacity(0.5).padding(.leading, 12) }
                if !entry.children.isEmpty { Image(systemName: "chevron.right") }
            }
            .font(AngroveTheme.Typography.body)
            .foregroundStyle(entry.destructive ? AngroveTheme.Colors.accentRed : AngroveTheme.Colors.paragraphText)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .padding(.horizontal, 8)
            .background(hovered || selected ? AngroveTheme.Colors.systemSelection : .clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .disabled(!entry.enabled)
        .opacity(entry.enabled ? 1 : 0.5)
        .onHover { hovered = $0 }
    }
}

struct MacActionMenu<Label: View>: View {
    let entries: () -> [MacMenuEntry]
    @ViewBuilder let label: Label
    @State private var anchor: NSView?
    var body: some View {
        Button {
            guard let anchor, let window = anchor.window else { return }
            let rect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let items = entries()
            let height = MacMenuPresenter.height(for: items)
            let bottom = window.screen?.visibleFrame.minY ?? 0
            let y = rect.minY - 8 - height < bottom + 8 ? rect.maxY + 8 + height : rect.minY - 8
            MacMenuPresenter.shared.show(items, at: CGPoint(x: rect.minX, y: y), in: window)
        } label: { label }
        .background(MacMenuAnchor { anchor = $0 })
    }
}

private struct MacMenuAnchor: NSViewRepresentable {
    let update: (NSView) -> Void
    func makeNSView(context: Context) -> NSView { let view = NSView(); DispatchQueue.main.async { update(view) }; return view }
    func updateNSView(_ view: NSView, context: Context) {}
}

@MainActor @Observable
final class MacMenuState {
    var entries: [MacMenuEntry] = []
    var selectedID: UUID?
    var ancestors: [[MacMenuEntry]] = []
    var selectable: [MacMenuEntry] { entries.filter { !$0.separator && $0.enabled && !$0.isNavigationBack } }
    func move(_ step: Int) {
        let values = selectable
        guard !values.isEmpty else { return }
        let current = values.firstIndex { $0.id == selectedID }
        let index = current.map { ($0 + step + values.count) % values.count } ?? (step > 0 ? 0 : values.count - 1)
        selectedID = values[index].id
    }
}

private struct MacMenuPanelContent: View {
    let state: MacMenuState
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                MacMenuContent(entries: state.entries, selectedID: state.selectedID, select: MacMenuPresenter.shared.select)
            }
            .onChange(of: state.selectedID) { _, id in
                if let id { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .background(AngroveTheme.Colors.canvasSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        // The system shadow outlines a clear panel in a dark ring, so the shadow is drawn here instead.
        .shadow(color: AngroveTheme.Colors.floatingShadow, radius: 14, y: 6)
        .padding(MacMenuPresenter.shadowInset)
        .modifier(MacMenuScaleIn())
    }
}

@MainActor final class MacMenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {
        let presenter = MacMenuPresenter.shared
        if event.modifierFlags.contains(.command) {
            let symbols = ["c": "doc.on.doc", "x": "scissors", "v": "doc.on.clipboard"]
            if let symbol = symbols[event.charactersIgnoringModifiers ?? ""],
               let entry = presenter.state.selectable.first(where: { $0.symbol == symbol }) {
                presenter.select(entry)
            } else {
                presenter.dismiss()
                NSApp.mainMenu?.performKeyEquivalent(with: event)
            }
            return
        }
        switch event.keyCode {
        case 53: presenter.dismiss()
        case 125: presenter.state.move(1)
        case 126: presenter.state.move(-1)
        case 36, 76, 124:
            if let entry = presenter.state.selectable.first(where: { $0.id == presenter.state.selectedID }) { presenter.select(entry) }
        case 123: presenter.back()
        case 48: presenter.dismiss()
        default:
            if let query = event.charactersIgnoringModifiers?.lowercased(), !query.isEmpty,
               let entry = presenter.state.selectable.first(where: { $0.title.lowercased().hasPrefix(query) }) {
                presenter.state.selectedID = entry.id
            }
        }
    }
}

@MainActor final class MacMenuPresenter {
    static let shared = MacMenuPresenter()
    let state = MacMenuState()
    private(set) var panel: MacMenuPanel?
    private weak var sourceWindow: NSWindow?
    private var monitor: Any?
    private var deactivate: NSObjectProtocol?
    private var origin = CGPoint.zero

    func show(_ entries: [MacMenuEntry], at point: CGPoint, in window: NSWindow) {
        dismiss()
        guard entries.contains(where: { !$0.separator }) else { return }
        NotificationCenter.default.post(name: .macActionMenuWillOpen, object: nil)
        state.entries = entries
        state.selectedID = nil
        state.ancestors = []
        origin = point
        sourceWindow = window
        let panel = MacMenuPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = String(localized: "Actions")
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.contentView = NSHostingView(rootView: MacMenuPanelContent(state: state).environment(\.colorScheme,
            window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light))
        self.panel = panel
        layout()
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]) { [weak self] event in
            if event.type == .keyDown {
                if event.window === self?.panel { self?.panel?.keyDown(with: event); return nil }
            } else if event.window !== self?.panel { self?.dismiss() }
            return event
        }
        deactivate = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    func layout() {
        guard let panel else { return }
        let naturalHeight = Self.height(for: state.entries)
        let screen = NSScreen.screens.first { $0.frame.contains(origin) } ?? sourceWindow?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1000, height: 800)
        let inset = Self.shadowInset
        let frame = Self.placement(origin: origin, size: CGSize(width: 260, height: naturalHeight), visible: visible)
        panel.setFrame(frame.insetBy(dx: -inset, dy: -inset), display: true)
    }
    /// Transparent room around the menu in which its shadow is drawn.
    static let shadowInset: CGFloat = 24
    static func height(for entries: [MacMenuEntry]) -> CGFloat {
        CGFloat(entries.reduce(0) { $0 + ($1.separator ? 1 : 32) }) + CGFloat(max(0, entries.count - 1)) * 4 + 24
    }
    static func placement(origin: CGPoint, size: CGSize, visible: CGRect) -> CGRect {
        let width = min(size.width, visible.width - 16)
        let height = min(size.height, visible.height - 16)
        return CGRect(x: min(max(visible.minX + 8, origin.x), visible.maxX - width - 8),
                      y: min(max(visible.minY + 8, origin.y - height), visible.maxY - height - 8), width: width, height: height)
    }
    func select(_ entry: MacMenuEntry) {
        guard entry.enabled else { return }
        if entry.isNavigationBack { back(); return }
        if !entry.children.isEmpty {
            state.ancestors.append(state.entries)
            var back = MacMenuEntry("Back", symbol: "chevron.left") {}
            back.isNavigationBack = true
            state.entries = [back, .divider] + entry.children
            state.selectedID = nil
            layout()
        } else {
            dismiss()
            DispatchQueue.main.async { entry.action() }
        }
    }
    func back() {
        guard let entries = state.ancestors.popLast() else { dismiss(); return }
        state.entries = entries; state.selectedID = nil; layout()
    }
    func dismiss() {
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        if let deactivate { NotificationCenter.default.removeObserver(deactivate) }; deactivate = nil
        if let panel {
            sourceWindow?.removeChildWindow(panel)
            panel.close()
            sourceWindow?.makeKey()
        }
        panel = nil
        state.entries = []; state.ancestors = []; state.selectedID = nil
    }
}

/// A stable menu coordinate space inside moving content. Word frames are measured locally;
/// only the native anchor is converted to window coordinates when a menu is requested.
@MainActor final class MacContextMenuCoordinateSpace {
    let id = UUID()
    weak var anchor: NSView?
    fileprivate var targets: [ObjectIdentifier: MacScopedMenuTarget] = [:]
}

private struct MacContextMenuCoordinateSpaceKey: EnvironmentKey {
    static let defaultValue: MacContextMenuCoordinateSpace? = nil
}

extension EnvironmentValues {
    var macContextMenuCoordinateSpace: MacContextMenuCoordinateSpace? {
        get { self[MacContextMenuCoordinateSpaceKey.self] }
        set { self[MacContextMenuCoordinateSpaceKey.self] = newValue }
    }
}

struct MacContextMenuContainer<Content: View>: View {
    @State private var space = MacContextMenuCoordinateSpace()
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .coordinateSpace(name: space.id)
            .environment(\.macContextMenuCoordinateSpace, space)
            .background(MacContextMenuAnchor(space: space))
    }
}

private struct MacContextMenuAnchor: NSViewRepresentable {
    let space: MacContextMenuCoordinateSpace
    func makeNSView(context: Context) -> Anchor {
        let view = Anchor()
        view.space = space
        space.anchor = view
        return view
    }
    func updateNSView(_ view: Anchor, context: Context) { space.anchor = view }
    final class Anchor: NSView {
        weak var space: MacContextMenuCoordinateSpace?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let space { MacContextMenuRegistry.register(space) }
        }
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// Entries are nonvisual callbacks. Refresh their stable storage during DynamicProperty's
/// update phase, without publishing state or allocating one native view for every word.
@MainActor private final class MacScopedMenuTarget {
    var frame = CGRect.zero
    var entries: () -> [MacMenuEntry] = { [] }
}

@MainActor private struct MacScopedMenuRegistration: DynamicProperty {
    @State private var storage = MacScopedMenuTarget()
    let entries: () -> [MacMenuEntry]
    var target: MacScopedMenuTarget { storage }
    nonisolated mutating func update() {
        MainActor.assumeIsolated { storage.entries = entries }
    }
}

private struct MacScopedContextMenuModifier: ViewModifier {
    let space: MacContextMenuCoordinateSpace
    private var registration: MacScopedMenuRegistration

    init(space: MacContextMenuCoordinateSpace, entries: @escaping () -> [MacMenuEntry]) {
        self.space = space
        registration = MacScopedMenuRegistration(entries: entries)
    }

    func body(content: Content) -> some View {
        let target = registration.target
        content
            .onGeometryChange(for: CGRect.self) { geometry in
                let frame = geometry.frame(in: .named(space.id))
                guard let viewport = geometry.bounds(of: .scrollView(axis: .vertical)) else { return frame }
                let clipped = CGRect(origin: .zero, size: geometry.size).intersection(viewport)
                guard !clipped.isNull else { return .zero }
                return CGRect(origin: CGPoint(x: frame.minX + clipped.minX, y: frame.minY + clipped.minY),
                              size: clipped.size)
            } action: { target.frame = $0 }
            .onAppear { space.targets[ObjectIdentifier(target)] = target }
            .onDisappear { space.targets.removeValue(forKey: ObjectIdentifier(target)) }
    }
}

struct MacContextMenuModifier: ViewModifier {
    let entries: () -> [MacMenuEntry]
    @State private var visibleFrame = CGRect.zero
    @Environment(\.macContextMenuCoordinateSpace) private var coordinateSpace
    @ViewBuilder func body(content: Content) -> some View {
        if let coordinateSpace {
            content.modifier(MacScopedContextMenuModifier(space: coordinateSpace, entries: entries))
        } else {
            content
                .onGeometryChange(for: CGRect.self) { geometry in
                    let frame = geometry.frame(in: .global)
                    guard let viewport = geometry.bounds(of: .scrollView(axis: .vertical)) else { return frame }
                    let clipped = CGRect(origin: .zero, size: geometry.size).intersection(viewport)
                    guard !clipped.isNull, geometry.size.width > 0, geometry.size.height > 0 else { return .zero }
                    let scaleX = frame.width / geometry.size.width
                    let scaleY = frame.height / geometry.size.height
                    return CGRect(x: frame.minX + clipped.minX * scaleX, y: frame.minY + clipped.minY * scaleY,
                                  width: clipped.width * scaleX, height: clipped.height * scaleY)
                } action: { visibleFrame = $0 }
                .background(MacContextMenuRegion(entries: entries, visibleFrame: visibleFrame))
        }
    }
}
extension View {
    func macContextMenu(_ entries: @escaping () -> [MacMenuEntry]) -> some View { modifier(MacContextMenuModifier(entries: entries)) }
}
fileprivate struct MacContextMenuRegion: NSViewRepresentable {
    let entries: () -> [MacMenuEntry]
    let visibleFrame: CGRect
    func makeNSView(context: Context) -> Region {
        let view = Region(); view.entries = entries; view.menuFrame = visibleFrame; return view
    }
    func updateNSView(_ view: Region, context: Context) { view.entries = entries; view.menuFrame = visibleFrame }
    final class Region: NSView {
        var entries: () -> [MacMenuEntry] = { [] }
        var menuFrame = CGRect.zero
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); MacContextMenuRegistry.register(self) }
    }
}

/// One event monitor for all words/cards, rather than one monitor per response word.
@MainActor enum MacContextMenuRegistry {
    private final class WeakRegion {
        weak var view: MacContextMenuRegion.Region?
        init(_ view: MacContextMenuRegion.Region) { self.view = view }
    }
    private static var regions: [ObjectIdentifier: WeakRegion] = [:]
    private final class WeakSpace {
        weak var space: MacContextMenuCoordinateSpace?
        init(_ space: MacContextMenuCoordinateSpace) { self.space = space }
    }
    private static var spaces: [ObjectIdentifier: WeakSpace] = [:]
    private static var monitor: Any?
    fileprivate static func register(_ space: MacContextMenuCoordinateSpace) {
        spaces[ObjectIdentifier(space)] = WeakSpace(space)
        startMonitoring()
    }
    fileprivate static func register(_ view: MacContextMenuRegion.Region) {
        regions[ObjectIdentifier(view)] = WeakRegion(view)
        startMonitoring()
    }
    private static func startMonitoring() {
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
                handle(event) ? nil : event
            }
        }
    }
    static func entries(at windowPoint: CGPoint, in window: NSWindow) -> [MacMenuEntry] {
        regions = regions.filter { $0.value.view != nil }
        guard let content = window.contentView else { return [] }
        // A cached canvas surface becomes live during hit testing, before resolving its word
        // menu. This preserves the initiating right-click instead of requiring a second click.
        _ = content.hitTest(content.convert(windowPoint, from: nil))
        var point = content.convert(windowPoint, from: nil)
        if !content.isFlipped { point.y = content.bounds.maxY - point.y }
        var matches: [(CGFloat, () -> [MacMenuEntry])] = []
        spaces = spaces.filter { $0.value.space != nil }
        for space in spaces.values.compactMap(\.space) {
            guard let anchor = space.anchor, anchor.window === window, !anchor.isHiddenOrHasHiddenAncestor else { continue }
            // One window-to-card conversion per conversation, at click time only.
            let local = anchor.convert(windowPoint, from: nil)
            guard anchor.visibleRect.contains(local) else { continue }
            for target in space.targets.values where target.frame.width > 0 && target.frame.height > 0 && target.frame.contains(local) {
                let frame = anchor.convert(target.frame, to: nil)
                matches.append((frame.width * frame.height, target.entries))
            }
        }
        for view in regions.values.compactMap(\.view) where view.window === window && !view.isHiddenOrHasHiddenAncestor
            && view.menuFrame.width > 0 && view.menuFrame.height > 0 && view.menuFrame.contains(point) {
            matches.append((view.menuFrame.width * view.menuFrame.height, view.entries))
        }
        for (_, entries) in matches.sorted(by: { $0.0 < $1.0 }) {
            let result = entries()
            if !result.isEmpty { return result }
        }
        return []
    }
    static func handle(_ event: NSEvent) -> Bool {
        guard let window = event.window else { return false }
        let entries = entries(at: event.locationInWindow, in: window)
        guard !entries.isEmpty else { return false }
        MacMenuPresenter.shared.show(entries, at: window.convertToScreen(CGRect(origin: event.locationInWindow, size: .zero)).origin, in: window)
        return true
    }

}

/// Native text fields and the Library reader share the app's menu surface.
@MainActor enum MacNativeContextMenus {
    private static var monitor: Any?
    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { event in
            guard event.type == .rightMouseDown || event.modifierFlags.contains(.control) else { return event }
            if MacContextMenuRegistry.handle(event) { return nil }
            guard let window = event.window, !(window is MacMenuPanel), let content = window.contentView else { return event }
            var hit = content.hitTest(content.convert(event.locationInWindow, from: nil))
            while let view = hit, !(view is NSTextView), !(view is NSTextField) { hit = view.superview }
            var text = hit as? NSTextView
            if let field = hit as? NSTextField, field.isEnabled, field.isEditable || field.isSelectable {
                window.makeFirstResponder(field)
                text = field.currentEditor() as? NSTextView
            }
            if text == nil, let editor = window.firstResponder as? NSTextView,
               editor.visibleRect.contains(editor.convert(event.locationInWindow, from: nil)) { text = editor }
            guard let text else { return event }
            window.makeFirstResponder(text)
            let index = text.characterIndexForInsertion(at: text.convert(event.locationInWindow, from: nil))
            if !NSLocationInRange(index, text.selectedRange()) {
                text.setSelectedRange(NSRange(location: index, length: 0))
                text.selectWord(nil)
            }
            let native = text.menu(for: event).map(MacMenuEntry.native) ?? []
            let custom = native.filter { !$0.title.isEmpty && !$0.separator }
            let entries = editingEntries(for: text, additional: custom)
            MacMenuPresenter.shared.show(entries, at: window.convertToScreen(CGRect(origin: event.locationInWindow, size: .zero)).origin, in: window)
            return nil
        }
    }
    static func editingEntries(for text: NSTextView, additional: [MacMenuEntry] = [], canPaste: Bool? = nil) -> [MacMenuEntry] {
        let selected = text.selectedRange().length > 0
        var entries: [MacMenuEntry] = []
        if text.isEditable {
            entries += [MacMenuEntry("Undo", symbol: "arrow.uturn.backward", enabled: text.undoManager?.canUndo == true) { text.undoManager?.undo() },
                        MacMenuEntry("Redo", symbol: "arrow.uturn.forward", enabled: text.undoManager?.canRedo == true) { text.undoManager?.redo() }, .divider]
            entries.append(MacMenuEntry("Cut", symbol: "scissors", enabled: selected) { text.cut(nil) })
        }
        entries.append(MacMenuEntry("Copy", symbol: "doc.on.doc", enabled: selected) { text.copy(nil) })
        if text.isEditable { entries.append(MacMenuEntry("Paste", symbol: "doc.on.clipboard", enabled: canPaste ?? (NSPasteboard.general.availableType(from: text.readablePasteboardTypes) != nil)) { text.paste(nil) }) }
        entries += [.divider, MacMenuEntry("Select All", symbol: "selection.pin.in.out", enabled: !text.string.isEmpty) { text.selectAll(nil) }]
        let existing = Set(entries.map(\.title))
        let extra = additional.filter { !existing.contains($0.title) }
        return extra.isEmpty ? entries : extra + [.divider] + entries
    }
}

struct MacMenuPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(Value, String)]
    var body: some View {
        MacActionMenu(entries: {
            options.map { value, label in
                MacMenuEntry(LocalizedStringResource(stringLiteral: label), symbol: value == selection ? "checkmark" : "") { selection = value }
            }
        }) {
            HStack(spacing: 8) {
                BlurSwapText(Text(options.first(where: { $0.0 == selection })?.1 ?? ""), value: selection)
                Image(systemName: "chevron.up.chevron.down").angroveIcon(.xSmall)
            }
            .font(AngroveTheme.Typography.body)
            .foregroundStyle(AngroveTheme.Colors.lightGreen)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(AngroveTheme.Colors.componentBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.springStandard, value: selection)
        .pulsesOnChange(of: selection, anchor: .trailing)
        .accessibilityLabel(title)
        .accessibilityValue(options.first(where: { $0.0 == selection })?.1 ?? "")
    }
}

extension Notification.Name {
    static let macActionMenuWillOpen = Notification.Name("Angrove.macActionMenuWillOpen")
}
