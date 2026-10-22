import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Global Search")
struct GlobalSearchTests {
    @Test("All scope finds every kind, ranking an exact title above titles that start with the query")
    func allScopeSearchesEveryKind() {
        let results = search("virtue", scope: .all)
        #expect(results.map(\.kind) == [.insight, .conversation, .studyTopic])
        #expect(results.map(\.text) == ["Virtue", "Virtue Ethics in Practice", "Virtue Ethics"])
    }

    @Test("Word-start matches rank above mid-word matches, and passages rank last")
    func ranking() {
        let title = { (text: String) in
            GlobalSearchResult(id: UUID(), kind: .insight, text: text, isPassage: false,
                               matches: GlobalSearch.ranges(of: "act", in: text))
        }
        #expect(GlobalSearch.rank(title("act")) == 0)
        #expect(GlobalSearch.rank(title("Acts of Faith")) == 1)
        #expect(GlobalSearch.rank(title("Moral act")) == 2)
        #expect(GlobalSearch.rank(title("Exactness")) == 3)
        let passage = GlobalSearchResult(id: UUID(), kind: .conversation, text: "act", isPassage: true,
                                         matches: GlobalSearch.ranges(of: "act", in: "act"))
        #expect(GlobalSearch.rank(passage) == 4)
    }

    @Test("A scope limits results to its kind")
    func scopeFilters() {
        #expect(search("virtue", scope: .insights).map(\.kind) == [.insight])
        #expect(search("virtue", scope: .studyTopics).map(\.kind) == [.studyTopic])
        #expect(search("virtue", scope: .conversations).map(\.kind) == [.conversation])
    }

    @Test("An empty query shows no results")
    func emptyQuery() {
        #expect(search("   ", scope: .all).isEmpty)
    }

    @Test("A conversation matched in its messages shows the passage around the match")
    func messagePassage() throws {
        let result = try #require(search("wrong reason", scope: .conversations).first)
        #expect(result.isPassage)
        #expect(result.text.hasPrefix("…"))
        let match = try #require(result.matches.first)
        #expect(result.text[match] == "wrong reason")
    }

    @Test("Every occurrence is reported for highlighting, ignoring diacritics")
    func allOccurrences() {
        let ranges = GlobalSearch.ranges(of: "cafe", in: "Café and CAFE")
        #expect(ranges.count == 2)
    }

    @Test("Study topic containers are not listed as conversations")
    func studyTopicContainersExcluded() {
        let container = InquiryConversation(title: "Virtue container", isStudyTopic: true)
        let results = GlobalSearch.results(for: "virtue", scope: .conversations,
                                           conversations: [container], insights: [], studyTopics: [])
        #expect(results.isEmpty)
    }

    private func search(_ query: String, scope: GlobalSearchScope) -> [GlobalSearchResult] {
        var branch = ChatBranch(startingConcept: nil)
        branch.activeChatBlocks = [
            .user("What makes an action good? Can someone do the right thing for the wrong reason?", nil, [])
        ]
        let titled = InquiryConversation(title: "Virtue Ethics in Practice")
        let byMessage = InquiryConversation(title: "Intention", branches: [branch])
        let insight = ConceptDefinition(word: "Virtue", partOfSpeech: "noun", pronunciation: "", meaning: "", example: "")
        return GlobalSearch.results(
            for: query,
            scope: scope,
            conversations: [titled, byMessage],
            insights: [insight],
            studyTopics: [StudyTopic(title: "Virtue Ethics"), StudyTopic(title: "Grace")]
        )
    }
}
