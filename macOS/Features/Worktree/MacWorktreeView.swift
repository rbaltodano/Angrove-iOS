import SwiftUI

/// A free-form canvas for exploring ideas with commands. It pans like the Insight Tree (drag,
/// trackpad or wheel; Command-scroll zooms) without the dot background. Typing anywhere places
/// bare text beside the pointer; clicking only selects. Quoted text committed with Return
/// is answered in place.
struct MacWorktreeView: View {
    static let canvasSpace = "WorktreeCanvas"
    let board: WorktreeBoard
    let queuePopup: ModelTasksPopupState
    /// Saves the board; called shortly after each change and when leaving.
    var onSave: () -> Void = {}
    @State private var camera = CanvasScrollTransform(scale: 1, offset: .zero)
    @GestureState private var drag: CGSize = .zero
    @State private var pinchStart: CanvasScrollTransform?
    @State private var viewport: CGSize = .zero
    /// The pointer over the canvas; typing starts 16pt to its right. Held outside SwiftUI state:
    /// it is only read on a keypress, so mouse movement never re-renders the canvas.
    @State private var pointerBox = WorktreePointer()
    /// The pointer in world space, observed only by note boxes that fade in near it.
    @State private var canvasPointer = WorktreeCanvasPointer()
    @State private var picker: WorktreePicker?
    @State private var showsTrash = false
    @State private var showsTools = false
    /// A tool picked up from the Tools card, following the pointer until a click places it.
    @State private var activeTool: WorktreeTool?
    /// Space is held: the canvas is a grab tool, panning on drag.
    @State private var isSpacePanning = false
    @State private var showsPhotoPicker = false
    @State private var pendingPhotos: [WorktreePhotoAsset] = []
    @State private var photoLoadID = UUID()
    @State private var showsFilePicker = false
    /// Where "+" menu choices land: the middle of the view when the menu opened.
    @State private var placementOrigin = CGPoint.zero
    private var pointer: CGPoint? { pointerBox.location }
    private static let zoomLimits: ClosedRange<CGFloat> = 0.28...2.6
    var runtime = MacApplicationRuntime.shared

    init(board: WorktreeBoard, queuePopup: ModelTasksPopupState,
         onSave: @escaping () -> Void = {}, runtime: MacApplicationRuntime = .shared) {
        self.board = board
        self.queuePopup = queuePopup
        self.onSave = onSave
        self.runtime = runtime
        _camera = State(initialValue: board.viewport.transform)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                AngroveTheme.Colors.canvas
                    .contentShape(Rectangle())
                    .gesture(panGesture)
                    .onTapGesture(coordinateSpace: .local) { location in tapCanvas(at: location, in: size) }
                // The Insight Tree's dots, resting invisible: they only pulse once when something
                // is selected or finishes.
                AnimatedDotGridBackground(settledOffset: camera.offset, settledScale: camera.scale,
                                          dragOffset: drag, ripples: board.ripples, showsIdleField: false)
                    .frame(width: size.width, height: size.height)
                if board.items.isEmpty && !board.isCommandOpen {
                    AngroveEmptyState(systemImage: MacIcon.worktree.symbol, title: "A blank canvas",
                        message: "Start typing anywhere to add a note. Open with a quotation mark and press Enter to ask a question. Open Tools for every command and shortcut.")
                        .frame(width: size.width, height: size.height)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                // One world layer moved by the camera: panning changes only this layer's transform,
                // so item views aren't recomputed per frame.
                ZStack(alignment: .topLeading) {
                    ForEach(board.items) { item in
                        WorktreeItemView(board: board, item: item, scale: camera.scale, runtime: runtime, pointer: canvasPointer)
                            .equatable()
                            .fixedSize()
                            .offset(x: item.origin.x, y: item.origin.y)
                            .zIndex(board.selection.contains(item.id) ? 1 : 0)
                            .transition(.blurFade)
                    }
                    if let origin = board.commandOrigin {
                        WorktreeCommandField(board: board, runtime: runtime)
                            .offset(x: origin.x, y: origin.y)
                            .zIndex(2)
                            .transition(.blurFade)
                    }
                }
                .frame(width: 0, height: 0, alignment: .topLeading)
                .scaleEffect(camera.scale, anchor: .topLeading)
                .offset(x: size.width / 2 + camera.offset.width + drag.width,
                        y: size.height / 2 + camera.offset.height + drag.height)
                ForEach(board.guides) { guide in
                    let from = screenPoint(guide.axis == .vertical ? CGPoint(x: guide.position, y: guide.start)
                                                                   : CGPoint(x: guide.start, y: guide.position), in: size)
                    let to = screenPoint(guide.axis == .vertical ? CGPoint(x: guide.position, y: guide.end)
                                                                 : CGPoint(x: guide.end, y: guide.position), in: size)
                    WorktreeGuideLine(axis: guide.axis)
                        .frame(width: guide.axis == .vertical ? 1 : to.x - from.x,
                               height: guide.axis == .vertical ? to.y - from.y : 1)
                        .position(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
                        .transition(.asymmetric(insertion: .modifier(active: WorktreeGuideDraw(axis: guide.axis, progress: 0),
                                                                     identity: WorktreeGuideDraw(axis: guide.axis, progress: 1)),
                                                removal: .opacity))
                        .zIndex(3)
                        .allowsHitTesting(false)
                }
                // With Tools, Trash or Model Tasks open, a click anywhere on the canvas (items
                // included) just closes it, as clicking outside a popover does.
                if hasOpenCard {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { closeCards() }
                        .zIndex(4)
                }
                MacCanvasScrollInput { delta, flags, anchor in
                    camera.apply(delta: delta, command: flags.contains(.command), shift: flags.contains(.shift),
                                 anchor: anchor, viewport: size)
                }
                if let photo = pendingPhotos.first {
                    WorktreePhotoPlacement(asset: photo, onPlace: { location in
                        board.placePhoto(photo.file, size: photo.placedSize, at: worldPoint(location, in: size))
                        pendingPhotos.removeFirst()
                    }, onPan: { delta in
                        camera.offset.width += delta.width
                        camera.offset.height += delta.height
                    })
                    .id(photo.id)
                    .frame(width: size.width, height: size.height)
                    .zIndex(10)
                } else if let tool = activeTool {
                    WorktreeToolPlacement(tool: tool, scale: camera.scale, onPlace: { click, origin in
                        place(tool, click: worldPoint(click, in: size), origin: worldPoint(origin, in: size))
                    }, onPan: { delta in
                        camera.offset.width += delta.width
                        camera.offset.height += delta.height
                    })
                    .id(tool)
                    .frame(width: size.width, height: size.height)
                    .zIndex(10)
                }
                if isSpacePanning {
                    WorktreePanSurface { delta in
                        camera.offset.width += delta.width
                        camera.offset.height += delta.height
                    }
                    .frame(width: size.width, height: size.height)
                    .zIndex(11)
                }
            }
            .coordinateSpace(name: Self.canvasSpace)
            .onContinuousHover(coordinateSpace: .local) { phase in
                if case .active(let location) = phase {
                    pointerBox.location = location
                    canvasPointer.update(world: worldPoint(location, in: size), board: board, zoom: camera.scale)
                } else {
                    pointerBox.location = nil
                    canvasPointer.update(world: nil, board: board, zoom: camera.scale)
                }
            }
            .simultaneousGesture(pinchGesture(in: size))
            .dropDestination(for: String.self) { payloads, location in
                let restored = payloads.compactMap { WorktreeTrashDrop.itemID(in: $0, boardID: board.documentID) }
                if !restored.isEmpty {
                    var didRestore = false
                    withAnimation(.springStandard) {
                        for (offset, id) in restored.enumerated() {
                            let point = CGPoint(x: location.x + CGFloat(offset) * 24, y: location.y + CGFloat(offset) * 24)
                            didRestore = board.restoreFromTrash(id, at: worldPoint(point, in: size)) || didRestore
                        }
                    }
                    return didRestore
                }
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
        .overlay {
            Color.clear.preference(key: MacGlobalModelControlsKey.self,
                                   value: MacGlobalModelControls(configuration: dockConfiguration))
        }
        .background(WorktreeKeyShortcuts(onCharacters: typeOnCanvas, onEditKey: editPendingField, onEscape: escape, onZoom: zoom, onSlash: openCommand, onTool: useShortcut, onResize: resizeTargets, onSpace: spacePan, onUndo: { board.undo() }, onRedo: { board.redo() }))
        .onChange(of: board.fileRequest) { _, _ in openFiles() }
        .onChange(of: camera.scale) { _, _ in rememberViewport() }
        .onChange(of: camera.offset) { _, _ in rememberViewport() }
        .onDisappear {
            photoLoadID = UUID()
            pendingPhotos = []
            activeTool = nil
            isSpacePanning = false
            rememberViewport(); board.endEditing(); onSave()
        }
        .modifier(MacAttachmentPickers(showsFiles: $showsFilePicker, showsPhotos: $showsPhotoPicker) { files in
            preparePhotos(files)
        })
        .sheet(item: $picker) { kind in
            WorktreePickerSheet(kind: kind) { concept in
                picker = nil
                board.addInsight(concept, at: placementOrigin)
            } onCancel: { picker = nil }
        }
        .background(WorktreeAutosave(board: board, onSave: onSave))
        .onReceive(NotificationCenter.default.publisher(for: .macWillFlushPersistence)) { _ in rememberViewport(); onSave() }
        .animation(.easeOut(duration: 0.3), value: board.items.isEmpty)
        .alert("Replace Conversation?", isPresented: Binding(get: { board.pendingReplacement != nil },
                                                             set: { if !$0 { board.pendingReplacement = nil } }),
               presenting: board.pendingReplacement) { replacement in
            Button("Replace") { board.replaceOriginal(with: replacement.id) }
            Button("Keep Both") { board.saveCopy(of: replacement.id, runtime: runtime, keepingBoth: true) }
            Button("Cancel", role: .cancel) {}
        } message: { replacement in
            Text("Replace “\(replacement.title)” in the sidebar with this window’s version, or keep both?")
        }
        .alert("Angrove", isPresented: Binding(get: { board.errorMessage != nil }, set: { if !$0 { board.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(board.errorMessage ?? "") }
    }

    private var dockConfiguration: ModelControlsConfiguration {
        var configuration = ModelControlsConfiguration(id: "mac-boards")
        configuration.modelTasks = runtime.modelTasks
        configuration.modelTasksPopupState = queuePopup
        configuration.buttons = AnyView(WorktreeControlDock(board: board, modelTasks: runtime.modelTasks,
            addEntries: addEntries,
            toggleTools: {
                withAnimation(.springStandard) { queuePopup.isOpen = false; showsTrash = false; showsTools.toggle() }
            }, toggleModelTasks: {
                withAnimation(.springStandard) { showsTrash = false; showsTools = false; queuePopup.isOpen.toggle() }
            }, toggleTrash: {
                withAnimation(.springStandard) { queuePopup.isOpen = false; showsTools = false; showsTrash.toggle() }
            }))
        configuration.pillHorizontalPadding = 0
        configuration.pillVerticalPadding = 0
        configuration.showsPillChrome = false
        if showsTrash {
            configuration.supplementalPopupIsOpen = true
            configuration.supplementalPopup = AnyView(WorktreeTrashCard(board: board))
        } else if showsTools {
            configuration.supplementalPopupIsOpen = true
            configuration.supplementalPopup = AnyView(WorktreeToolsCard(onChoose: pickUp))
        }
        return configuration
    }

    private func preparePhotos(_ files: [UploadedFile]) {
        let request = UUID()
        photoLoadID = request
        board.endEditing()
        board.closeCommand()
        queuePopup.isOpen = false
        activeTool = nil
        Task { @MainActor in
            let photos = await Task.detached(priority: .userInitiated) {
                files.compactMap { file -> WorktreePhotoAsset? in
                    guard let data = file.imageData, let image = NSImage(data: data), image.isValid else { return nil }
                    let upright = UploadedFile(id: file.id, name: file.name, imageData: data, rotationDegrees: 0)
                    return WorktreePhotoAsset(file: upright, image: image)
                }
            }.value
            guard photoLoadID == request else { return }
            pendingPhotos = photos
        }
    }

    private func rememberViewport() {
        board.viewport = WorktreeViewport(scale: camera.scale, offset: camera.offset)
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

    /// Whether Tools, Trash or Model Tasks is open above the controls.
    private var hasOpenCard: Bool { showsTools || showsTrash || queuePopup.isOpen }

    private func closeCards() {
        withAnimation(.springStandard) { showsTools = false; showsTrash = false; queuePopup.isOpen = false }
    }

    private func tapCanvas(at location: CGPoint, in size: CGSize) {
        if hasOpenCard { closeCards() }
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
        guard pendingPhotos.isEmpty, activeTool == nil else { return true }
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

    /// ⌘= and ⌘− (when nothing is there to resize) step around the viewport centre; ⌘0 returns to 100%.
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

    /// Return, Delete and Escape typed into a field that hasn't taken focus yet (just opened by
    /// "/" or by typing) act on it, so fast typing never loses the keystroke that submits.
    private func editPendingField(_ key: WorktreeKeyShortcuts.EditKey) -> Bool {
        if board.isCommandOpen, board.editingID == board.commandFieldID, !board.isCommandStruck {
            switch key {
            case .submit: board.submitCommand(runtime: runtime)
            case .delete:
                board.commandText.removeLast()
                if board.commandText.isEmpty { board.closeCommand() }
            case .cancel: board.closeCommand()
            }
            return true
        }
        guard let id = board.editingID, let item = board.items.first(where: { $0.id == id }),
              !item.isQuestion, !item.isInsight else { return false }
        switch key {
        case .submit: item.isHeading ? board.endEditing() : board.commit(id, runtime: runtime)
        case .delete: board.update(id) { if !$0.text.isEmpty { $0.text.removeLast() } }
        case .cancel: board.endEditing()
        }
        return true
    }

    /// Escape closes a card first, then deselects. Returns whether it was used.
    private func escape() -> Bool {
        if showsTrash { withAnimation(.springStandard) { showsTrash = false }; return true }
        if !pendingPhotos.isEmpty { pendingPhotos = []; photoLoadID = UUID(); return true }
        if activeTool != nil { activeTool = nil; return true }
        if showsTools { withAnimation(.springStandard) { showsTools = false }; return true }
        if queuePopup.isOpen { withAnimation(.springStandard) { queuePopup.isOpen = false }; return true }
        if !board.selection.isEmpty { board.select(nil); return true }
        return false
    }

    /// The "+" menu: each starts something in the middle of the view.
    /// The "+" menu matches a conversation's: Insights and Passages place cards, Photos and
    /// Image File place pictures, all in the middle of the view.
    private func addEntries() -> [MacMenuEntry] {
        placementOrigin = worldPoint(CGPoint(x: viewport.width / 2 - 160, y: viewport.height / 2 - 80), in: viewport)
        return [
            MacMenuEntry("Insights", symbol: "text.bubble") { picker = .insights },
            MacMenuEntry("Passages", symbol: "books.vertical") { picker = .passages },
            .divider,
            MacMenuEntry("Photos…", symbol: "photo.on.rectangle") { showsPhotoPicker = true },
            MacMenuEntry("Image File…", symbol: "doc", shortcut: "⇧⌘K") { openFiles() },
        ]
    }

    /// "/" with a selection opens beside it, even from another text field. Otherwise, when not
    /// typing, it opens beside the hovered item, or by the pointer for the whole Worktree.
    private func openCommand(fromTextField: Bool) -> Bool {
        guard pendingPhotos.isEmpty, activeTool == nil else { return true }
        if board.editingID == board.commandFieldID { return false }
        if !board.commandSelection.isEmpty { return board.openCommand() }
        guard !fromTextField else { return false }
        return board.openCommand(freeOrigin: typingOrigin)
    }

    /// A row of the Tools card: Add File opens the file browser; the rest follow the pointer.
    private func pickUp(_ tool: WorktreeTool) {
        withAnimation(.springStandard) { showsTools = false }
        guard tool != .file else { openFiles(); return }
        board.endEditing()
        board.closeCommand()
        activeTool = tool
    }

    /// The file browser, pictures only for now; chosen pictures follow the pointer to be placed.
    private func openFiles() {
        activeTool = nil
        showsFilePicker = true
    }

    /// A tool's shortcut runs on what is selected, else edited, else hovered, as if its command had
    /// been typed there; with nothing to act on, the typed command waits by the pointer.
    private func useShortcut(_ tool: WorktreeTool) {
        guard pendingPhotos.isEmpty else { return }
        activeTool = nil
        if tool == .file { openFiles(); return }
        board.runTool(tool, on: board.shortcutTargets, freeOrigin: typingOrigin, runtime: runtime)
    }

    /// Space down grabs the canvas; a just-opened field that has not taken focus yet gets the
    /// space as text instead.
    private func spacePan(isDown: Bool) -> Bool {
        guard isDown else { isSpacePanning = false; return true }
        guard board.editingID == nil else { return false }
        isSpacePanning = true
        return true
    }

    private func resizeTargets(growing: Bool) -> Bool {
        guard pendingPhotos.isEmpty, activeTool == nil else { return false }
        return board.resize(board.shortcutTargets, growing: growing)
    }

    /// A click with a picked-up tool. Text, Question and Heading land where the preview sat, ready
    /// to type. Rename, Summarize and Define act on what was clicked; Define on empty canvas
    /// waits for a term there, and the others stay picked up until something is clicked.
    private func place(_ tool: WorktreeTool, click: CGPoint, origin: CGPoint) {
        switch tool {
        case .text:
            board.select(nil)
            board.addText(at: origin)
        case .question:
            board.select(nil)
            board.addText(at: origin, text: "“")
        case .heading:
            board.select(nil)
            board.addHeadingField(at: origin)
        case .rename, .summarize, .define:
            if let id = board.item(at: click) {
                board.select(id)
                board.runTool(tool, on: [id], freeOrigin: origin, runtime: runtime)
            } else if tool == .define {
                board.select(nil)
                board.runTool(tool, on: [], freeOrigin: origin, runtime: runtime)
            } else {
                return
            }
        case .file:
            openFiles()
            return
        }
        activeTool = nil
    }

}

/// An accent-green alignment guide, faded over its first and last quarter.
private struct WorktreeGuideLine: View {
    let axis: WorktreeGuide.Axis

    var body: some View {
        let green = AngroveTheme.Colors.lightGreen
        // Held at 25% so guides stay quiet.
        Rectangle().fill(LinearGradient(stops: [
            .init(color: green.opacity(0), location: 0), .init(color: green, location: 0.25),
            .init(color: green, location: 0.75), .init(color: green.opacity(0), location: 1)
        ], startPoint: axis == .vertical ? .top : .leading, endPoint: axis == .vertical ? .bottom : .trailing))
            .opacity(0.25)
    }
}

/// A guide draws itself from its centre outward.
private struct WorktreeGuideDraw: ViewModifier {
    let axis: WorktreeGuide.Axis
    let progress: CGFloat

    func body(content: Content) -> some View {
        content.scaleEffect(x: axis == .horizontal ? progress : 1, y: axis == .vertical ? progress : 1, anchor: .center)
    }
}

/// Not observed: see `MacWorktreeView.pointerBox`.
private final class WorktreePointer {
    var location: CGPoint?
}

/// Saves about a second after the board's saved content changes. Kept apart from the canvas so
/// panning and zooming never recompute the board's fingerprint.
private struct WorktreeAutosave: View {
    private struct SaveKey: Equatable {
        let content: Int
        let viewport: WorktreeViewport
    }
    let board: WorktreeBoard
    let onSave: () -> Void

    var body: some View {
        Color.clear
            .task(id: SaveKey(content: board.saveSignature, viewport: board.viewport)) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                onSave()
            }
    }
}

enum WorktreePicker: String, Identifiable {
    case insights, passages
    var id: String { rawValue }
}

/// Choose a saved Insight or clipped passage to place on the canvas as a card.
private struct WorktreePickerSheet: View {
    let kind: WorktreePicker
    let onPick: (ConceptDefinition) -> Void
    let onCancel: () -> Void

    private var concepts: [ConceptDefinition] {
        kind == .insights ? InsightLibraryStore.load() : ClippedPassageStore.load()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            MacPageHeading(title: kind == .insights ? "Insights" : "Clipped Passages")
            let concepts = concepts
            if concepts.isEmpty {
                Text(kind == .insights ? "No saved Insights yet." : "No clipped passages yet.")
                    .font(AngroveTheme.Typography.body)
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(concepts) { concept in
                            Button(concept.isLibraryQuote ? concept.word : concept.word.capitalized) { onPick(concept) }
                                .buttonStyle(.plain)
                                .font(AngroveTheme.Typography.body)
                                .foregroundStyle(AngroveTheme.Colors.lightGreen)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Button("Cancel", role: .cancel, action: onCancel)
        }
        .padding(28)
        .frame(width: 380, height: 420)
        .background(AngroveTheme.Colors.canvas)
    }
}
