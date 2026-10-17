import Testing
@testable import Angrove_iOS

@Suite("Insight notification navigation")
@MainActor
struct InsightNotificationNavigationTests {
    private func request(_ title: String) -> ConversationDefinitionRequest {
        ConversationDefinitionRequest(
            conversationID: nil,
            word: ConversationInsightWord(text: title, sourceResponseBlock: "Original answer"),
            definition: ConceptDefinition(word: title, partOfSpeech: "noun", pronunciation: "",
                                          meaning: "A completed contextual definition", example: "")
        )
    }

    @Test func notificationOpensInRecreatedPageAfterOriginalCacheIsReset() throws {
        let originalPage = ConversationDefinitionState()
        let completed = request("Prudence")
        originalPage.presentCompletedDefinition(completed)
        let center = ModelCompletionNotificationCenter()
        var pending: ConversationDefinitionRequest?
        center.post(title: completed.definition.word, kind: .insightDefinition,
                    postsSystemNotification: false) { pending = completed }
        originalPage.reset()
        center.open(id: try #require(center.notifications.first).id)
        let recreatedPage = ConversationDefinitionState()
        recreatedPage.presentCompletedDefinition(try #require(pending))
        #expect(recreatedPage.activeWord == completed.word)
        #expect(recreatedPage.definitionsByKey[completed.word.id] == completed.definition)
        #expect(originalPage.activeWord == nil)
        #expect(center.notifications.isEmpty)
    }

    @Test func notificationReplacesAlreadyOpenCard() {
        let page = ConversationDefinitionState()
        page.presentCompletedDefinition(request("Prudence"))
        let next = request("Temperance")
        page.presentCompletedDefinition(next)
        #expect(page.activeWord == next.word)
        #expect(page.definitionsByKey[next.word.id] == next.definition)
        #expect(page.completedWords.isEmpty)
    }
}
