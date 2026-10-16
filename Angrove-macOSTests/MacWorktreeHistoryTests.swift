import AppKit
import SwiftUI
import Foundation
import Testing
@testable import AngroveMac

@MainActor @Suite(.serialized)
struct MacWorktreeHistoryTests {
    @Test func viewportSurvivesEncodingAndOlderDocumentsStillOpen() throws {
        let board = WorktreeBoard()
        board.viewport = WorktreeViewport(scale: 1.7, offset: CGSize(width: -720, height: 430))
        let document = board.document(createdAt: Date())
        let encoded = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(WorktreeDocument.self, from: encoded)
        #expect(WorktreeBoard(document: decoded).viewport == board.viewport)
        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "viewport")
        let old = try JSONDecoder().decode(WorktreeDocument.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(WorktreeBoard(document: old).viewport == WorktreeViewport())
    }

    @Test func undoKeepsTwentyActionsAndNewActionsDiscardRedo() {
        let board = WorktreeBoard()
        for index in 0..<25 { board.addText(at: .zero, text: "Note \(index)"); board.endEditing() }
        for _ in 0..<25 { board.undo() }
        #expect(board.items.count == 5)
        for _ in 0..<20 { board.redo() }
        #expect(board.items.count == 25)
        board.undo()
        board.addText(at: .zero, text: "Different note")
        board.endEditing()
        board.redo()
        #expect(board.items.count == 25)
        #expect(board.items.last?.text == "Different note")
    }

    @Test func aWholeDragIsOneActionAndPreservesLaterContent() {
        let board = WorktreeBoard()
        let id = board.addText(at: .zero, text: "Initial")
        board.endEditing()
        board.beginHistoryAction()
        for index in 1...100 { board.update(id) { $0.origin.x = CGFloat(index) } }
        board.endHistoryAction()
        board.update(id) { $0.text = "A result that arrived after moving" }
        board.undo()
        #expect(board.items.first?.origin == .zero)
        #expect(board.items.first?.text == "A result that arrived after moving")
        board.redo()
        #expect(board.items.first?.origin.x == 100)
        #expect(board.items.first?.text == "A result that arrived after moving")
        board.undo()
        board.undo()
        #expect(board.items.isEmpty)
    }

    @Test func deletionRestoresLatestTextAndCanBeRedone() {
        let board = WorktreeBoard()
        let id = board.addText(at: CGPoint(x: 42, y: 90), text: "Initial")
        board.update(id) { $0.text = "Finished note" }
        board.endEditing()
        board.delete(id)
        board.undo()
        #expect(board.items.first?.id == id)
        #expect(board.items.first?.text == "Finished note")
        #expect(board.items.first?.origin == CGPoint(x: 42, y: 90))
        board.redo()
        #expect(board.items.isEmpty)
    }

    @Test func resizeAndRenameCanBeUndoneTogetherWithoutMovingCamera() {
        let board = WorktreeBoard()
        let id = board.addText(at: .zero, text: "Note")
        board.endEditing()
        board.beginHistoryAction()
        board.update(id) { $0.size = CGSize(width: 500, height: 400); $0.label = "Renamed" }
        board.customTitle = "Board title"
        board.endHistoryAction()
        board.viewport = WorktreeViewport(scale: 2, offset: CGSize(width: 500, height: -300))
        board.undo()
        #expect(board.items.first?.size == nil)
        #expect(board.items.first?.label == nil)
        #expect(board.customTitle == nil)
        #expect(board.viewport.scale == 2)
        board.redo()
        #expect(board.items.first?.size == CGSize(width: 500, height: 400))
        #expect(board.customTitle == "Board title")
    }

    @Test func finishedTextEditingIsUndoableFromCanvas() {
        let board = WorktreeBoard()
        let id = board.addText(at: .zero, text: "Original")
        board.endEditing()
        board.editingID = id
        board.binding(id, \.text).wrappedValue = "Edited"
        board.endEditing()
        board.undo()
        #expect(board.items.first?.text == "Original")
        board.redo()
        #expect(board.items.first?.text == "Edited")
    }

    @Test func restoredConversationIsUsableAndRetainsTranscript() {
        let board = WorktreeBoard()
        let session = MacConversationState()
        session.savesConversation = false
        session.configure(preview: true)
        var branch = ChatBranch(startingConcept: nil)
        branch.topQuestionText = "What is grace?"
        branch.topQuestionSubmitted = true
        branch.activeChatBlocks = [.text("A gift.")]
        session.branches = [branch]
        session.selectedBranch = branch.id
        var item = WorktreeBoard.Item(origin: .zero)
        item.session = session
        board.items = [item]
        board.delete(item.id)
        #expect(session.isDeleted)
        board.undo()
        #expect(board.items.first?.session?.isDeleted == false)
        #expect(board.items.first?.session?.transcript.count == 2)
        #expect(board.items.first?.session?.savesConversation == false)
        board.redo()
        #expect(board.items.isEmpty)
    }

    @Test func clearingANoteCanBeUndoneAsOneAction() {
        let board = WorktreeBoard()
        let id = board.addText(at: .zero, text: "Keep this note")
        board.endEditing()
        board.editingID = id
        board.binding(id, \.text).wrappedValue = ""
        board.endEditing()
        #expect(board.items.isEmpty)
        board.undo()
        #expect(board.items.first?.text == "Keep this note")
        board.redo()
        #expect(board.items.isEmpty)
    }

    @Test func keyboardShortcutsUndoAndRedoCanvasActions() async throws {
        let runtime = MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue())
        let board = WorktreeBoard()
        let host = NSHostingView(rootView: MacWorktreeView(board: board, queuePopup: ModelTasksPopupState(), runtime: runtime))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        board.addHelp(at: .zero)
        try await Task.sleep(for: .milliseconds(100))
        for flags: NSEvent.ModifierFlags in [.command, [.command, .shift]] {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: flags.contains(.shift) ? "Z" : "z", charactersIgnoringModifiers: "z",
                isARepeat: false, keyCode: 6))
            NSApp.postEvent(event, atStart: false)
            try await Task.sleep(for: .milliseconds(100))
            #expect(board.items.count == (flags.contains(.shift) ? 1 : 0))
        }
    }

    @Test func photosFitLandscapePortraitAndRotatedBounds() {
        #expect(WorktreePhotoGeometry.fitted(CGSize(width: 4000, height: 2000), rotation: 0, maximum: 1000)
            == CGSize(width: 1000, height: 500))
        #expect(WorktreePhotoGeometry.fitted(CGSize(width: 2000, height: 4000), rotation: 0, maximum: 1000)
            == CGSize(width: 500, height: 1000))
        let rotated = WorktreePhotoGeometry.fitted(CGSize(width: 4000, height: 2000), rotation: 90, maximum: 1000)
        #expect(abs(rotated.width - 500) < 0.001)
        #expect(abs(rotated.height - 1000) < 0.001)
        #expect(WorktreePhotoGeometry.fitted(CGSize(width: 200, height: 100), rotation: 0, maximum: 1000)
            == CGSize(width: 200, height: 100))
    }

    @Test func placingPhotoPulsesAtItsCentreAndIsUndoable() throws {
        let board = WorktreeBoard()
        let file = UploadedFile(name: "Photo", imageData: Data([0]), rotationDegrees: 0)
        board.placePhoto(file, size: CGSize(width: 1000, height: 500), at: CGPoint(x: 100, y: 200))
        let item = try #require(board.items.first)
        #expect(item.image == file)
        #expect(item.size == CGSize(width: 1000, height: 500))
        #expect(board.ripples.count == 1)
        #expect(board.ripples.first?.worldOrigin == CGPoint(x: 600, y: -450))
        let saved = board.document(createdAt: Date())
        #expect(WorktreeBoard(document: saved).items.first?.size == item.size)
        board.undo()
        #expect(board.items.isEmpty)
        board.redo()
        #expect(board.items.first?.image == file)
        #expect(board.items.first?.origin == CGPoint(x: 100, y: 200))
    }

    private var photoFrame: WorktreePhotoFrame {
        WorktreePhotoFrame(origin: CGPoint(x: 100, y: 200), size: CGSize(width: 1000, height: 500),
                           layout: WorktreePhotoLayout(contentSize: CGSize(width: 1000, height: 500)))
    }

    @Test func photoEdgesUseCenteredFillAndSnapWithin16ScreenPoints() {
        let start = photoFrame
        let cropped = WorktreePhotoResize.frame(from: start, handle: .left,
            translation: CGSize(width: 100, height: 0), zoom: 1)
        #expect(cropped.size == CGSize(width: 900, height: 500))
        #expect(cropped.origin == CGPoint(x: 200, y: 200))
        #expect(cropped.layout.offset == CGPoint(x: -50, y: 0))
        #expect(cropped.layout.contentSize == start.layout.contentSize)
        let snapped = WorktreePhotoResize.frame(from: cropped, handle: .left,
            translation: CGSize(width: -84, height: 0), zoom: 1)
        #expect(snapped == start)
        let zoomed = WorktreePhotoResize.frame(from: start, handle: .right,
            translation: CGSize(width: -17, height: 0), zoom: 0.5)
        #expect(zoomed.size.width == 966)
        let zoomedSnap = WorktreePhotoResize.frame(from: start, handle: .right,
            translation: CGSize(width: -16, height: 0), zoom: 0.5)
        #expect(zoomedSnap == start)
    }

    @Test func verticalCropSnapsAndExpandedFramesRemainFilled() {
        let start = photoFrame
        let cropped = WorktreePhotoResize.frame(from: start, handle: .top,
            translation: CGSize(width: 0, height: 100), zoom: 1)
        #expect(cropped.size.height == 400)
        #expect(cropped.origin.y == 300)
        #expect(cropped.layout.offset.y == -50)
        let snapped = WorktreePhotoResize.frame(from: cropped, handle: .top,
            translation: CGSize(width: 0, height: -84), zoom: 1)
        #expect(snapped == start)
        let expanded = WorktreePhotoResize.frame(from: start, handle: .bottom,
            translation: CGSize(width: 0, height: 500), zoom: 1)
        #expect(expanded.size == CGSize(width: 1000, height: 1000))
        #expect(expanded.layout.contentSize == CGSize(width: 2000, height: 1000))
        #expect(expanded.layout.offset == CGPoint(x: -500, y: 0))
    }

    @Test func cornersScaleCropAndContentsProportionallyWithOppositeCornerFixed() {
        let start = WorktreePhotoResize.frame(from: photoFrame, handle: .left,
            translation: CGSize(width: 100, height: 0), zoom: 1)
        let resized = WorktreePhotoResize.frame(from: start, handle: .topLeft,
            translation: CGSize(width: -90, height: -50), zoom: 1)
        #expect(abs(resized.size.width / resized.size.height - start.size.width / start.size.height) < 0.0001)
        #expect(abs(resized.size.width - 990) < 0.0001)
        #expect(abs(resized.layout.contentSize.width - 1100) < 0.0001)
        #expect(abs(resized.layout.offset.x + 55) < 0.0001)
        #expect(abs(resized.origin.x + resized.size.width - start.origin.x - start.size.width) < 0.0001)
        #expect(abs(resized.origin.y + resized.size.height - start.origin.y - start.size.height) < 0.0001)
    }

    @Test func cropPersistsAndUndoRestoresItWithTheFrame() throws {
        let board = WorktreeBoard()
        let file = UploadedFile(name: "Photo", imageData: Data([0]), rotationDegrees: 4)
        board.placePhoto(file, size: photoFrame.size, at: photoFrame.origin)
        let item = try #require(board.items.first)
        #expect(item.image?.rotationDegrees == 0)
        let cropped = WorktreePhotoResize.frame(from: photoFrame, handle: .left,
            translation: CGSize(width: 150, height: 0), zoom: 1)
        board.beginHistoryAction()
        board.update(item.id) { $0.size = cropped.size; $0.origin = cropped.origin; $0.photoLayout = cropped.layout }
        board.endHistoryAction()
        let document = board.document(createdAt: Date())
        let restored = WorktreeBoard(document: try JSONDecoder().decode(WorktreeDocument.self, from: JSONEncoder().encode(document)))
        #expect(restored.items.first?.photoLayout == cropped.layout)
        board.undo()
        #expect(board.items.first?.size == photoFrame.size)
        #expect(board.items.first?.photoLayout?.offset == .zero)
        board.redo()
        #expect(board.items.first?.photoLayout == cropped.layout)
    }

    @Test func keepBothUsesPrefix() {
        #expect(WorktreeBoard.copyTitle("On Grace") == "(Copy) On Grace")
    }
}
