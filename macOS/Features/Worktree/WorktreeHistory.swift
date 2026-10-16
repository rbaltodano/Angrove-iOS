import AppKit

/// In-memory canvas history. Text fields retain their native editing undo manager.
@MainActor final class WorktreeHistory {
    struct Snapshot {
        var items: [WorktreeBoard.Item]
        var title: String?
        var trash: [WorktreeStoredItem]
    }

    let manager: UndoManager = {
        let manager = UndoManager()
        manager.groupsByEvent = false
        manager.levelsOfUndo = 20
        return manager
    }()
    var depth = 0
    var initial: Snapshot?
    var editingSnapshot: Snapshot?
    var editedItemID: UUID?
    var editsLabel = false
}

extension WorktreeBoard {
    private var historySnapshot: WorktreeHistory.Snapshot {
        .init(items: items.filter { !$0.isSummarizing && $0.definitionFailureTerm == nil && ($0.definingTerm == nil || $0.insight != nil) }.map { item in
            var stable = item
            stable.labelWork = nil
            stable.outputWork = nil
            stable.arrivalTitle = nil
            stable.revealsSummary = false
            return stable
        }, title: customTitle, trash: recentlyDeleted)
    }

    func editingFocusChanged() {
        if let initial = history.editingSnapshot, history.depth == 0,
           let oldIndex = initial.items.firstIndex(where: { $0.id == history.editedItemID }) {
            let old = initial.items[oldIndex]
            var before = historySnapshot
            if let index = before.items.firstIndex(where: { $0.id == old.id }) {
                if history.editsLabel { before.items[index].label = old.label }
                else { before.items[index].text = old.text }
            } else {
                // Clearing a note removes it; undo restores the text from before editing.
                before.items.insert(old, at: min(oldIndex, before.items.count))
            }
            registerHistory(from: before, to: historySnapshot)
        }
        let item = items.first { item in
            editingID == item.labelID || (editingID == item.id && !item.isQuestion && !item.isInsight)
        }
        history.editedItemID = item?.id
        history.editsLabel = item?.labelID == editingID
        history.editingSnapshot = item == nil ? nil : historySnapshot
    }

    /// One user action may include nested edits or many pointer updates.
    func beginHistoryAction() {
        if history.depth == 0 {
            editingFocusChanged()
            history.initial = historySnapshot
        }
        history.depth += 1
    }

    func endHistoryAction() {
        guard history.depth > 0 else { return }
        history.depth -= 1
        guard history.depth == 0, let before = history.initial else { return }
        history.initial = nil
        registerHistory(from: before, to: historySnapshot)
    }

    func undo() {
        guard history.depth == 0 else { return }
        editingID = nil
        history.manager.undo()
    }

    func redo() {
        guard history.depth == 0 else { return }
        editingID = nil
        history.manager.redo()
    }

    private func registerHistory(from before: WorktreeHistory.Snapshot, to after: WorktreeHistory.Snapshot) {
        guard before.items != after.items || before.title != after.title || before.trash != after.trash else { return }
        let manager = history.manager
        let needsGroup = !manager.isUndoing && !manager.isRedoing
        if needsGroup { manager.beginUndoGrouping() }
        manager.registerUndo(withTarget: self) { board in
            board.applyHistory(from: after, to: before)
        }
        if needsGroup { manager.endUndoGrouping() }
    }

    private func restoredSession(_ old: MacConversationState) -> MacConversationState {
        guard old.isDeleted else { return old }
        let session = MacConversationState()
        session.savesConversation = false
        session.configure(preview: false)
        session.id = old.id
        session.branches = old.branches
        session.selectedBranch = old.selectedBranch
        session.promotedIDs = old.promotedIDs
        return session
    }

    private func applyHistory(from source: WorktreeHistory.Snapshot, to target: WorktreeHistory.Snapshot) {
        history.editingSnapshot = nil
        let before = historySnapshot
        let sourceIDs = Set(source.items.map(\.id))
        let targetIDs = Set(target.items.map(\.id))
        for id in sourceIDs.subtracting(targetIDs) {
            // Deletion cancels live work; redo restores content without re-submitting a question.
            delete(id, recordsHistory: false)
        }
        restoreTrashHistory(from: source.trash, to: target.trash)
        for (position, desired) in target.items.enumerated() where !permanentlyDeletedIDs.contains(desired.id) {
            guard let previous = source.items.first(where: { $0.id == desired.id }) else {
                var restored = desired
                restored.session = restored.session.map(restoredSession)
                items.insert(restored, at: min(position, items.count))
                continue
            }
            guard let index = items.firstIndex(where: { $0.id == desired.id }) else { continue }
            // Only restore properties changed by the action. A completed answer or definition
            // arriving after a move must survive undoing that move.
            func restore<Value: Equatable>(_ path: WritableKeyPath<Item, Value>) {
                if previous[keyPath: path] != desired[keyPath: path] {
                    items[index][keyPath: path] = desired[keyPath: path]
                }
            }
            restore(\.origin)
            restore(\.size)
            restore(\.photoLayout)
            restore(\.text)
            restore(\.label)
            restore(\.labelRevision)
            restore(\.isHeading)
            restore(\.isHelp)
            restore(\.insight)
            restore(\.image)
            restore(\.sourceID)
            if previous.session != desired.session {
                if let session = items[index].session {
                    session.markDeleted()
                    MacApplicationRuntime.shared.modelTasks.cancelTasks { $0.conversationID == session.id }
                }
                items[index].session = desired.session.map(restoredSession)
            }
        }
        if source.title != target.title { customTitle = target.title }
        editingID = nil
        selection.removeAll { id in !items.contains { $0.id == id } }
        closeCommand(animated: false)
        // Register the actual inverse, preserving edits and model results made since the action.
        registerHistory(from: before, to: historySnapshot)
    }
}
