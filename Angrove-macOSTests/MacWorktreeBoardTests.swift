import Foundation
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
        board.commandText = "/define grace"
        board.submitCommand(runtime: runtime)
        #expect(board.isCommandStruck)
        #expect(board.items.isEmpty)
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
    func defineTerm(_ term: String, in context: ConversationContext) async throws -> ConceptDefinition {
        ConceptDefinition(word: term, partOfSpeech: "", pronunciation: "", meaning: "Test definition.", example: "")
    }
    func labelSubject(forTitles titles: [String]) async throws -> String { throw AngroveModelActionError.unavailable }
    func blendConceptCandidates(_ concepts: [ConceptDefinition], weights: [Double]) async throws -> [ConceptDefinition] { throw AngroveModelActionError.unavailable }
    func generateChildren(for concept: ConceptDefinition) async throws -> [ConceptDefinition] { throw AngroveModelActionError.unavailable }
}
