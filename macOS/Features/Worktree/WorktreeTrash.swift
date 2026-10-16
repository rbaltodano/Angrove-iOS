import Foundation

extension WorktreeBoard {
    func retainInTrash(_ item: Item) {
        guard let stored = Self.stored(item), item.session != nil || item.image != nil || item.insight != nil
            || item.isHelp || !["", "\"", "“"].contains(item.text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        recentlyDeleted.removeAll { $0.id == item.id }
        recentlyDeleted.insert(stored, at: 0)
        trimTrash()
    }

    func trimTrash() {
        for item in recentlyDeleted.dropFirst(10) { permanentlyDeletedIDs.insert(item.id) }
        recentlyDeleted = Array(recentlyDeleted.prefix(10))
    }

    func emptyTrash() {
        permanentlyDeletedIDs.formUnion(recentlyDeleted.map(\.id))
        recentlyDeleted = []
    }

    @discardableResult
    func restoreFromTrash(_ id: UUID, at origin: CGPoint) -> Bool {
        guard !permanentlyDeletedIDs.contains(id), let stored = recentlyDeleted.first(where: { $0.id == id }),
              !items.contains(where: { $0.id == id }) else { return false }
        beginHistoryAction()
        defer { endHistoryAction() }
        recentlyDeleted.removeAll { $0.id == id }
        var item = Self.restore(stored)
        item.origin = origin
        items.append(item)
        select(id)
        Task { @MainActor [self] in await Task.yield(); pulse(id) }
        return true
    }

    /// Change only entries affected by this undo step; permanently purged IDs stay gone.
    func restoreTrashHistory(from source: [WorktreeStoredItem], to target: [WorktreeStoredItem]) {
        let changed = Set(source.map(\.id)).symmetricDifference(Set(target.map(\.id)))
        recentlyDeleted.removeAll { changed.contains($0.id) || permanentlyDeletedIDs.contains($0.id) }
        for (index, item) in target.enumerated() where changed.contains(item.id) && !permanentlyDeletedIDs.contains(item.id) {
            recentlyDeleted.insert(item, at: min(index, recentlyDeleted.count))
        }
        trimTrash()
    }
}

enum WorktreeTrashDrop {
    static func payload(_ id: UUID, boardID: UUID) -> String { "angrove-worktree-trash:\(boardID):\(id)" }
    static func itemID(in payload: String, boardID: UUID) -> UUID? {
        let prefix = "angrove-worktree-trash:\(boardID):"
        guard payload.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(payload.dropFirst(prefix.count)))
    }
}
