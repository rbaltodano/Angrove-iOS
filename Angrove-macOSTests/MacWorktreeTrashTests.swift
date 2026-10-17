import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor @Suite(.serialized)
struct MacWorktreeTrashTests {
    @Test func keepsTenNewestAndOverflowCannotBeRestoredEvenByUndo() {
        let board = WorktreeBoard()
        let notes = (0..<11).map { WorktreeBoard.Item(origin: .zero, text: "Note \($0)") }
        board.items = notes
        for note in notes { board.delete(note.id) }
        #expect(board.recentlyDeleted.map(\.id) == notes.dropFirst().reversed().map(\.id))
        #expect(!board.restoreFromTrash(notes[0].id, at: .zero))
        for _ in 0..<11 { board.undo() }
        #expect(!board.items.contains { $0.id == notes[0].id })
        #expect(board.items.count == 10)
    }

    @Test func restoringRemovesFromTrashAndUndoRedoMoveBetweenBoth() throws {
        let board = WorktreeBoard()
        var photo = WorktreeBoard.Item(origin: .zero)
        photo.image = UploadedFile(name: "Image", imageData: Data([0]), rotationDegrees: 0)
        photo.size = CGSize(width: 800, height: 500)
        photo.photoLayout = WorktreePhotoLayout(contentSize: CGSize(width: 1000, height: 500), offset: CGPoint(x: -100, y: 0))
        board.items = [photo]
        board.delete(photo.id)
        #expect(board.restoreFromTrash(photo.id, at: CGPoint(x: 120, y: 220)))
        #expect(board.recentlyDeleted.isEmpty)
        #expect(board.items.first?.photoLayout == photo.photoLayout)
        #expect(board.items.first?.origin == CGPoint(x: 120, y: 220))
        board.undo()
        #expect(board.items.isEmpty)
        #expect(board.recentlyDeleted.first?.id == photo.id)
        board.redo()
        #expect(board.recentlyDeleted.isEmpty)
        #expect(board.items.first?.id == photo.id)
    }

    @Test func emptyIsPermanentButDoesNotDestroyUndoForUnrelatedItems() {
        let board = WorktreeBoard()
        let original = WorktreeBoard.Item(origin: .zero, text: "Removed")
        board.items = [original]
        board.delete(original.id)
        let other = board.addText(at: .zero, text: "Keep")
        board.endEditing()
        board.emptyTrash()
        #expect(board.recentlyDeleted.isEmpty)
        board.undo()
        #expect(!board.items.contains { $0.id == other })
        board.undo()
        #expect(!board.items.contains { $0.id == original.id })
        #expect(!board.restoreFromTrash(original.id, at: .zero))
    }

    @Test func trashPersistsAndOlderDocumentsStillDecode() throws {
        let board = WorktreeBoard()
        let item = WorktreeBoard.Item(origin: .zero, text: "Saved note")
        board.items = [item]
        board.delete(item.id)
        let encoded = try JSONEncoder().encode(board.document(createdAt: Date()))
        let restored = WorktreeBoard(document: try JSONDecoder().decode(WorktreeDocument.self, from: encoded))
        #expect(restored.recentlyDeleted.first?.text == "Saved note")
        #expect(restored.restoreFromTrash(item.id, at: .zero))
        var old = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        old.removeValue(forKey: "trash")
        let legacy = try JSONDecoder().decode(WorktreeDocument.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(WorktreeBoard(document: legacy).recentlyDeleted.isEmpty)
    }

    @Test func unfinishedModelWorkIsNotRecoverableTrashAndDragPayloadIsBoardScoped() {
        let board = WorktreeBoard()
        var pending = WorktreeBoard.Item(origin: .zero)
        pending.isSummarizing = true
        board.items = [pending]
        board.delete(pending.id)
        #expect(board.recentlyDeleted.isEmpty)
        let payload = WorktreeTrashDrop.payload(pending.id, boardID: board.documentID)
        #expect(WorktreeTrashDrop.itemID(in: payload, boardID: board.documentID) == pending.id)
        #expect(WorktreeTrashDrop.itemID(in: payload, boardID: UUID()) == nil)
    }

    @Test func rendersTrashCardInLightAndDark() throws {
        for dark in [false, true] {
            let board = WorktreeBoard()
            var heading = WorktreeBoard.Item(origin: .zero, text: "the early church")
            heading.isHeading = true
            let note = WorktreeBoard.Item(origin: .zero, text: "A long note that should fill its preview column and trail off with an ellipsis rather than stretching the card beyond its bounds.")
            board.items = [heading, note]
            board.delete(heading.id)
            board.delete(note.id)
            let host = NSHostingView(rootView: WorktreeTrashCard(board: board).padding(24).preferredColorScheme(dark ? .dark : .light))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 548, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: NSTemporaryDirectory() + "angrove-trash-\(dark ? "dark" : "light").png"))
            window.contentView = nil
            window.close()
        }
    }
}
