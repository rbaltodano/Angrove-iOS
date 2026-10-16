import SwiftUI

/// Model work an item is waiting on: it breathes while queued and shimmers while running,
/// as queued and live work do in a conversation.
enum WorktreeWork: Equatable { case queued, running }

/// Everything placed on the Worktree canvas. Held by the workspace so it survives page changes;
/// saved through WorktreeLibrary.
@MainActor @Observable final class WorktreeBoard {
    struct Item: Identifiable, Equatable {
        var id = UUID()
        var followUpID = UUID()
        /// World position of the text's top-leading corner.
        var origin: CGPoint
        var text = ""
        /// The conversation behind a question card: the same session the conversation page uses,
        /// kept out of the sidebar.
        var session: MacConversationState?
        /// Set once the person resizes a question card; until then it fits its content.
        var size: CGSize?
        var followUp = ""
        /// Set by `/rename`; shown above the item.
        var label: String?
        var labelWork: WorktreeWork?
        var labelID = UUID()
        /// Made by `/heading`: 40pt Baskerville text.
        var isHeading = false
        /// A command list card from the retired `/help`, still shown in Worktrees that have one.
        var isHelp = false
        /// A picture placed from the "+" menu.
        var image: UploadedFile?
        var photoLayout: WorktreePhotoLayout?
        /// Bumped when a command sets the label, so it blurs in rather than being typed.
        var labelRevision = 0
        var labelText: String {
            get { label ?? "" }
            set { label = newValue }
        }
        /// An Insight card made by `/define`: the term while the model works, then its definition.
        var definingTerm: String?
        /// Transient inline failure; never saved, trashed, or restored by undo.
        var definitionFailureTerm: String?
        var insight: ConceptDefinition?
        /// The window the term was defined from; the card's Quote action quotes into it.
        var sourceID: UUID?
        /// A `/summarize` result while the model writes it.
        var isSummarizing = false
        /// Presentation only: restored notes and redo do not replay the initial summary reveal.
        var revealsSummary = false
        /// A conversation dropped from the sidebar: its title while it still looks like the chip.
        var arrivalTitle: String?
        var isDropped = false
        /// Dropped conversations show their latest turns first, loading earlier ones on scroll.
        var visibleTurnLimit: Int?
        /// The sidebar conversation a dropped window was copied from, and its name then.
        var sourceConversationID: UUID?
        var sourceTitle: String?
        /// The model work behind a pending Insight card or summary.
        var outputWork: WorktreeWork?
        var isQuestion: Bool { session != nil }
        var isInsight: Bool { definingTerm != nil || insight != nil }
    }

    @ObservationIgnored let history = WorktreeHistory()
    var viewport = WorktreeViewport()

    let documentID: UUID
    var items: [Item] = []
    var recentlyDeleted: [WorktreeStoredItem] = []
    @ObservationIgnored var permanentlyDeletedIDs: Set<UUID> = []
    /// Dot-grid pulses, in world space: one when something is selected or finishes.
    var ripples: [RippleTrigger] = []

    init(document: WorktreeDocument = WorktreeDocument()) {
        documentID = document.id
        customTitle = document.title
        viewport = document.viewport ?? WorktreeViewport()
        items = document.items.map(Self.restore)
        recentlyDeleted = Array((document.trash ?? []).prefix(10))
    }

    /// The board as saved; work still in progress is left out.
    func document(createdAt: Date) -> WorktreeDocument {
        WorktreeDocument(id: documentID, title: customTitle, createdAt: createdAt,
                         items: items.compactMap(Self.stored), viewport: viewport, trash: recentlyDeleted)
    }

    static func stored(_ item: Item) -> WorktreeStoredItem? {
        guard !item.isSummarizing, item.definitionFailureTerm == nil, item.definingTerm == nil || item.insight != nil else { return nil }
        return WorktreeStoredItem(id: item.id, origin: item.origin, text: item.text, size: item.size,
            label: item.label, isHeading: item.isHeading, isHelp: item.isHelp, image: item.image, insight: item.insight, sourceID: item.sourceID,
            sourceConversationID: item.sourceConversationID, sourceTitle: item.sourceTitle,
            visibleTurnLimit: item.visibleTurnLimit, conversationID: item.session?.id,
            branches: item.session?.branches, promotedIDs: item.session?.promotedIDs, photoLayout: item.photoLayout)
    }

    static func restore(_ stored: WorktreeStoredItem) -> Item {
        var item = Item(id: stored.id, origin: stored.origin, text: stored.text)
        item.size = stored.size
        item.label = stored.label
        item.isHeading = stored.isHeading
        item.isHelp = stored.isHelp ?? false
        item.image = stored.image
        item.photoLayout = stored.photoLayout
        item.insight = stored.insight
        item.sourceID = stored.sourceID
        item.sourceConversationID = stored.sourceConversationID
        item.sourceTitle = stored.sourceTitle
        item.visibleTurnLimit = stored.visibleTurnLimit
        if let branches = stored.branches, let first = branches.first {
            let session = MacConversationState()
            session.savesConversation = false
            session.configure(preview: false, conversationID: stored.conversationID)
            session.branches = branches
            session.selectedBranch = first.id
            session.promotedIDs = stored.promotedIDs ?? []
            item.session = session
        }
        return item
    }

    /// A cheap fingerprint of everything saved, so edits can be saved shortly after they happen.
    var saveSignature: Int {
        var hasher = Hasher()
        hasher.combine(customTitle)
        hasher.combine(recentlyDeleted.map(\.id))
        for item in items {
            hasher.combine(item.id)
            hasher.combine(item.origin.x); hasher.combine(item.origin.y)
            hasher.combine(item.text); hasher.combine(item.label); hasher.combine(item.isHeading)
            hasher.combine(item.photoLayout?.contentSize.width); hasher.combine(item.photoLayout?.contentSize.height)
            hasher.combine(item.photoLayout?.offset.x); hasher.combine(item.photoLayout?.offset.y)
            hasher.combine(item.size?.width); hasher.combine(item.size?.height)
            hasher.combine(item.insight?.id); hasher.combine(item.visibleTurnLimit)
            // Counts only: building the transcript here would copy every turn on each check.
            hasher.combine(item.session?.activeBranch?.activeChatBlocks.count)
            hasher.combine(item.session?.activeBranch?.topQuestionSubmitted)
            hasher.combine(item.session?.completedResponseCount)
        }
        return hasher.finalize()
    }

    /// Figma-style alignment guides shown while an item is dragged.
    var guides: [WorktreeGuide] = []

    /// An item's frame in world space, its padding included.
    func frame(of id: UUID) -> CGRect? {
        guard let item = items.first(where: { $0.id == id }), let size = itemSizes[id] else { return nil }
        let padding = item.isQuestion ? WorktreeItemView.cardPadding : WorktreeItemView.textPadding
        return CGRect(x: item.origin.x - padding, y: item.origin.y - padding, width: size.width, height: size.height)
    }

    /// Moves a dragged item, snapping its left, centre or right (and top, centre or bottom) to
    /// another item's when within `threshold`, and shows a guide along each alignment.
    func move(_ id: UUID, to proposed: CGPoint, threshold: CGFloat, overhang: CGFloat) {
        guard let current = frame(of: id) else {
            update(id) { $0.origin = proposed }
            return
        }
        let padding = current.minX - (items.first { $0.id == id }?.origin.x ?? current.minX)
        var moved = CGRect(x: proposed.x + padding, y: proposed.y + padding, width: current.width, height: current.height)
        let others = items.lazy.filter { $0.id != id }.compactMap { self.frame(of: $0.id) }

        func edges(_ rect: CGRect, _ axis: WorktreeGuide.Axis) -> [CGFloat] {
            axis == .vertical ? [rect.minX, rect.midX, rect.maxX] : [rect.minY, rect.midY, rect.maxY]
        }
        func snap(_ axis: WorktreeGuide.Axis) -> CGFloat? {
            var best: CGFloat?
            for other in others {
                for mine in edges(moved, axis) {
                    for theirs in edges(other, axis) where abs(theirs - mine) <= threshold {
                        if best.map({ abs(theirs - mine) < abs($0) }) ?? true { best = theirs - mine }
                    }
                }
            }
            return best
        }
        let dx = snap(.vertical), dy = snap(.horizontal)
        moved.origin.x += dx ?? 0
        moved.origin.y += dy ?? 0
        update(id) { $0.origin = CGPoint(x: moved.minX - padding, y: moved.minY - padding) }

        var next: [WorktreeGuide] = []
        for (axis, snapped) in [(WorktreeGuide.Axis.vertical, dx != nil), (.horizontal, dy != nil)] where snapped {
            for value in edges(moved, axis) {
                let aligned = others.filter { other in edges(other, axis).contains { abs($0 - value) < 0.5 } }
                guard !aligned.isEmpty else { continue }
                let span = aligned.reduce(moved) { $0.union($1) }
                let (low, high) = axis == .vertical ? (span.minY, span.maxY) : (span.minX, span.maxX)
                next.append(WorktreeGuide(axis: axis, position: value, start: low - overhang, end: high + overhang))
            }
        }
        if next.map(\.id) != guides.map(\.id) {
            withAnimation(.easeOut(duration: 0.15)) { guides = next }
        } else {
            guides = next
        }
    }

    /// On release the guides fade away.
    func endMove() {
        guard !guides.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.15)) { guides = [] }
    }

    /// One dot-grid pulse from an item's centre.
    func pulse(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let size = itemSizes[id] ?? .zero
        let padding = item.isQuestion ? WorktreeItemView.cardPadding : WorktreeItemView.textPadding
        let center = CGPoint(x: item.origin.x - padding + size.width / 2, y: item.origin.y - padding + size.height / 2)
        pulse(at: center)
    }

    func pulse(at center: CGPoint) {
        let now = Date().timeIntervalSinceReferenceDate
        // The grid's world space runs y-up.
        ripples = ripples.filter { now - $0.startTime < 4 } + [RippleTrigger(worldOrigin: CGPoint(x: center.x, y: -center.y), startTime: now)]
    }
    var editingID: UUID? { didSet { if oldValue != editingID { editingFocusChanged() } } }
    /// Selected items in the order picked (⇧- or ⌘-click adds); the last is the primary one.
    var selection: [UUID] = []
    var activeID: UUID? { selection.last }
    /// The item under the pointer. Commands typed with nothing selected act on it. Not observed:
    /// it changes as the pointer moves and is only read when "/" is typed.
    @ObservationIgnored var hoveredID: UUID?
    /// What the open command field acts on; its field sits beside the last.
    var commandTargets: [UUID] = []
    var errorMessage: String?
    /// The Trash control's global frame, and the item currently dragged over it.
    var trashFrame: CGRect = .zero
    var trashTargetID: UUID?
    /// The command field opened by typing "/": beside the selected item, or, with nothing
    /// selected, at a free spot where its commands act on the whole Worktree.
    let commandFieldID = UUID()
    var commandFieldSize: CGSize = .zero
    var commandTargetID: UUID?
    var commandFreeOrigin: CGPoint?
    var commandText = ""
    /// `/define` with no term: the command is struck through before the field blurs away.
    var isCommandStruck = false
    private var commandInvocationID = UUID()
    /// Each item's laid-out size in world points, so the command field can sit beside it.
    var itemSizes: [UUID: CGSize] = [:]
    var savedInsightIDs = Set(InsightLibraryStore.load().map(\.id))

    /// Set by `/rename` with nothing selected.
    var customTitle: String?
    var retitleWork: WorktreeWork?

    /// Named like a conversation: after its first question, until then a prompt.
    var title: String {
        customTitle ?? firstQuestion.flatMap(MacConversationState.automaticTitle(for:))
            ?? String(localized: "What Should We Explore Today?")
    }

    private var firstQuestion: String? {
        items.lazy.compactMap(\.session?.branches.first?.topQuestionText).first { !$0.isEmpty }
    }

    /// World position of the command field: 32pt right of the selected item's frame, level with
    /// its first line.
    var commandOrigin: CGPoint? {
        if let id = commandTargetID {
            guard let item = items.first(where: { $0.id == id }) else { return nil }
            let size = itemSizes[id] ?? item.size.map { CGSize(width: $0.width + 16, height: $0.height + 16) }
                ?? CGSize(width: 320, height: 40)
            let padding = item.isQuestion ? WorktreeItemView.cardPadding : WorktreeItemView.textPadding
            return CGPoint(x: item.origin.x - padding + size.width + 32, y: item.origin.y)
        }
        return commandFreeOrigin
    }

    /// The sidebar's window frame, and a window being dragged over it to become a conversation.
    /// Set by the workspace; read only while dragging, so it needn't be observed.
    static var sidebarFrame: CGRect = .zero
    struct SidebarDrag: Equatable {
        let id: UUID
        let title: String
        var location: CGPoint
    }
    var sidebarDrag: SidebarDrag?

    func sidebarTitle(for id: UUID) -> String? {
        guard let item = items.first(where: { $0.id == id }), let session = item.session else { return nil }
        return item.label ?? item.sourceTitle
            ?? session.branches.first.flatMap { MacConversationState.automaticTitle(for: $0.topQuestionText) }
            ?? String(localized: "New Conversation")
    }

    /// A window that came from the sidebar, asking whether to replace the sidebar's version.
    struct SidebarReplacement: Identifiable {
        let id: UUID
        let title: String
    }
    var pendingReplacement: SidebarReplacement?

    /// Dropping a window on the sidebar copies it there; the window stays on the canvas. One that
    /// came from the sidebar first asks whether to replace the version it came from.
    func dropOnSidebar(_ id: UUID, runtime: MacApplicationRuntime) {
        guard let item = items.first(where: { $0.id == id }), item.session != nil else { return }
        if item.sourceConversationID != nil {
            pendingReplacement = .init(id: id, title: sidebarTitle(for: id) ?? "")
        } else {
            saveCopy(of: id, runtime: runtime)
        }
    }

    /// Saves the window's conversation as a new sidebar conversation, named by its label or,
    /// without one, by the model.
    func saveCopy(of id: UUID, runtime: MacApplicationRuntime, keepingBoth: Bool = false) {
        guard let item = items.first(where: { $0.id == id }), let session = item.session else { return }
        let named = item.label ?? item.sourceTitle
        let fallback = session.branches.first.flatMap { MacConversationState.automaticTitle(for: $0.topQuestionText) }
        let title = named ?? fallback ?? String(localized: "New Conversation")
        let copy = InquiryConversation(title: keepingBoth ? Self.copyTitle(title) : title,
                                       branches: session.branches, promotedInsightIDs: session.promotedIDs)
        Self.store(copy)
        guard !keepingBoth, named == nil, runtime.modelIsAvailable,
              let question = session.branches.first?.topQuestionText, !question.isEmpty else { return }
        let model = runtime.model
        runtime.modelTasks.enqueue(kind: .labelWorktreeItem, conversationID: copy.id) {
            guard let title = try? await model.conversationTitle(for: question), !Task.isCancelled,
                  let snapshot = CurrentConversationsStore.load(),
                  let updated = MacSidebarConversationActions.applying(.rename(title), to: copy.id, in: snapshot) else { return }
            CurrentConversationsStore.save(updated)
            NotificationCenter.default.post(name: .macConversationMetadataChanged,
                                            object: updated.conversations.first { $0.id == copy.id })
            NotificationCenter.default.post(name: .macConversationSaved, object: nil)
        }
    }

    static func copyTitle(_ title: String) -> String {
        String(localized: "(Copy) \(title)")
    }

    /// Overwrites the sidebar conversation the window came from with the window's version.
    func replaceOriginal(with id: UUID) {
        guard let item = items.first(where: { $0.id == id }), let session = item.session,
              let sourceID = item.sourceConversationID,
              var original = CurrentConversationsStore.load()?.conversations.first(where: { $0.id == sourceID }) else { return }
        original.branches = session.branches
        original.promotedInsightIDs = session.promotedIDs
        if let label = item.label { original.title = label }
        Self.store(original)
    }

    private static func store(_ conversation: InquiryConversation) {
        var snapshot = CurrentConversationsStore.load() ?? InquiryPersistenceSnapshot(conversations: [], activeConversationID: nil)
        if let index = snapshot.conversations.firstIndex(where: { $0.id == conversation.id }) {
            snapshot.conversations[index] = conversation
        } else {
            snapshot.conversations.append(conversation)
        }
        CurrentConversationsStore.save(snapshot)
        NotificationCenter.default.post(name: .macConversationMetadataChanged, object: conversation)
        NotificationCenter.default.post(name: .macConversationSaved, object: nil)
    }

    func delete(_ id: UUID, recordsHistory: Bool = true) {
        if recordsHistory { beginHistoryAction() }
        defer { if recordsHistory { endHistoryAction() } }
        guard let item = items.first(where: { $0.id == id }) else { return }
        pulse(id)
        if recordsHistory { retainInTrash(item) }
        if [item.id, item.followUpID].contains(editingID) { editingID = nil }
        if selection.contains(id) { selection.removeAll { $0 == id } }
        if hoveredID == id { hoveredID = nil }
        if let session = item.session {
            session.markDeleted()
            MacApplicationRuntime.shared.modelTasks.cancelTasks { $0.conversationID == session.id }
        }
        if commandTargetID == id { closeCommand() }
        items.removeAll { $0.id == id }
        itemSizes[id] = nil
    }

    @discardableResult
    func addText(at origin: CGPoint, text: String = "") -> UUID {
        beginHistoryAction()
        defer { endHistoryAction() }
        endEditing()
        let item = Item(origin: origin, text: text)
        items.append(item)
        editingID = item.id
        return item.id
    }

    /// Ends editing and drops text items left empty.
    func endEditing() {
        items.removeAll { !$0.isQuestion && !$0.isInsight && !$0.isSummarizing && !$0.isHelp && $0.image == nil && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        editingID = nil
    }

    /// Clearing a label removes it.
    func finishLabelEditing(_ id: UUID) {
        if editingID == items.first(where: { $0.id == id })?.labelID { editingID = nil }
        update(id) {
            let trimmed = $0.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            $0.label = trimmed.isEmpty ? nil : trimmed
        }
    }

    func binding(_ id: UUID, _ keyPath: WritableKeyPath<Item, String>) -> Binding<String> {
        Binding(get: { [self] in items.first { $0.id == id }?[keyPath: keyPath] ?? "" },
                set: { [self] in if let i = index(id) { items[i][keyPath: keyPath] = $0 } })
    }

    func update(_ id: UUID, _ change: (inout Item) -> Void) {
        if let i = index(id) { change(&items[i]) }
    }

    /// Selects only `id` (or nothing). Changing the selection puts away the command field.
    func select(_ id: UUID?) {
        let next = id.map { [$0] } ?? []
        if isCommandOpen, !commandTargets.isEmpty, commandTargets != next { closeCommand() }
        if selection != next {
            selection = next
            if let id { pulse(id) }
        }
        if let id, items.first(where: { $0.id == id })?.isQuestion == true { lastWindowID = id }
    }

    /// ⇧- or ⌘-click: adds an item to the selection, or takes it out.
    func toggleSelection(_ id: UUID) {
        if isCommandOpen, !commandTargets.isEmpty { closeCommand() }
        if let index = selection.firstIndex(of: id) {
            selection.remove(at: index)
        } else {
            selection.append(id)
            pulse(id)
            if items.first(where: { $0.id == id })?.isQuestion == true { lastWindowID = id }
        }
    }

    func setHovered(_ id: UUID, _ isHovered: Bool) {
        if isHovered { hoveredID = id } else if hoveredID == id { hoveredID = nil }
    }

    /// The conversation window most recently selected or made; dropped conversations match its size.
    private var lastWindowID: UUID?
    private var lastWindowSize: CGSize? {
        guard let id = lastWindowID, let item = items.first(where: { $0.id == id }) else { return nil }
        return item.size ?? itemSizes[id]
    }

    /// Places a copy of a sidebar conversation as a window: follow-ups stay on the canvas until it
    /// is dragged back. It lands as the sidebar chip, then opens and takes the conversation's name.
    func addConversation(_ conversationID: UUID, at origin: CGPoint) {
        beginHistoryAction()
        defer { endHistoryAction() }
        guard let conversation = CurrentConversationsStore.load()?.conversations.first(where: { $0.id == conversationID }) else { return }
        let session = MacConversationState()
        session.savesConversation = false
        session.configure(preview: false, conversationID: conversationID)
        var item = Item(origin: origin)
        item.session = session
        item.isDropped = true
        item.arrivalTitle = conversation.title
        item.visibleTurnLimit = 5
        item.sourceConversationID = conversationID
        item.sourceTitle = conversation.title
        item.size = lastWindowSize ?? CGSize(width: WorktreeItemView.cardWidth, height: WorktreeItemView.cardMaxHeight)
        items.append(item)
        let id = item.id
        select(id)
        Task { @MainActor [self] in
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.springStandard) { update(id) { $0.arrivalTitle = nil } }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.springStandard) { update(id) { $0.label = conversation.title; $0.labelRevision += 1 } }
        }
    }

    /// Return: text opened with a quotation mark becomes a question card and is answered;
    /// any commands typed after it queue behind the answer.
    func commit(_ id: UUID, runtime: MacApplicationRuntime) {
        beginHistoryAction()
        defer { endHistoryAction() }
        defer { endEditing() }
        guard let item = items.first(where: { $0.id == id }), !item.isQuestion else { return }
        let input = WorktreeCommandParser.parse(item.text, requiresQuotes: true)
        if let question = input.question {
            let session = MacConversationState()
            session.savesConversation = false
            session.configure(preview: false)
            guard send(question, in: session, runtime: runtime) else { return }
            update(id) { $0.session = session }
            lastWindowID = id
        } else if !input.commands.isEmpty, let first = WorktreeCommandParser.commandRanges(in: item.text).first {
            // A plain note keeps only its text; the commands act on it.
            update(id) { $0.text = (item.text as NSString).substring(to: first.location).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        run(input.commands, on: id, runtime: runtime)
    }

    func askFollowUp(in id: UUID, runtime: MacApplicationRuntime) {
        guard let item = items.first(where: { $0.id == id }), let session = item.session, session.isComposerReady else { return }
        let input = WorktreeCommandParser.parse(item.followUp, requiresQuotes: false)
        guard input.question != nil || !input.commands.isEmpty else { return }
        if let question = input.question, !send(question, in: session, runtime: runtime) { return }
        update(id) { $0.followUp = "" }
        run(input.commands, on: id, runtime: runtime)
    }

    /// Typing "/" opens the command field beside the selection, else the hovered item, else at
    /// `freeOrigin`, where its commands act on the whole Worktree.
    var commandSelection: [UUID] {
        let selected = selection.filter { id in items.contains { $0.id == id } }
        if let hoveredID, items.contains(where: { $0.id == hoveredID }), !selected.contains(hoveredID) {
            return [hoveredID]
        }
        return selected
    }

    func openCommand(freeOrigin: CGPoint? = nil, text: String = "/", targets chosen: [UUID]? = nil) -> Bool {
        let targets = chosen ?? commandSelection
        guard !targets.isEmpty || freeOrigin != nil else { return false }
        withAnimation(.springQuick) {
            commandInvocationID = UUID()
            commandTargets = targets
            commandTargetID = targets.last
            commandFreeOrigin = targets.isEmpty ? freeOrigin : nil
            commandText = text
            isCommandStruck = false
            editingID = commandFieldID
        }
        return true
    }

    var isCommandOpen: Bool { commandTargetID != nil || commandFreeOrigin != nil }

    /// What a tool's shortcut acts on: what is selected, else the item being edited, else the
    /// hovered item. Unlike "/", a hovered item never takes over from the selection.
    var shortcutTargets: [UUID] {
        let selected = selection.filter { id in items.contains { $0.id == id } }
        if !selected.isEmpty { return selected }
        if let editingID, let item = items.first(where: { [$0.id, $0.followUpID, $0.labelID].contains(editingID) }) {
            return [item.id]
        }
        if let hoveredID, items.contains(where: { $0.id == hoveredID }) { return [hoveredID] }
        return []
    }

    /// A tool's shortcut, or a tool clicked onto something: its command appears in the field as if
    /// typed. With something to act on it then runs; with nothing it waits, so a term or text can
    /// follow. `/file` is opened by the page, which owns the file browser.
    func runTool(_ tool: WorktreeTool, on targets: [UUID], freeOrigin: CGPoint, runtime: MacApplicationRuntime) {
        guard let command = tool.command, tool != .file else { return }
        let typed = targets.isEmpty ? command.full + " " : command.full
        guard openCommand(freeOrigin: freeOrigin, text: typed, targets: targets), !targets.isEmpty else { return }
        let invocation = commandInvocationID
        Task { @MainActor [self] in
            // Long enough to read the command before it gives way to its work.
            try? await Task.sleep(for: .milliseconds(280))
            guard commandInvocationID == invocation, isCommandOpen else { return }
            submitCommand(runtime: runtime)
        }
    }

    /// The topmost item whose frame contains a world point.
    func item(at point: CGPoint) -> UUID? {
        let ordered = items.filter { !selection.contains($0.id) } + items.filter { selection.contains($0.id) }
        return ordered.last { frame(of: $0.id)?.contains(point) == true }?.id
    }

    /// The Heading tool: an empty heading at `origin`, ready to type into. Left empty, it goes away.
    func addHeadingField(at origin: CGPoint) {
        beginHistoryAction()
        defer { endHistoryAction() }
        endEditing()
        var heading = Item(origin: origin)
        heading.isHeading = true
        items.append(heading)
        editingID = heading.id
    }

    /// Bumped by `/file`; the page opens its file browser in response.
    var fileRequest = 0

    func closeCommand(animated: Bool = true) {
        guard isCommandOpen else { return }
        if let origin = commandOrigin {
            pulse(at: CGPoint(x: origin.x + commandFieldSize.width / 2, y: origin.y + commandFieldSize.height / 2))
        }
        var transaction = Transaction(animation: animated ? .easeOut(duration: 0.25) : nil)
        transaction.disablesAnimations = !animated
        withTransaction(transaction) {
            commandTargetID = nil
            commandTargets = []
            commandFreeOrigin = nil
            isCommandStruck = false
            if editingID == commandFieldID { editingID = nil }
        }
        commandText = ""
        commandFieldSize = .zero
    }

    func submitCommand(runtime: MacApplicationRuntime) {
        guard isCommandOpen, !isCommandStruck else { return }
        let targets = commandTargets
        let commands = WorktreeCommandParser.parse(commandText, requiresQuotes: true).commands
        let trimmed = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        let startsWithCommand = WorktreeCommandParser.commandRanges(in: trimmed).first?.location == 0
        // Unrecognised, misformed, meaningless here, or object dependent with nothing selected:
        // strike it through, then blur it away. Nothing runs.
        if commands.isEmpty || !startsWithCommand || commands.contains(where: { !canRun($0, on: targets) }) {
            withAnimation(.easeOut(duration: 0.42)) { isCommandStruck = true }
            let invocation = commandInvocationID
            Task { @MainActor [self] in
                try? await Task.sleep(for: .milliseconds(650))
                guard commandInvocationID == invocation else { return }
                closeCommand()
            }
            return
        }
        // A command that makes something replaces the field in place, without fading.
        let origin = commandOrigin
        closeCommand(animated: !commands.contains(where: \.isObjectDependent))
        run(commands, on: targets, at: origin, runtime: runtime)
    }

    func canRun(_ command: WorktreeCommand, on ids: [UUID]) -> Bool {
        let targets = items.filter { ids.contains($0.id) }
        switch command {
        case .define(let term):
            if let term, !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
            return !targets.isEmpty && !targets.contains(where: \.isInsight)
                && !material(for: ids).isEmpty
        case .heading(let text):
            return !targets.contains(where: \.isHeading)
                && (text != nil || !material(for: ids).isEmpty)
        case .summarize: return !material(for: ids).isEmpty
        case .label, .file: return true
        }
    }

    private func run(_ commands: [WorktreeCommand], on id: UUID?, at origin: CGPoint? = nil, runtime: MacApplicationRuntime) {
        run(commands, on: id.map { [$0] } ?? [], at: origin, runtime: runtime)
    }

    /// `ids` are the items the commands act on (none: the whole Worktree). `/rename` names each;
    /// `/define` and `/summarize` read them together. What commands make starts at `origin`, or
    /// just right of the last item, and stacks.
    private func run(_ commands: [WorktreeCommand], on ids: [UUID], at origin: CGPoint? = nil, runtime: MacApplicationRuntime) {
        beginHistoryAction()
        defer { endHistoryAction() }
        let id = ids.last
        var next = origin ?? id.flatMap(outputOrigin(beside:))
        for command in commands where canRun(command, on: ids) {
            switch command {
            case .label(let text?):
                withAnimation(.springStandard) {
                    if ids.isEmpty { customTitle = text }
                    for id in ids { update(id) { $0.label = text; $0.labelRevision += 1 } }
                }
            case .label(nil):
                if ids.isEmpty { generateTitle(runtime: runtime) }
                for id in ids { generateLabel(for: id, runtime: runtime) }
            case .define(let term):
                guard let place = next else { continue }
                define(term, at: place, from: ids, runtime: runtime)
                next = CGPoint(x: place.x, y: place.y + 56)
            case .summarize:
                guard !ids.isEmpty, let place = next else { continue }
                summarize(ids, at: place, runtime: runtime)
                next = CGPoint(x: place.x, y: place.y + 56)
            case .heading(let text):
                guard let place = next else { continue }
                addHeading(text, from: ids, at: place, runtime: runtime)
                next = CGPoint(x: place.x, y: place.y + 72)
            case .file:
                fileRequest += 1
            }
        }
    }

    private func outputOrigin(beside id: UUID) -> CGPoint? {
        guard let item = items.first(where: { $0.id == id }) else { return nil }
        let size = itemSizes[id] ?? item.size ?? CGSize(width: 320, height: 40)
        let padding = item.isQuestion ? WorktreeItemView.cardPadding : WorktreeItemView.textPadding
        return CGPoint(x: item.origin.x - padding + size.width + 24, y: item.origin.y)
    }

    /// Several items read together, fitted to the on-device context as a whole.
    private func material(for ids: [UUID]) -> [ChatBlock] {
        guard ids.count > 1 else { return material(for: ids.first) }
        return Self.fitting(ids.flatMap { material(for: $0) }, earlier: nil)
    }

    /// What the model reads for an item: a window's whole conversation (not just the turns on
    /// screen), an Insight's definition, or text.
    private func material(for id: UUID?) -> [ChatBlock] {
        guard let item = id.flatMap({ id in items.first { $0.id == id } }) else { return [] }
        if let session = item.session { return Self.fitting(session.transcript, earlier: session.activeBranch?.compactedContext) }
        if let insight = item.insight { return [.text("\(insight.word): \(insight.meaning)")] }
        if let image = item.image { return [.user("Selected photo", nil, [image])] }
        if item.isHelp { return [.text(WorktreeCommandGuide.entries.map { "\($0.name): \($0.explanation)" }.joined(separator: "\n"))] }
        return item.text.isEmpty ? [] : [.text(item.text)]
    }

    /// Places a summary at `origin`, showing Summarizing until the model writes it;
    /// it then becomes ordinary editable text.
    private func summarize(_ sources: [UUID], at origin: CGPoint, runtime: MacApplicationRuntime) {
        guard runtime.modelIsAvailable, let sourceID = sources.last else { errorMessage = UnavailableAngroveModel.unavailableMessage; return }
        let transcript = material(for: sources)
        guard !transcript.isEmpty else { return }
        var note = Item(origin: origin)
        note.isSummarizing = true
        note.outputWork = .queued
        note.sourceID = sourceID
        items.append(note)
        let id = note.id
        let context = ConversationContext(transcript: transcript, personality: runtime.modelTasks.personality)
        let model = runtime.model
        runtime.modelTasks.enqueue(kind: .summarizeWorktreeItem, conversationID: items.first { $0.id == sourceID }?.session?.id,
            onStart: { [self] in withAnimation(.springStandard) { update(id) { $0.outputWork = .running } } },
            onCancel: { [self] in withAnimation(.easeOut(duration: 0.25)) { delete(id) } }) { [self] in
            do {
                let summary = try await model.summarize(context)
                guard !Task.isCancelled else { return }
                beginHistoryAction()
                defer { endHistoryAction() }
                withAnimation(.springStandard) { update(id) { $0.text = summary; $0.isSummarizing = false; $0.outputWork = nil; $0.revealsSummary = true } }
                pulse(id)
            } catch {
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.25)) { delete(id) }
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Places saved Insights or clipped passages as cards, and pictures, from the "+" menu.
    func addInsight(_ concept: ConceptDefinition, at origin: CGPoint) {
        beginHistoryAction()
        defer { endHistoryAction() }
        var card = Item(origin: origin)
        card.insight = concept
        withAnimation(.springStandard) { items.append(card) }
        select(card.id)
    }

    /// A placement click is one undoable action; use its known bounds for an immediate ripple.
    func placePhoto(_ file: UploadedFile, size: CGSize, at origin: CGPoint) {
        guard file.imageData != nil else { return }
        beginHistoryAction()
        defer { endHistoryAction() }
        var picture = Item(origin: origin)
        picture.image = UploadedFile(id: file.id, name: file.name, imageData: file.imageData, rotationDegrees: 0)
        picture.size = size
        picture.photoLayout = WorktreePhotoLayout(contentSize: size)
        itemSizes[picture.id] = CGSize(width: size.width + WorktreeItemView.textPadding * 2,
                                      height: size.height + WorktreeItemView.textPadding * 2)
        withAnimation(.springLively) { items.append(picture) }
        pulse(picture.id)
    }

    func addImages(_ files: [UploadedFile], at origin: CGPoint) {
        beginHistoryAction()
        defer { endHistoryAction() }
        for (offset, file) in files.enumerated() where file.imageData != nil {
            var picture = Item(origin: CGPoint(x: origin.x + CGFloat(offset) * 24, y: origin.y + CGFloat(offset) * 24))
            picture.image = file
            withAnimation(.springStandard) { items.append(picture) }
        }
    }

    /// Places an Insight card at `origin` and asks the model for the definition, in the context
    /// of the window it came from.
    private func define(_ requestedTerm: String?, at origin: CGPoint, from sources: [UUID], runtime: MacApplicationRuntime) {
        let sourceID = sources.last
        var card = Item(origin: origin)
        card.definingTerm = requestedTerm ?? String(localized: "Selection")
        card.outputWork = .queued
        card.sourceID = sourceID
        items.append(card)
        let id = card.id
        guard runtime.modelIsAvailable else {
            showDefinitionFailure(id, term: card.definingTerm ?? "")
            return
        }
        let source = sourceID.flatMap { sid in items.first { $0.id == sid } }
        let selectedItems = sources.compactMap { sid in items.first { $0.id == sid } }
        let transcript = material(for: sources)
        let context = ConversationContext(transcript: transcript, personality: runtime.modelTasks.personality)
        let conversationID = source?.session?.id
        let model = runtime.model
        let pendingTerm = requestedTerm ?? String(localized: "Selection")
        runtime.modelTasks.enqueue(kind: .defineInsight(key: pendingTerm.lowercased(), name: pendingTerm), conversationID: conversationID,
            onStart: { [self] in withAnimation(.springStandard) { update(id) { $0.outputWork = .running } } },
            onCancel: { [self] in withAnimation(.easeOut(duration: 0.25)) { delete(id) } }) { [self] in
            do {
                let term: String
                if let requestedTerm { term = requestedTerm }
                else {
                    term = try await Self.subject(of: selectedItems, context: context, model: model)
                }
                guard !Task.isCancelled else { return }
                update(id) { $0.definingTerm = term }
                let concept = try await model.defineTerm(term, in: context, conversationID: conversationID)
                guard !Task.isCancelled else { return }
                beginHistoryAction()
                defer { endHistoryAction() }
                withAnimation(.springStandard) { update(id) { $0.insight = concept; $0.definingTerm = nil; $0.outputWork = nil } }
                pulse(id)
            } catch {
                guard !Task.isCancelled else { return }
                let term = items.first { $0.id == id }?.definingTerm ?? pendingTerm
                showDefinitionFailure(id, term: term)
            }
        }
    }

    func showDefinitionFailure(_ id: UUID, term: String) {
        withAnimation(.springStandard) {
            update(id) { $0.definitionFailureTerm = term; $0.outputWork = nil }
        }
    }

    func dismissDefinitionFailure(_ id: UUID) {
        guard items.contains(where: { $0.id == id && $0.definitionFailureTerm != nil }) else { return }
        withAnimation(.easeOut(duration: 0.35)) { delete(id, recordsHistory: false) }
    }

    func toggleSaved(_ concept: ConceptDefinition) {
        var library = InsightLibraryStore.load()
        if savedInsightIDs.contains(concept.id) {
            library.removeAll { $0.id == concept.id }
            savedInsightIDs.remove(concept.id)
        } else {
            library.append(concept)
            savedInsightIDs.insert(concept.id)
        }
        InsightLibraryStore.save(library)
    }

    private static func subject(of sources: [Item], context: ConversationContext,
                                model: any AngroveModel) async throws -> String {
        if sources.count == 1, let item = sources.first, item.image == nil {
            let text = item.insight?.word ?? item.label
                ?? item.session?.branches.first?.topQuestionText ?? item.text
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 80 { return text }
        }
        let summary = try await model.summarize(context)
        try Task.checkCancellation()
        return try await model.conversationTitle(for: summary)
    }

    private func addHeading(_ text: String?, from ids: [UUID], at origin: CGPoint, runtime: MacApplicationRuntime) {
        guard text != nil || runtime.modelIsAvailable else {
            errorMessage = UnavailableAngroveModel.unavailableMessage; return
        }
        let sources = ids.compactMap { id in items.first { $0.id == id } }
        let context = ConversationContext(transcript: material(for: ids), personality: runtime.modelTasks.personality)
        var heading = Item(origin: origin, text: text ?? "/heading")
        heading.isHeading = true
        heading.isSummarizing = text == nil
        heading.outputWork = text == nil ? .queued : nil
        items.append(heading)
        let id = heading.id
        guard text == nil else { Task { @MainActor [self] in await Task.yield(); pulse(id) }; return }
        let model = runtime.model
        runtime.modelTasks.enqueue(kind: .labelWorktreeItem,
            onStart: { [self] in update(id) { $0.outputWork = .running } },
            onCancel: { [self] in delete(id) }) { [self] in
            do {
                let title = try await Self.subject(of: sources, context: context, model: model)
                guard !Task.isCancelled else { return }
                beginHistoryAction()
                defer { endHistoryAction() }
                withAnimation(.springStandard) { update(id) { $0.text = title; $0.isSummarizing = false; $0.outputWork = nil } }
                pulse(id)
            } catch {
                guard !Task.isCancelled else { return }
                delete(id)
                errorMessage = error.localizedDescription
            }
        }
    }

    /// The Worktree's title from the conversation-title prompt, given its first question.
    private func generateTitle(runtime: MacApplicationRuntime) {
        guard let source = firstQuestion ?? items.lazy.map(\.text).first(where: { !$0.isEmpty }) else { return }
        guard runtime.modelIsAvailable else { errorMessage = UnavailableAngroveModel.unavailableMessage; return }
        let model = runtime.model
        withAnimation(.springStandard) { retitleWork = .queued }
        runtime.modelTasks.enqueue(kind: .labelWorktreeItem,
            // With an idle queue this runs in the same update as `.queued`; animate it too so the
            // text still blurs in.
            onStart: { [self] in withAnimation(.springStandard) { retitleWork = .running } },
            onCancel: { [self] in withAnimation(.easeOut(duration: 0.25)) { retitleWork = nil } }) { [self] in
            let title = try? await model.conversationTitle(for: source)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { retitleWork = nil }
            guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return }
            Task { @MainActor [self] in
                try? await Task.sleep(for: .milliseconds(250))
                beginHistoryAction()
                defer { endHistoryAction() }
                withAnimation(.springStandard) { customTitle = title }
            }
        }
    }

    /// The conversation-title prompt, given the item's first question (or its text). Queued like
    /// any model work, so a label typed after a question arrives after the answer.
    private func generateLabel(for id: UUID, runtime: MacApplicationRuntime) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let context = ConversationContext(transcript: material(for: id), personality: runtime.modelTasks.personality)
        guard !context.transcript.isEmpty else { return }
        guard runtime.modelIsAvailable else { errorMessage = UnavailableAngroveModel.unavailableMessage; return }
        let model = runtime.model
        withAnimation(.springStandard) { update(id) { $0.labelWork = .queued } }
        runtime.modelTasks.enqueue(kind: .labelWorktreeItem, conversationID: item.session?.id,
            onStart: { [self] in withAnimation(.springStandard) { update(id) { $0.labelWork = .running } } },
            onCancel: { [self] in withAnimation(.easeOut(duration: 0.25)) { update(id) { $0.labelWork = nil } } }) { [self] in
            let title: String?
            do {
                let source: String
                if item.image != nil { source = try await model.summarize(context) }
                else { source = item.insight?.word ?? item.session?.branches.first?.topQuestionText ?? item.text }
                title = try await model.conversationTitle(for: source)
            } catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
                title = nil
            }
            guard !Task.isCancelled else { return }
            // "Labeling..." blurs away first, then the label blurs in.
            withAnimation(.easeOut(duration: 0.25)) { update(id) { $0.labelWork = nil } }
            guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return }
            Task { @MainActor [self] in
                try? await Task.sleep(for: .milliseconds(250))
                beginHistoryAction()
                defer { endHistoryAction() }
                withAnimation(.springStandard) { update(id) { $0.label = title; $0.labelRevision += 1 } }
                pulse(id)
            }
        }
    }

    private func send(_ question: String, in session: MacConversationState, runtime: MacApplicationRuntime) -> Bool {
        if session.send(question, runtime: runtime) { return true }
        errorMessage = session.errorMessage
        session.errorMessage = nil
        session.showsError = false
        return false
    }

    /// The on-device model's context is small: keep the newest turns that fit, behind any
    /// compacted summary of earlier ones.
    static func fitting(_ transcript: [ChatBlock], earlier: String?, budget: Int = 9000) -> [ChatBlock] {
        var kept: [ChatBlock] = []
        var used = earlier?.count ?? 0
        for block in transcript.reversed() {
            let length: Int = switch block {
            case .user(let text, _, _): text.count
            case .text(let text): text.count
            }
            guard used + length <= budget || kept.isEmpty else { break }
            used += length
            kept.insert(block, at: 0)
        }
        if let earlier, !earlier.isEmpty, kept.count < transcript.count { kept.insert(.text(earlier), at: 0) }
        return kept
    }

    private func index(_ id: UUID) -> Int? { items.firstIndex { $0.id == id } }
}

/// An alignment guide in world space.
struct WorktreeGuide: Identifiable, Equatable {
    enum Axis { case vertical, horizontal }
    let axis: Axis
    let position: CGFloat
    var start: CGFloat
    var end: CGFloat
    var id: String { "\(axis)-\(Int((position * 2).rounded()))" }
}

/// Items compare their conversation by identity, so unchanged canvas items can be skipped.
extension MacConversationState: Equatable {
    nonisolated static func == (lhs: MacConversationState, rhs: MacConversationState) -> Bool { lhs === rhs }
}
