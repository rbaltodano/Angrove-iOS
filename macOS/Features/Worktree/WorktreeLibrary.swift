import Foundation
import Observation

/// One saved Worktree: its title and the items on its canvas.
struct WorktreeDocument: Codable, Identifiable, Equatable {
    var id = UUID()
    /// Set by `/rename`; otherwise the Worktree is named after its first question.
    var title: String?
    var createdAt = Date()
    var updatedAt = Date()
    var items: [WorktreeStoredItem] = []
    /// Optional for documents saved before viewport persistence.
    var viewport: WorktreeViewport?
    var trash: [WorktreeStoredItem]?

    /// The card title: the chosen name, the first question's automatic title, or a placeholder.
    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        let question = items.lazy.compactMap { $0.branches?.first?.topQuestionText }.first { !$0.isEmpty }
        return question.flatMap(MacConversationState.automaticTitle(for:)) ?? String(localized: "Untitled Board")
    }
}

/// A canvas item as saved. Conversation windows keep their whole conversation; model work still
/// in progress is not saved.
struct WorktreeStoredItem: Codable, Equatable {
    var id: UUID
    var origin: CGPoint
    var text: String
    var size: CGSize?
    var label: String?
    var isHeading: Bool
    /// Optional so Worktrees saved before `/help` still open.
    var isHelp: Bool?
    var image: UploadedFile?
    var insight: ConceptDefinition?
    var sourceID: UUID?
    var sourceConversationID: UUID?
    var sourceTitle: String?
    var visibleTurnLimit: Int?
    var conversationID: UUID?
    var branches: [ChatBranch]?
    var promotedIDs: [UUID]?
    var photoLayout: WorktreePhotoLayout?
}

/// Worktrees live in the same encrypted, file-backed personal store as Insight Tree state.
enum WorktreeStore {
    private static let key = "angrove.worktrees.v1"

    private static var store: InsightTreeLocalStateFileStore? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return InsightTreeLocalStateFileStore(rootDirectory: support
            .appending(path: "Angrove-macOS", directoryHint: .isDirectory)
            .appending(path: "Aquinas/Worktree", directoryHint: .isDirectory))
    }

    static func load() -> [WorktreeDocument] {
        guard let store else { return [] }
        return SerializedPersonalStore.shared.load([WorktreeDocument].self, key: key, store: store) ?? []
    }

    static func save(_ documents: [WorktreeDocument]) {
        guard let store else { return }
        SerializedPersonalStore.shared.save(documents, key: key, store: store)
    }
}

/// The saved Worktrees and the one open on the canvas.
@MainActor @Observable final class WorktreeLibrary {
    private(set) var documents = WorktreeStore.load()
    private(set) var openBoard: WorktreeBoard?

    var sortedDocuments: [WorktreeDocument] { documents.sorted { $0.updatedAt > $1.updatedAt } }

    func create() {
        let document = WorktreeDocument()
        documents.append(document)
        WorktreeStore.save(documents)
        openBoard = WorktreeBoard(document: document)
    }

    func open(_ id: UUID) {
        guard let document = documents.first(where: { $0.id == id }) else { return }
        openBoard = WorktreeBoard(document: document)
    }

    func close() {
        if let openBoard { save(openBoard) }
        openBoard = nil
    }

    func save(_ board: WorktreeBoard) {
        guard let index = documents.firstIndex(where: { $0.id == board.documentID }) else { return }
        var document = board.document(createdAt: documents[index].createdAt)
        guard document.items != documents[index].items || document.title != documents[index].title || document.viewport != documents[index].viewport || document.trash != documents[index].trash else { return }
        document.updatedAt = Date()
        documents[index] = document
        WorktreeStore.save(documents)
    }

    func delete(_ id: UUID) {
        if openBoard?.documentID == id { openBoard = nil }
        documents.removeAll { $0.id == id }
        WorktreeStore.save(documents)
    }
}

/// Camera coordinates relative to the viewport centre, independent of window dimensions.
struct WorktreeViewport: Codable, Equatable {
    var scale: CGFloat = 1
    var offset: CGSize = .zero

    var transform: CanvasScrollTransform {
        guard scale.isFinite, offset.width.isFinite, offset.height.isFinite else {
            return CanvasScrollTransform(scale: 1, offset: .zero)
        }
        return CanvasScrollTransform(scale: min(max(scale, 0.28), 2.6), offset: offset)
    }
}
