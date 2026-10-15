import SwiftUI

/// Model work an item is waiting on: it breathes while queued and shimmers while running,
/// as queued and live work do in a conversation.
enum WorktreeWork: Equatable { case queued, running }

/// Everything placed on the Worktree canvas. Held by the workspace so it survives page changes;
/// not persisted yet.
@MainActor @Observable final class WorktreeBoard {
    struct Item: Identifiable {
        let id = UUID()
        let followUpID = UUID()
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
        let labelID = UUID()
        /// Bumped when a command sets the label, so it blurs in rather than being typed.
        var labelRevision = 0
        var labelText: String {
            get { label ?? "" }
            set { label = newValue }
        }
        /// An Insight card made by `/define`: the term while the model works, then its definition.
        var definingTerm: String?
        var insight: ConceptDefinition?
        /// The window the term was defined from; the card's Quote action quotes into it.
        var sourceID: UUID?
        /// A `/summarize` result while the model writes it.
        var isSummarizing = false
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

    var items: [Item] = []
    var editingID: UUID?
    /// The conversation window last clicked; it lifts above the others.
    var activeID: UUID?
    var errorMessage: String?
    /// The Trash control's global frame, and the item currently dragged over it.
    var trashFrame: CGRect = .zero
    var trashTargetID: UUID?
    /// The command field opened by typing "/": beside the selected item, or, with nothing
    /// selected, at a free spot where its commands act on the whole Worktree.
    let commandFieldID = UUID()
    var commandTargetID: UUID?
    var commandFreeOrigin: CGPoint?
    var commandText = ""
    /// `/define` with no term: the command is struck through before the field blurs away.
    var isCommandStruck = false
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

    /// World position of the command field: 16pt right of the selected item's frame, level with
    /// its first line.
    var commandOrigin: CGPoint? {
        if let id = commandTargetID {
            guard let item = items.first(where: { $0.id == id }), let size = itemSizes[id] else { return nil }
            let padding = item.isQuestion ? WorktreeItemView.cardPadding : WorktreeItemView.textPadding
            return CGPoint(x: item.origin.x - padding + size.width + 16, y: item.origin.y)
        }
        return commandFreeOrigin
    }

    /// The sidebar's window frame, and a window being dragged over it to become a conversation.
    var sidebarFrame: CGRect = .zero
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
    func saveCopy(of id: UUID, runtime: MacApplicationRuntime) {
        guard let item = items.first(where: { $0.id == id }), let session = item.session else { return }
        let named = item.label ?? item.sourceTitle
        let fallback = session.branches.first.flatMap { MacConversationState.automaticTitle(for: $0.topQuestionText) }
        let copy = InquiryConversation(title: named ?? fallback ?? String(localized: "New Conversation"),
                                       branches: session.branches, promotedInsightIDs: session.promotedIDs)
        Self.store(copy)
        guard named == nil, runtime.modelIsAvailable,
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

    func delete(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        if [item.id, item.followUpID].contains(editingID) { editingID = nil }
        if activeID == id { select(nil) }
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
        endEditing()
        let item = Item(origin: origin, text: text)
        items.append(item)
        editingID = item.id
        return item.id
    }

    /// Ends editing and drops text items left empty.
    func endEditing() {
        editingID = nil
        items.removeAll { !$0.isQuestion && !$0.isInsight && !$0.isSummarizing && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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

    /// Selecting another item, or none, puts away the command field.
    func select(_ id: UUID?) {
        if commandTargetID != nil, commandTargetID != id { closeCommand() }
        if activeID != id { activeID = id }
        if let id, items.first(where: { $0.id == id })?.isQuestion == true { lastWindowID = id }
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

    /// Typing "/" opens the command field beside the selected item, or at `freeOrigin`.
    func openCommand(freeOrigin: CGPoint? = nil) -> Bool {
        guard activeID != nil || freeOrigin != nil else { return false }
        withAnimation(.springQuick) {
            commandTargetID = activeID
            commandFreeOrigin = activeID == nil ? freeOrigin : nil
            commandText = "/"
            isCommandStruck = false
            editingID = commandFieldID
        }
        return true
    }

    var isCommandOpen: Bool { commandTargetID != nil || commandFreeOrigin != nil }

    func closeCommand(animated: Bool = true) {
        guard isCommandOpen else { return }
        var transaction = Transaction(animation: animated ? .easeOut(duration: 0.25) : nil)
        transaction.disablesAnimations = !animated
        withTransaction(transaction) {
            commandTargetID = nil
            commandFreeOrigin = nil
            isCommandStruck = false
            if editingID == commandFieldID { editingID = nil }
        }
        commandText = ""
    }

    func submitCommand(runtime: MacApplicationRuntime) {
        guard isCommandOpen, !isCommandStruck else { return }
        let target = commandTargetID
        let commands = WorktreeCommandParser.parse(commandText, requiresQuotes: true).commands
        let trimmed = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        let startsWithCommand = WorktreeCommandParser.commandRanges(in: trimmed).first?.location == 0
        // Unrecognised, misformed, meaningless here, or object dependent with nothing selected:
        // strike it through, then blur it away. Nothing runs.
        if commands.isEmpty || !startsWithCommand || commands.contains(.define(nil))
            || (target == nil && commands.contains(where: \.isObjectDependent)) {
            withAnimation(.easeOut(duration: 0.42)) { isCommandStruck = true }
            Task { @MainActor [self] in
                try? await Task.sleep(for: .milliseconds(650))
                closeCommand()
            }
            return
        }
        // A command that makes something replaces the field in place, without fading.
        let origin = commandOrigin
        closeCommand(animated: !commands.contains(where: \.isObjectDependent))
        run(commands, on: target, at: origin, runtime: runtime)
    }

    /// `id` is the item the commands act on; nil acts on the whole Worktree. Things the commands
    /// make (Insight cards, summaries) start at `origin`, or just right of the item, and stack.
    private func run(_ commands: [WorktreeCommand], on id: UUID?, at origin: CGPoint? = nil, runtime: MacApplicationRuntime) {
        var next = origin ?? id.flatMap(outputOrigin(beside:))
        for command in commands {
            switch command {
            case .label(let text?):
                withAnimation(.springStandard) {
                    if let id { update(id) { $0.label = text; $0.labelRevision += 1 } } else { customTitle = text }
                }
            case .label(nil):
                if let id { generateLabel(for: id, runtime: runtime) } else { generateTitle(runtime: runtime) }
            case .define(let term?):
                guard let id, let place = next else { continue }
                define(term, at: place, from: id, runtime: runtime)
                next = CGPoint(x: place.x, y: place.y + 56)
            case .summarize:
                guard let id, let place = next else { continue }
                summarize(id, at: place, runtime: runtime)
                next = CGPoint(x: place.x, y: place.y + 56)
            case .define(nil):
                continue
            }
        }
    }

    private func outputOrigin(beside id: UUID) -> CGPoint? {
        guard let item = items.first(where: { $0.id == id }), let size = itemSizes[id] else { return nil }
        let padding = item.isQuestion ? WorktreeItemView.cardPadding : WorktreeItemView.textPadding
        return CGPoint(x: item.origin.x - padding + size.width + 24, y: item.origin.y)
    }

    /// What the model reads for an item: a window's whole conversation (not just the turns on
    /// screen), an Insight's definition, or text.
    private func material(for id: UUID?) -> [ChatBlock] {
        guard let item = id.flatMap({ id in items.first { $0.id == id } }) else { return [] }
        if let session = item.session { return Self.fitting(session.transcript, earlier: session.activeBranch?.compactedContext) }
        if let insight = item.insight { return [.text("\(insight.word): \(insight.meaning)")] }
        return item.text.isEmpty ? [] : [.text(item.text)]
    }

    /// Places a summary at `origin`, shimmering as the typed command until the model writes it;
    /// it then becomes ordinary editable text.
    private func summarize(_ sourceID: UUID, at origin: CGPoint, runtime: MacApplicationRuntime) {
        guard runtime.modelIsAvailable else { errorMessage = UnavailableAngroveModel.unavailableMessage; return }
        let transcript = material(for: sourceID)
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
                withAnimation(.springStandard) { update(id) { $0.text = summary; $0.isSummarizing = false; $0.outputWork = nil } }
            } catch {
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.25)) { delete(id) }
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Places an Insight card at `origin` and asks the model for the definition, in the context
    /// of the window it came from.
    private func define(_ term: String, at origin: CGPoint, from sourceID: UUID?, runtime: MacApplicationRuntime) {
        guard runtime.modelIsAvailable else { errorMessage = UnavailableAngroveModel.unavailableMessage; return }
        var card = Item(origin: origin)
        card.definingTerm = term
        card.outputWork = .queued
        card.sourceID = sourceID
        items.append(card)
        let id = card.id
        let source = sourceID.flatMap { sid in items.first { $0.id == sid } }
        let transcript = material(for: sourceID)
        let context = ConversationContext(transcript: transcript, personality: runtime.modelTasks.personality)
        let conversationID = source?.session?.id
        let model = runtime.model
        runtime.modelTasks.enqueue(kind: .defineInsight(key: term.lowercased(), name: term), conversationID: conversationID,
            onStart: { [self] in withAnimation(.springStandard) { update(id) { $0.outputWork = .running } } },
            onCancel: { [self] in withAnimation(.easeOut(duration: 0.25)) { delete(id) } }) { [self] in
            do {
                let concept = try await model.defineTerm(term, in: context, conversationID: conversationID)
                guard !Task.isCancelled else { return }
                withAnimation(.springStandard) { update(id) { $0.insight = concept; $0.definingTerm = nil; $0.outputWork = nil } }
            } catch {
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.25)) { delete(id) }
                errorMessage = error.localizedDescription
            }
        }
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
                withAnimation(.springStandard) { customTitle = title }
            }
        }
    }

    /// The conversation-title prompt, given the item's first question (or its text). Queued like
    /// any model work, so a label typed after a question arrives after the answer.
    private func generateLabel(for id: UUID, runtime: MacApplicationRuntime) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let source = (item.session?.branches.first?.topQuestionText ?? item.text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        guard runtime.modelIsAvailable else { errorMessage = UnavailableAngroveModel.unavailableMessage; return }
        let model = runtime.model
        withAnimation(.springStandard) { update(id) { $0.labelWork = .queued } }
        runtime.modelTasks.enqueue(kind: .labelWorktreeItem, conversationID: item.session?.id,
            onStart: { [self] in withAnimation(.springStandard) { update(id) { $0.labelWork = .running } } },
            onCancel: { [self] in withAnimation(.easeOut(duration: 0.25)) { update(id) { $0.labelWork = nil } } }) { [self] in
            let title = try? await model.conversationTitle(for: source)
            guard !Task.isCancelled else { return }
            // "Labeling..." blurs away first, then the label blurs in.
            withAnimation(.easeOut(duration: 0.25)) { update(id) { $0.labelWork = nil } }
            guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return }
            Task { @MainActor [self] in
                try? await Task.sleep(for: .milliseconds(250))
                withAnimation(.springStandard) { update(id) { $0.label = title; $0.labelRevision += 1 } }
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
