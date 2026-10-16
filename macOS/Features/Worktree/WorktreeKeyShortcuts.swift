import AppKit
import SwiftUI

/// Canvas keys, ignored while text is being edited anywhere in the window (except "/" with a
/// selection): typed characters start text, Escape deselects, ⌘= / ⌘− / ⌘0 zoom.
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
    /// + or − with something selected or hovered resizes it; returns whether it did.
    let onResize: (_ growing: Bool) -> Bool

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
        var onUndo: (() -> Void)?
        var onRedo: (() -> Void)?
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.window, !self.isHiddenOrHasHiddenAncestor else { return event }
                let modifiers = event.modifierFlags.intersection([.command, .control, .option])
                let key = event.charactersIgnoringModifiers?.lowercased()
                let isTyping = self.window?.firstResponder is NSText
                if modifiers == .command, let key,
                   let tool = WorktreeTool.forShortcut(key: key, shift: event.modifierFlags.contains(.shift)) {
                    if !event.isARepeat { self.onTool?(tool) }
                    return nil
                }
                if key == "/", modifiers.isEmpty, !event.isARepeat {
                    return self.onSlash?(isTyping) == true ? nil : event
                }
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
                // + and − (either row or the keypad) resize what is selected or hovered; with
                // nothing to resize they type, as any key does.
                let growing: Bool? = switch key {
                case "+", "=": true
                case "-", "_": false
                default: nil
                }
                if let growing, self.onResize?(growing) == true { return nil }
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
        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
