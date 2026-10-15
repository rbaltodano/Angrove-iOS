import SwiftUI

/// A free-form canvas for exploring ideas with commands. It pans like the Insight Tree (drag,
/// trackpad or wheel; Command-scroll zooms) without the dot background. Typing anywhere places
/// bare text beside the pointer; clicking only selects. Quoted text committed with Return
/// is answered in place.
struct MacWorktreeView: View {
    static let canvasSpace = "WorktreeCanvas"
    let board: WorktreeBoard
    let queuePopup: ModelTasksPopupState
    @State private var camera = CanvasScrollTransform(scale: 1, offset: .zero)
    @GestureState private var drag: CGSize = .zero
    @State private var pinchStart: CanvasScrollTransform?
    @State private var viewport: CGSize = .zero
    /// The pointer over the canvas; typing starts 16pt to its right.
    @State private var pointer: CGPoint?
    private static let zoomLimits: ClosedRange<CGFloat> = 0.28...2.6
    @State private var showsCommands = false
    private let runtime = MacApplicationRuntime.shared

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                AngroveTheme.Colors.canvas
                    .contentShape(Rectangle())
                    .gesture(panGesture)
                    .onTapGesture(coordinateSpace: .local) { location in tapCanvas(at: location, in: size) }
                ForEach(board.items) { item in
                    let point = screenPoint(item.origin, in: size)
                    WorktreeItemView(board: board, item: item, scale: camera.scale, runtime: runtime)
                        .fixedSize()
                        .scaleEffect(camera.scale, anchor: .topLeading)
                        .offset(x: point.x, y: point.y)
                        .zIndex(board.activeID == item.id ? 1 : 0)
                }
                if let origin = board.commandOrigin {
                    let point = screenPoint(origin, in: size)
                    WorktreeCommandField(board: board, runtime: runtime)
                        .scaleEffect(camera.scale, anchor: .topLeading)
                        .offset(x: point.x, y: point.y)
                        .zIndex(2)
                        .transition(.blurFade)
                }
                MacCanvasScrollInput { delta, flags, anchor in
                    camera.apply(delta: delta, command: flags.contains(.command), shift: flags.contains(.shift),
                                 anchor: anchor, viewport: size)
                }
            }
            .coordinateSpace(name: Self.canvasSpace)
            .onContinuousHover(coordinateSpace: .local) { phase in
                if case .active(let location) = phase { pointer = location } else { pointer = nil }
            }
            .simultaneousGesture(pinchGesture(in: size))
            .dropDestination(for: String.self) { payloads, location in
                let ids = payloads.compactMap(WorktreeConversationDrop.conversationID(in:))
                guard !ids.isEmpty else { return false }
                for (offset, id) in ids.enumerated() {
                    // The chip lands where it was let go, its text level with the pointer.
                    let point = CGPoint(x: location.x - 16 + CGFloat(offset) * 24, y: location.y - 22 + CGFloat(offset) * 24)
                    board.addConversation(id, at: worldPoint(point, in: size))
                }
                return true
            }
            .onAppear { viewport = size }
            .onChange(of: size) { _, value in viewport = value }
            .clipped()
        }
        .overlay(alignment: .top) {
            // The compact title a conversation pins once it scrolls past its heading.
            ZStack(alignment: .top) {
                MacConversationEdgeFade(top: true)
                    .ignoresSafeArea(.container, edges: .top)
                ZStack {
                    if let work = board.retitleWork {
                        Text("Labeling...")
                            .font(MacConversationStyle.pinnedTitle)
                            .modifier(WorktreeWorkStyle(work: work))
                            .transition(.blurFade)
                    } else {
                        ConversationHeading(title: board.title) { title in
                            MacPageHeading(title: title, font: MacConversationStyle.pinnedTitle)
                        }
                        .id(board.title)
                        .transition(.blurFade)
                    }
                }
                .padding(.top, 48)
            }
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 16) {
                if queuePopup.isOpen {
                    ModelTasksCard(modelTasks: runtime.modelTasks, popupState: queuePopup)
                        .transition(.bottomDockCard)
                } else if showsCommands {
                    WorktreeCommandsCard()
                        .transition(.scale(scale: 0.96, anchor: .bottom).combined(with: .opacity))
                }
                WorktreeControlDock(board: board, modelTasks: runtime.modelTasks, showsCommands: showsCommands,
                    toggleModelTasks: {
                        withAnimation(.springStandard) {
                            queuePopup.isOpen.toggle()
                            if queuePopup.isOpen { showsCommands = false }
                        }
                    }) {
                    withAnimation(.springStandard) {
                        showsCommands.toggle()
                        if showsCommands { queuePopup.isOpen = false }
                    }
                }
            }
            .padding(24)
        }
        .background(WorktreeKeyShortcuts(onCharacters: typeOnCanvas, onEscape: escape, onZoom: zoom, onSlash: openCommand))
        .onDisappear { board.endEditing() }
        .alert("Replace Conversation?", isPresented: Binding(get: { board.pendingReplacement != nil },
                                                             set: { if !$0 { board.pendingReplacement = nil } }),
               presenting: board.pendingReplacement) { replacement in
            Button("Replace") { board.replaceOriginal(with: replacement.id) }
            Button("Keep Both") { board.saveCopy(of: replacement.id, runtime: runtime) }
            Button("Cancel", role: .cancel) {}
        } message: { replacement in
            Text("Replace “\(replacement.title)” in the sidebar with this window’s version, or keep both?")
        }
        .alert("Angrove", isPresented: Binding(get: { board.errorMessage != nil }, set: { if !$0 { board.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(board.errorMessage ?? "") }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                camera.offset.width += value.translation.width
                camera.offset.height += value.translation.height
            }
    }

    /// screen = viewport centre + camera offset + world × scale, matching `CanvasScrollTransform`.
    private func screenPoint(_ world: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2 + camera.offset.width + drag.width + world.x * camera.scale,
                y: size.height / 2 + camera.offset.height + drag.height + world.y * camera.scale)
    }

    private func worldPoint(_ screen: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: (screen.x - size.width / 2 - camera.offset.width) / camera.scale,
                y: (screen.y - size.height / 2 - camera.offset.height) / camera.scale)
    }

    private func tapCanvas(at location: CGPoint, in size: CGSize) {
        dismissCommands()
        if queuePopup.isOpen { withAnimation(.springStandard) { queuePopup.isOpen = false } }
        board.select(nil)
        board.endEditing()
    }

    /// 16pt right of the pointer with the first line centred on it, or below the title when the
    /// pointer is off the canvas.
    private var typingOrigin: CGPoint {
        let anchor = pointer ?? CGPoint(x: viewport.width / 2 - 120, y: 132)
        return worldPoint(CGPoint(x: anchor.x + 16, y: anchor.y - WorktreeTextEditor.lineHeight / 2 * camera.scale), in: viewport)
    }

    /// Typing on the canvas starts a text field beside the pointer, holding what was typed.
    /// Keys that arrive before the new field takes focus are added to it.
    private func typeOnCanvas(_ characters: String) -> Bool {
        // A command field just opened by "/" takes focus a moment later; keys typed meanwhile
        // belong to it, not to new canvas text (which would deselect and close it).
        if board.isCommandOpen, board.editingID == board.commandFieldID, !board.isCommandStruck {
            board.commandText += characters
            return true
        }
        if let id = board.editingID, board.items.contains(where: { $0.id == id && !$0.isQuestion && !$0.isInsight }) {
            board.update(id) { $0.text += characters }
            return true
        }
        guard characters.contains(where: { !$0.isWhitespace }) else { return false }
        board.select(nil)
        board.addText(at: typingOrigin, text: characters)
        return true
    }

    private func pinchGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                let start = pinchStart ?? camera
                pinchStart = start
                camera = Self.zoomed(start, to: start.scale * value.magnification, anchor: value.startLocation, in: size)
            }
            .onEnded { _ in pinchStart = nil }
    }

    /// ⌘= and ⌘− step around the viewport centre; ⌘0 returns to 100%.
    private func zoom(_ step: WorktreeKeyShortcuts.Zoom) {
        let center = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        let target: CGFloat = switch step {
        case .in: camera.scale * 1.25
        case .out: camera.scale / 1.25
        case .reset: 1
        }
        withAnimation(.springQuick) { camera = Self.zoomed(camera, to: target, anchor: center, in: viewport) }
    }

    /// Scales about `anchor`, keeping the world point under it fixed (as `CanvasScrollTransform` does).
    private static func zoomed(_ start: CanvasScrollTransform, to scale: CGFloat, anchor: CGPoint, in size: CGSize) -> CanvasScrollTransform {
        let next = min(max(scale, zoomLimits.lowerBound), zoomLimits.upperBound)
        let ratio = next / start.scale
        let centered = CGPoint(x: anchor.x - size.width / 2, y: anchor.y - size.height / 2)
        return CanvasScrollTransform(scale: next, offset: CGSize(width: centered.x - (centered.x - start.offset.width) * ratio,
                                                               height: centered.y - (centered.y - start.offset.height) * ratio))
    }

    /// Escape closes a card first, then deselects. Returns whether it was used.
    private func escape() -> Bool {
        if queuePopup.isOpen { withAnimation(.springStandard) { queuePopup.isOpen = false }; return true }
        if showsCommands { dismissCommands(); return true }
        if board.activeID != nil { board.select(nil); return true }
        return false
    }

    /// "/" with an item selected opens beside it, even from another text field. With nothing
    /// selected it starts beside the pointer, acting on the whole Worktree, when not typing.
    private func openCommand(fromTextField: Bool) -> Bool {
        if board.activeID != nil { return board.editingID == board.commandFieldID ? false : board.openCommand() }
        guard !fromTextField else { return false }
        return board.openCommand(freeOrigin: typingOrigin)
    }

    private func dismissCommands() {
        guard showsCommands else { return }
        withAnimation(.springStandard) { showsCommands = false }
    }
}

/// Canvas keys, ignored while text is being edited anywhere in the window (except "/" with a
/// selection): typed characters start text, Escape deselects, ⌘= / ⌘− / ⌘0 zoom.
private struct WorktreeKeyShortcuts: NSViewRepresentable {
    enum Zoom { case `in`, out, reset }
    let onCharacters: (String) -> Bool
    let onEscape: () -> Bool
    let onZoom: (Zoom) -> Void
    /// "/" opens the selected item's command field; returns whether something was selected.
    let onSlash: (_ fromTextField: Bool) -> Bool

    func makeNSView(context: Context) -> Monitor { Monitor() }
    func updateNSView(_ view: Monitor, context: Context) {
        view.onCharacters = onCharacters
        view.onEscape = onEscape
        view.onZoom = onZoom
        view.onSlash = onSlash
    }
    static func dismantleNSView(_ view: Monitor, coordinator: ()) { view.stop() }

    final class Monitor: NSView {
        var onCharacters: ((String) -> Bool)?
        var onEscape: (() -> Bool)?
        var onZoom: ((Zoom) -> Void)?
        var onSlash: ((Bool) -> Bool)?
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
                if key == "/", modifiers.isEmpty, !event.isARepeat {
                    return self.onSlash?(isTyping) == true ? nil : event
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

/// The Worktree's model controls: add, Model Tasks, Commands and Trash.
private struct WorktreeControlDock: View {
    let board: WorktreeBoard
    let modelTasks: ModelTaskQueue
    let showsCommands: Bool
    let toggleModelTasks: () -> Void
    let toggleCommands: () -> Void
    @State private var isPressed = false
    private var isTrashTargeted: Bool { board.trashTargetID != nil }

    var body: some View {
        HStack(spacing: 24) {
            Button {} label: {
                icon("WorktreePlus", width: 10, height: 10)
                    .foregroundStyle(AngroveTheme.Colors.lightGreen)
            }
            .accessibilityLabel("Add")
            .modelControlHoverLabel("Add")

            ModelStatusButton(modelTasks: modelTasks, action: toggleModelTasks, controlIsPressed: $isPressed)

            Button(action: toggleCommands) {
                label("Commands", icon: icon("WorktreeCommand", width: 12, height: 12))
                    .foregroundStyle(showsCommands ? AngroveTheme.Colors.lightGreen : AngroveTheme.Colors.paragraphText)
            }
            .accessibilityAddTraits(showsCommands ? .isSelected : [])
            .modelControlHoverLabel(showsCommands ? "Hide Commands" : "Show Commands")

            Button {} label: {
                label("Trash", icon: icon("WorktreeTrash", width: 10, height: 12))
                    .foregroundStyle(isTrashTargeted ? AngroveTheme.Colors.accentRed : AngroveTheme.Colors.paragraphText)
                    .scaleEffect(isTrashTargeted ? 1.12 : 1)
                    .animation(.springLively, value: isTrashTargeted)
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { board.trashFrame = $0 }
            .accessibilityHint("Drag text here to delete it")
            .modelControlHoverLabel("Trash")
        }
        .buttonStyle(FloatingControlButtonStyle(isPressed: $isPressed))
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .background(AngroveTheme.Colors.canvasSecondary)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(AngroveTheme.Colors.popupBorder, lineWidth: 1))
        .modelControlHoverPill()
        .modifier(FloatingControlPressFeedback(isButtonPressed: isPressed))
        .modelControlHoverOverlay(isVisible: true)
    }

    private func icon(_ name: String, width: CGFloat, height: CGFloat) -> some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }

    private func label(_ title: LocalizedStringKey, icon: some View) -> some View {
        HStack(spacing: 8) {
            icon
            Text(title).font(BrandTypography.font("Figtree-SemiBold", size: 14))
        }
        .frame(minHeight: 21)
        .contentShape(Rectangle())
    }
}

/// Getting-started help opened from Commands.
private struct WorktreeCommandsCard: View {
    private static let paragraph = BrandTypography.font("Figtree-Regular", size: 14)
    private static let emphasis = BrandTypography.font("Figtree-Bold", size: 14)
    /// Figtree 14 at the design's 2× line height.
    private static let lineSpacing: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Getting Started with \(Text("Worktrees").font(BrandTypography.font("LibreBaskerville-Italic", size: 18)).foregroundStyle(AngroveTheme.Colors.lightGreen))")
                    .font(BrandTypography.font("LibreBaskerville-Regular", size: 18))
                    .foregroundStyle(AngroveTheme.Colors.headingText)
                Text("Scratchpad is a space to explore ideas in a more open space. The main way to interact is with commands, to use commands on a specific element, click it to \(highlight("Select"))")
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
            }

            VStack(alignment: .leading, spacing: 4) {
                heading("Ask a question:")
                Text("To ask a question, start typing anywhere, open your question with quotation marks, and press \(highlight("Enter")) to submit.")
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
            }

            VStack(alignment: .leading, spacing: 16) {
                heading("Useful commands:")
                command("/rename", "Will generate a label for whatever you have selected. If you want to label manually, type it right after this command.")
                command("/summarize", "Will generate a brief summary of the selected object")
                command("/define", "Will generate an Insight card of whatever is being selected. If you want to define a specific term, type the term right after this command.")
            }

            Text("Commands can be strung together, the model will complete them in the order that they have been typed.")
                .foregroundStyle(AngroveTheme.Colors.paragraphText)
        }
        .font(Self.paragraph)
        .lineSpacing(Self.lineSpacing)
        .fixedSize(horizontal: false, vertical: true)
        .padding(28)
        .frame(width: 500, alignment: .leading)
        .background(AngroveTheme.Colors.canvasSecondary, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(AngroveTheme.Colors.popupBorder, lineWidth: 1))
    }

    private func highlight(_ text: LocalizedStringKey) -> Text {
        Text(text).font(Self.emphasis).foregroundStyle(AngroveTheme.Colors.lightGreen)
    }

    private func heading(_ text: LocalizedStringKey) -> some View {
        Text(text).font(Self.emphasis).foregroundStyle(AngroveTheme.Colors.headingText)
    }

    private func command(_ name: String, _ detail: LocalizedStringKey) -> some View {
        Text("\(Text(verbatim: name).font(Self.emphasis).foregroundStyle(AngroveTheme.Colors.lightGreen)) \(Text(detail))")
            .foregroundStyle(AngroveTheme.Colors.headingText)
            .padding(.leading, 16)
    }
}
