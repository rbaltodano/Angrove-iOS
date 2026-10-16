import AppKit
import SwiftUI

/// Canvas keys, ignored while text is being edited anywhere in the window (except "/" with a
/// selection): typed characters start text, Escape deselects, ⌘= / ⌘− / ⌘0 zoom, and holding
/// Space grabs the canvas to pan.
struct WorktreeKeyShortcuts: NSViewRepresentable {
    enum Zoom { case `in`, out, reset }
    enum EditKey { case submit, delete, cancel }
    let onCharacters: (String) -> Bool
    let onEditKey: (EditKey) -> Bool
    let onEscape: () -> Bool
    let onZoom: (Zoom) -> Void
    /// "/" opens the selected item's command field; returns whether something was selected.
    let onSlash: (_ fromTextField: Bool) -> Bool
    /// A Tools card shortcut (⌘H, ⌘R, ⌘S, ⌘D, ⇧⌘K). Taken even while typing: it is a command,
    /// not text, and on this page it wins over the menus' use of the same keys (⌘H is Hide).
    let onTool: (WorktreeTool) -> Void
    /// ⌘+ or ⌘− with something selected, edited or hovered resizes it; returns whether it did.
    let onResize: (_ growing: Bool) -> Bool
    /// Space held outside a text field: the canvas becomes a grab tool until it is released.
    /// Returns whether the press was taken (a field that has not taken focus yet gets the space).
    let onSpace: (_ isDown: Bool) -> Bool

    let onUndo: () -> Void
    let onRedo: () -> Void

    func makeNSView(context: Context) -> Monitor { Monitor() }
    func updateNSView(_ view: Monitor, context: Context) {
        view.onCharacters = onCharacters
        view.onEditKey = onEditKey
        view.onEscape = onEscape
        view.onZoom = onZoom
        view.onSlash = onSlash
        view.onTool = onTool
        view.onResize = onResize
        view.onSpace = onSpace
        view.onUndo = onUndo
        view.onRedo = onRedo
    }
    static func dismantleNSView(_ view: Monitor, coordinator: ()) { view.stop() }

    final class Monitor: NSView {
        var onCharacters: ((String) -> Bool)?
        var onEditKey: ((EditKey) -> Bool)?
        var onEscape: (() -> Bool)?
        var onZoom: ((Zoom) -> Void)?
        var onSlash: ((Bool) -> Bool)?
        var onTool: ((WorktreeTool) -> Void)?
        var onResize: ((Bool) -> Bool)?
        var onSpace: ((Bool) -> Bool)?
        private var isSpacePanning = false
        private var resignObserver: NSObjectProtocol?
        var onUndo: (() -> Void)?
        var onRedo: (() -> Void)?
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window else { return }
            // Leaving the window lets go of the grab tool, since its key-up would never arrive.
            resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                    object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.endSpacePan() }
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                guard let self, event.window === self.window, !self.isHiddenOrHasHiddenAncestor else { return event }
                if event.type == .keyUp {
                    guard event.keyCode == 49, self.isSpacePanning else { return event }
                    self.endSpacePan()
                    return nil
                }
                let modifiers = event.modifierFlags.intersection([.command, .control, .option])
                let key = event.charactersIgnoringModifiers?.lowercased()
                let isTyping = self.window?.firstResponder is NSText
                // Space, as in Figma: hold to grab and pan; repeats are swallowed while held.
                if event.keyCode == 49, modifiers.isEmpty, !isTyping {
                    if self.isSpacePanning { return nil }
                    if !event.isARepeat, self.onSpace?(true) == true {
                        self.isSpacePanning = true
                        return nil
                    }
                }
                if modifiers == .command, let key,
                   let tool = WorktreeTool.forShortcut(key: key, shift: event.modifierFlags.contains(.shift)) {
                    if !event.isARepeat { self.onTool?(tool) }
                    return nil
                }
                if key == "/", modifiers.isEmpty, !event.isARepeat {
                    return self.onSlash?(isTyping) == true ? nil : event
                }
                // ⌘+ and ⌘− resize what is selected, else edited, else hovered, even while typing;
                // with nothing to resize they zoom the canvas below.
                let growing: Bool? = switch key {
                case "+", "=": true
                case "-", "_": false
                default: nil
                }
                if modifiers == .command, let growing, self.onResize?(growing) == true { return nil }
                if modifiers == .command, key == "z" {
                    let redo = event.modifierFlags.contains(.shift)
                    if isTyping, let manager = self.window?.firstResponder?.undoManager,
                       redo ? manager.canRedo : manager.canUndo { return event }
                    if redo { self.onRedo?() } else { self.onUndo?() }
                    return nil
                }
                guard !isTyping else { return event }
                let zoom: Zoom? = switch key {
                case "=", "+": .in
                case "-": .out
                case "0": .reset
                default: nil
                }
                if modifiers == .command, let zoom {
                    self.onZoom?(zoom)
                    return nil
                }
                guard modifiers.isEmpty else { return event }
                let editKey: EditKey? = switch event.keyCode {
                case 36, 76: .submit
                case 51: .delete
                case 53: .cancel
                default: nil
                }
                if let editKey, self.onEditKey?(editKey) == true { return nil }
                if event.keyCode == 53 { return self.onEscape?() == true ? nil : event }
                // Printable text only: no control, arrow or function keys.
                guard let characters = event.characters, !characters.isEmpty,
                      characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value) })
                else { return event }
                return self.onCharacters?(characters) == true ? nil : event
            }
        }
        private func endSpacePan() {
            guard isSpacePanning else { return }
            isSpacePanning = false
            _ = onSpace?(false)
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
            resignObserver = nil
            endSpacePan()
        }
    }
}
