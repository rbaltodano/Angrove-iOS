import AppKit
import Foundation
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor @Suite(.serialized)
struct MacWorktreeBoardTests {
    @Test func defineOnASelectedWindowMakesAnInsightCard() async throws {
        let runtime = MacApplicationRuntime(testModel: WorktreeTestModel(), queue: ModelTaskQueue())
        let board = WorktreeBoard()
        let session = MacConversationState()
        session.savesConversation = false
        session.configure(preview: true)
        var window = WorktreeBoard.Item(origin: .zero)
        window.session = session
        board.items.append(window)
        board.itemSizes[window.id] = CGSize(width: 400, height: 300)

        board.select(window.id)
        #expect(board.openCommand())
        board.commandText = "/define grace"
        board.submitCommand(runtime: runtime)

        #expect(!board.isCommandOpen)
        let card = try #require(board.items.first { $0.definingTerm == "grace" || $0.insight?.word == "grace" })
        try await wait { board.items.first { $0.id == card.id }?.insight != nil }
        #expect(board.items.first { $0.id == card.id }?.insight?.word == "grace")
    }

    @Test func defineWithNothingSelectedIsStruck() {
        let runtime = MacApplicationRuntime(testModel: WorktreeTestModel(), queue: ModelTaskQueue())
        let board = WorktreeBoard()
        #expect(board.openCommand(freeOrigin: .zero))
        board.commandText = "/define"
        board.submitCommand(runtime: runtime)
        #expect(board.isCommandStruck)
        #expect(board.items.isEmpty)
    }

    @Test func savedBoardRestoresItsItemsAndConversations() {
        let board = WorktreeBoard()
        board.customTitle = "Patristics"
        var note = WorktreeBoard.Item(origin: CGPoint(x: 10, y: 20), text: "A note")
        note.label = "Label"
        var heading = WorktreeBoard.Item(origin: CGPoint(x: 0, y: -80), text: "Heading")
        heading.isHeading = true
        let session = MacConversationState()
        session.savesConversation = false
        session.configure(preview: true)
        var branch = ChatBranch(startingConcept: nil)
        branch.topQuestionText = "Who was Ignatius?"
        branch.topQuestionSubmitted = true
        branch.activeChatBlocks = [.text("A bishop of Antioch.")]
        session.branches = [branch]
        session.selectedBranch = branch.id
        var window = WorktreeBoard.Item(origin: CGPoint(x: 300, y: 0))
        window.session = session
        window.size = CGSize(width: 400, height: 300)
        var pending = WorktreeBoard.Item(origin: .zero)
        pending.isSummarizing = true
        board.items = [note, heading, window, pending]

        let document = board.document(createdAt: Date())
        #expect(document.items.count == 3)
        let restored = WorktreeBoard(document: document)
        #expect(restored.customTitle == "Patristics")
        #expect(restored.items.map(\.id) == [note.id, heading.id, window.id])
        #expect(restored.items[0].label == "Label")
        #expect(restored.items[1].isHeading)
        #expect(restored.items[2].session?.transcript.count == 2)
        #expect(restored.items[2].session?.savesConversation == false)
        #expect(restored.items[2].size == CGSize(width: 400, height: 300))
        #expect(restored.document(createdAt: document.createdAt).items == document.items)
    }

    @Test func typingInTheCommandFieldAndPressingReturnRunsIt() async throws {
        let runtime = MacApplicationRuntime(testModel: WorktreeTestModel(), queue: ModelTaskQueue())
        let board = WorktreeBoard()
        let session = MacConversationState()
        session.savesConversation = false
        session.configure(preview: true)
        var window = WorktreeBoard.Item(origin: .zero)
        window.session = session
        board.items.append(window)
        board.itemSizes[window.id] = CGSize(width: 400, height: 300)
        board.select(window.id)
        #expect(board.openCommand())

        let host = NSHostingView(rootView: WorktreeCommandField(board: board, runtime: runtime))
        let nsWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 200),
                                styleMask: [.titled], backing: .buffered, defer: false)
        nsWindow.isReleasedWhenClosed = false
        nsWindow.contentView = host
        defer { nsWindow.contentView = nil; nsWindow.close() }
        host.layoutSubtreeIfNeeded()
        try await wait { (nsWindow.firstResponder as? NSTextView) != nil }
        let editor = try #require(nsWindow.firstResponder as? NSTextView)
        editor.insertText("define grace", replacementRange: editor.selectedRange())
        #expect(board.commandText == "/define grace")
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        try await wait { board.items.contains { $0.insight?.word == "grace" } }
    }

    @Test func renameWithNothingSelectedNamesTheWorktree() async throws {
        let runtime = MacApplicationRuntime(testModel: WorktreeTestModel(), queue: ModelTaskQueue())
        let board = WorktreeBoard()
        board.items.append(WorktreeBoard.Item(origin: .zero, text: "Notes on grace"))
        #expect(board.openCommand(freeOrigin: .zero))
        board.commandText = "/rename"
        board.submitCommand(runtime: runtime)
        try await wait { board.customTitle == "Generated Title" }
        board.select(nil)
        #expect(board.openCommand(freeOrigin: .zero))
        board.commandText = "/rename Patristics"
        board.submitCommand(runtime: runtime)
        #expect(board.customTitle == "Patristics")
    }

    /// Real key events through the whole canvas: "/" with a window selected, then the command.
    @Test func keyEventsOpenAndRunACommandOnTheSelection() async throws {
        let runtime = MacApplicationRuntime(testModel: WorktreeTestModel(), queue: ModelTaskQueue())
        let board = WorktreeBoard()
        let session = MacConversationState()
        session.savesConversation = false
        session.configure(preview: true)
        var window = WorktreeBoard.Item(origin: .zero)
        window.session = session
        board.items.append(window)
        let host = NSHostingView(rootView: MacWorktreeView(board: board, queuePopup: ModelTasksPopupState(), runtime: runtime))
        let nsWindow = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 700),
                                styleMask: [.titled], backing: .buffered, defer: false)
        nsWindow.isReleasedWhenClosed = false
        nsWindow.contentView = host
        nsWindow.makeKeyAndOrderFront(nil)
        defer { nsWindow.contentView = nil; nsWindow.close() }
        try await wait { board.itemSizes[window.id] != nil }
        board.select(window.id)
        try await Task.sleep(for: .milliseconds(50))

        post("/", keyCode: 44, to: nsWindow)
        try await wait { board.isCommandOpen }
        for character in "define grace" { post(String(character), keyCode: 0, to: nsWindow) }
        try await wait { board.commandText == "/define grace" }
        post("\r", keyCode: 36, to: nsWindow)
        try await Task.sleep(for: .milliseconds(300))
        try await wait { board.items.contains { $0.insight?.word == "grace" } }
        #expect(board.items.filter { !$0.isQuestion && $0.insight == nil }.isEmpty, "no stray text items")
    }

    /// A fast typist: every key queued before any is handled.
    @Test func fastTypedCommandStillRuns() async throws {
        let runtime = MacApplicationRuntime(testModel: WorktreeTestModel(), queue: ModelTaskQueue())
        let board = WorktreeBoard()
        let session = MacConversationState()
        session.savesConversation = false
        session.configure(preview: true)
        var window = WorktreeBoard.Item(origin: .zero)
        window.session = session
        board.items.append(window)
        let host = NSHostingView(rootView: MacWorktreeView(board: board, queuePopup: ModelTasksPopupState(), runtime: runtime))
        let nsWindow = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 700),
                                styleMask: [.titled], backing: .buffered, defer: false)
        nsWindow.isReleasedWhenClosed = false
        nsWindow.contentView = host
        nsWindow.makeKeyAndOrderFront(nil)
        defer { nsWindow.contentView = nil; nsWindow.close() }
        try await wait { board.itemSizes[window.id] != nil }
        board.select(window.id)
        try await Task.sleep(for: .milliseconds(50))
        for character in "/define grace" { post(String(character), keyCode: character == "/" ? 44 : 0, to: nsWindow) }
        post("\r", keyCode: 36, to: nsWindow)
        try await Task.sleep(for: .milliseconds(500))
        try await wait { board.items.contains { $0.insight?.word == "grace" } }
    }

    @Test func draggingNearAnotherItemSnapsAndShowsAGuide() {
        let board = WorktreeBoard()
        let fixed = WorktreeBoard.Item(origin: CGPoint(x: 100, y: 100), text: "Fixed")
        let moving = WorktreeBoard.Item(origin: CGPoint(x: 300, y: 400), text: "Moving")
        board.items = [fixed, moving]
        board.itemSizes[fixed.id] = CGSize(width: 200, height: 40)
        board.itemSizes[moving.id] = CGSize(width: 120, height: 40)

        // Left edges 5pt apart: snaps flush and shows one vertical guide reaching past both.
        board.move(moving.id, to: CGPoint(x: 105, y: 400), threshold: 8, overhang: 84)
        #expect(board.items[1].origin.x == 100)
        let guide = board.guides.first
        #expect(board.guides.count == 1)
        #expect(guide?.axis == .vertical)
        #expect(guide?.start == CGFloat(92 - 84))
        #expect(guide?.end == CGFloat(392 + 40 + 84))

        // Out of range: moves freely with no guides; release clears them.
        board.move(moving.id, to: CGPoint(x: 160, y: 400), threshold: 8, overhang: 84)
        #expect(board.items[1].origin.x == 160)
        #expect(board.guides.isEmpty)
        board.endMove()
        #expect(board.guides.isEmpty)
    }

    @Test func hoveringIsEnoughAndSelectionTakesSeveral() {
        let runtime = MacApplicationRuntime(testModel: WorktreeTestModel(), queue: ModelTaskQueue())
        let board = WorktreeBoard()
        let first = WorktreeBoard.Item(origin: .zero, text: "First")
        let second = WorktreeBoard.Item(origin: CGPoint(x: 0, y: 100), text: "Second")
        board.items = [first, second]
        board.itemSizes[first.id] = CGSize(width: 100, height: 40)
        board.itemSizes[second.id] = CGSize(width: 100, height: 40)

        // Hovered, nothing selected: the command acts on the hovered item.
        board.setHovered(first.id, true)
        #expect(board.openCommand(freeOrigin: .zero))
        #expect(board.commandTargets == [first.id])
        board.commandText = "/rename Hovered"
        board.submitCommand(runtime: runtime)
        #expect(board.items[0].label == "Hovered")

        // Two selected (the second by ⇧-click): /rename names both, and selection wins over hover.
        board.select(first.id)
        board.toggleSelection(second.id)
        #expect(board.selection == [first.id, second.id])
        #expect(board.openCommand(freeOrigin: .zero))
        #expect(board.commandTargets == [first.id, second.id])
        board.commandText = "/rename Both"
        board.submitCommand(runtime: runtime)
        #expect(board.items.map(\.label) == ["Both", "Both"])

        // Nothing hovered or selected: the Worktree itself.
        board.select(nil)
        board.setHovered(first.id, false)
        #expect(board.openCommand(freeOrigin: .zero))
        #expect(board.commandTargets.isEmpty)
    }

    @Test func explicitDefineWorksWithoutSelectionAndBareDefineUsesNote() async throws {
        let runtime = MacApplicationRuntime(testModel: WorktreeTestModel(), queue: ModelTaskQueue())
        let board = WorktreeBoard()
        #expect(board.openCommand(freeOrigin: .zero))
        board.commandText = "/define grace"
        board.submitCommand(runtime: runtime)
        #expect(!board.isCommandStruck)
        try await wait { board.items.contains { $0.insight?.word == "grace" } }
        let note = board.addText(at: .zero, text: "Charity")
        board.endEditing()
        board.select(note)
        #expect(board.openCommand())
        board.commandText = "/define"
        board.submitCommand(runtime: runtime)
        try await wait { board.items.contains { $0.insight?.word == "Charity" } }
    }

    @Test func insightNeedsAnExplicitDefineTermAndHeadingCannotBeHeadedAgain() {
        let runtime = MacApplicationRuntime(testModel: WorktreeTestModel(), queue: ModelTaskQueue())
        let board = WorktreeBoard()
        var insight = WorktreeBoard.Item(origin: .zero)
        insight.insight = ConceptDefinition(word: "Grace", partOfSpeech: "", pronunciation: "", meaning: "A gift.", example: "")
        var heading = WorktreeBoard.Item(origin: .zero, text: "Patristics")
        heading.isHeading = true
        board.items = [insight, heading]
        #expect(!board.canRun(.define(nil), on: [insight.id]))
        #expect(board.canRun(.define("charity"), on: [insight.id]))
        #expect(!board.canRun(.heading(nil), on: [heading.id]))
        #expect(!board.canRun(.heading("Other"), on: [heading.id]))
        board.select(insight.id)
        #expect(board.openCommand())
        board.commandText = "/define"
        board.submitCommand(runtime: runtime)
        #expect(board.isCommandStruck)
    }

    @Test func hoveredPhotoOverridesAnUnrelatedSelectionAndSupportsCommands() async throws {
        let runtime = MacApplicationRuntime(testModel: WorktreeTestModel(), queue: ModelTaskQueue())
        let board = WorktreeBoard()
        let note = board.addText(at: .zero, text: "Unrelated")
        board.endEditing()
        let file = UploadedFile(name: "Photo", imageData: Data([0]), rotationDegrees: 0)
        board.placePhoto(file, size: CGSize(width: 500, height: 400), at: .zero)
        let photo = try #require(board.items.last)
        board.select(note)
        board.setHovered(photo.id, true)
        #expect(board.openCommand())
        #expect(board.commandTargets == [photo.id])
        board.commandText = "/summarize"
        board.submitCommand(runtime: runtime)
        try await wait { board.items.contains { $0.text == "Photo summary" } }
        #expect(board.openCommand())
        board.commandText = "/define"
        board.submitCommand(runtime: runtime)
        try await wait { board.items.contains { $0.insight?.word == "Generated Title" } }
        #expect(board.openCommand())
        board.commandText = "/heading"
        board.submitCommand(runtime: runtime)
        try await wait { board.items.contains { $0.isHeading && $0.text == "Generated Title" } }
    }

    @Test func oldInvalidCommandCannotDismissANewField() async throws {
        let runtime = MacApplicationRuntime(testModel: WorktreeTestModel(), queue: ModelTaskQueue())
        let board = WorktreeBoard()
        #expect(board.openCommand(freeOrigin: .zero))
        board.commandText = "/define"
        board.submitCommand(runtime: runtime)
        #expect(board.isCommandStruck)
        board.closeCommand()
        #expect(board.openCommand(freeOrigin: .zero))
        board.commandText = "/define grace"
        try await Task.sleep(for: .milliseconds(700))
        #expect(board.isCommandOpen)
        board.submitCommand(runtime: runtime)
        try await wait { board.items.contains { $0.insight?.word == "grace" } }
    }

    @Test func selectionTaskMessageRetainsImagesAndRejectsTextOnlyEngine() throws {
        let bytes = Data([0, 1, 2])
        let file = UploadedFile(name: "Photo", imageData: bytes, rotationDegrees: 0)
        let context = ConversationContext(transcript: [.user("Selected photo", [], [file])])
        let message = try LiteRTAngroveModel.selectionTaskMessage("Summarize", context: context, supportsVision: true)
        #expect(message.contents.contains { if case .imageData(let data) = $0 { return data == bytes }; return false })
        #expect(throws: LiteRTAngroveModel.SelectionImageError.self) {
            try LiteRTAngroveModel.selectionTaskMessage("Summarize", context: context, supportsVision: false)
        }
    }

    @Test func slashTargetsHoveredImageWhileAnotherTextEditorHasFocus() async throws {
        let runtime = MacApplicationRuntime(testModel: WorktreeTestModel(), queue: ModelTaskQueue())
        let board = WorktreeBoard()
        let note = board.addText(at: CGPoint(x: -300, y: 0), text: "A note")
        let file = UploadedFile(name: "Photo", imageData: Data([0]), rotationDegrees: 0)
        board.placePhoto(file, size: CGSize(width: 200, height: 200), at: .zero)
        let photo = try #require(board.items.last)
        let host = NSHostingView(rootView: MacWorktreeView(board: board, queuePopup: ModelTasksPopupState(), runtime: runtime))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        board.editingID = note
        try await wait { window.firstResponder is NSTextView }
        board.select(nil)
        board.setHovered(photo.id, true)
        post("/", keyCode: 44, to: window)
        try await wait { board.isCommandOpen }
        #expect(board.commandTargets == [photo.id])
        for character in "define grace" { post(String(character), keyCode: 0, to: window) }
        try await wait { board.commandText == "/define grace" }
        post("\r", keyCode: 36, to: window)
        try await wait { board.items.contains { $0.insight?.word == "grace" } }
        #expect(!board.isCommandStruck)
    }

    @Test func toolShortcutsPreferTheSelectionOverTheHoveredItem() {
        let board = WorktreeBoard()
        let first = WorktreeBoard.Item(origin: .zero, text: "First")
        let second = WorktreeBoard.Item(origin: CGPoint(x: 400, y: 0), text: "Second")
        board.items = [first, second]
        board.setHovered(second.id, true)
        #expect(board.shortcutTargets == [second.id])
        board.select(first.id)
        #expect(board.shortcutTargets == [first.id])
        // "/" still follows the pointer.
        #expect(board.commandSelection == [second.id])
    }

    @Test func toolShortcutWithATargetTypesAndRunsItsCommand() async throws {
        let runtime = MacApplicationRuntime(testModel: WorktreeTestModel(), queue: ModelTaskQueue())
        let board = WorktreeBoard()
        let note = WorktreeBoard.Item(origin: .zero, text: "Grace perfects nature.")
        board.items = [note]
        board.itemSizes[note.id] = CGSize(width: 200, height: 44)
        board.runTool(.heading, on: [note.id], freeOrigin: .zero, runtime: runtime)
        #expect(board.commandText == "/heading")
        #expect(board.commandTargets == [note.id])
        try await wait { !board.isCommandOpen }
        #expect(board.items.contains { $0.isHeading })
    }

    @Test func toolShortcutWithNothingToActOnWaitsForInput() async throws {
        let runtime = MacApplicationRuntime(testModel: WorktreeTestModel(), queue: ModelTaskQueue())
        let board = WorktreeBoard()
        board.runTool(.define, on: [], freeOrigin: CGPoint(x: 10, y: 20), runtime: runtime)
        #expect(board.commandText == "/define ")
        #expect(board.commandOrigin == CGPoint(x: 10, y: 20))
        try await Task.sleep(for: .milliseconds(400))
        #expect(board.isCommandOpen)
        #expect(!board.isCommandStruck)
    }

    @Test func fileCommandAsksThePageForTheFileBrowser() {
        let runtime = MacApplicationRuntime(testModel: WorktreeTestModel(), queue: ModelTaskQueue())
        let board = WorktreeBoard()
        #expect(board.openCommand(freeOrigin: .zero))
        board.commandText = "/f"
        board.submitCommand(runtime: runtime)
        #expect(board.fileRequest == 1)
        #expect(!board.isCommandOpen)
    }

    @Test func clickedItemIsFoundByItsFrameAndEmptyHeadingsGoAway() {
        let board = WorktreeBoard()
        let note = WorktreeBoard.Item(origin: CGPoint(x: 100, y: 100), text: "Note")
        board.items = [note]
        board.itemSizes[note.id] = CGSize(width: 120, height: 44)
        #expect(board.item(at: CGPoint(x: 150, y: 110)) == note.id)
        #expect(board.item(at: CGPoint(x: 400, y: 400)) == nil)
        board.addHeadingField(at: CGPoint(x: 0, y: 300))
        let heading = try? #require(board.items.last)
        #expect(heading?.isHeading == true)
        #expect(board.editingID == heading?.id)
        board.endEditing()
        #expect(!board.items.contains { $0.isHeading })
    }

    private func post(_ characters: String, keyCode: UInt16, to window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode) else { continue }
            NSApp.postEvent(event, atStart: false)
        }
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }
}

private struct WorktreeTestModel: AngroveModel {
    func respond(to context: ConversationContext) async -> ModelResponse { ModelResponse(text: "Answer") }
    func respond(to context: ConversationContext, thinkingEnabled: Bool,
                 onUpdate: @escaping (ModelResponseUpdate) -> Void) async -> ModelResponse { ModelResponse(text: "Answer") }
    func compact(_ context: ConversationContext) async -> String { "" }
    func summarize(_ context: ConversationContext) async throws -> String {
        context.transcript.contains { block in
            if case .user(_, _, let uploads) = block { return !uploads.isEmpty }
            return false
        } ? "Photo summary" : "Summary"
    }
    func conversationTitle(for initialQuestion: String) async throws -> String { "Generated Title" }
    func defineTerm(_ term: String, in context: ConversationContext) async throws -> ConceptDefinition {
        ConceptDefinition(word: term, partOfSpeech: "", pronunciation: "", meaning: "Test definition.", example: "")
    }
    func labelSubject(forTitles titles: [String]) async throws -> String { throw AngroveModelActionError.unavailable }
    func blendConceptCandidates(_ concepts: [ConceptDefinition], weights: [Double]) async throws -> [ConceptDefinition] { throw AngroveModelActionError.unavailable }
    func generateChildren(for concept: ConceptDefinition) async throws -> [ConceptDefinition] { throw AngroveModelActionError.unavailable }
}
