import Foundation
import Testing
@testable import Aquinas_iOS

@Suite("Launch settings behavior")
struct SettingsBehaviorTests {
    @Test("Home is the explicit default destination")
    func homeDestination() {
        #expect(
            AppStartupPolicy.resolve(
                preference: .home,
                conversationIDs: [UUID()],
                activeConversationID: nil
            ) == .home
        )
    }

    @Test("Last Conversation restores the persisted active conversation")
    func lastConversationDestination() {
        let first = UUID()
        let active = UUID()

        #expect(
            AppStartupPolicy.resolve(
                preference: .lastConversation,
                conversationIDs: [first, active],
                activeConversationID: active
            ) == .openConversation(active)
        )
    }

    @Test("Last Conversation falls back to Home when no conversation exists")
    func emptyLastConversationDestination() {
        #expect(
            AppStartupPolicy.resolve(
                preference: .lastConversation,
                conversationIDs: [],
                activeConversationID: nil
            ) == .home
        )
    }

    @Test("New Conversation requests a fresh conversation")
    func newConversationDestination() {
        #expect(
            AppStartupPolicy.resolve(
                preference: .newConversation,
                conversationIDs: [],
                activeConversationID: nil
            ) == .newConversation
        )
    }

    @Test("Automatic titles are concise and deterministic")
    func automaticConversationTitle() {
        #expect(
            ConversationTitlePolicy.title(
                for: "How does grace perfect human nature?",
                option: .automatic
            ) == "How Does Grace Perfect Human"
        )
    }

    @Test("Automatic titles keep the subject instead of question scaffolding")
    func automaticTitleStripsScaffolding() {
        let cases = [
            ("What does Aquinas say about the virtue of justice?", "Virtue of Justice"),
            ("How does Aquinas prove that God exists?", "God Exists"),
            ("What is grace?", "Grace"),
            ("Can you explain the five ways?", "Five Ways"),
            ("What does St. Augustine teach about original sin?", "Original Sin"),
            ("Why is justice a virtue according to Aquinas?", "Why Is Justice a Virtue")
        ]
        for (question, expected) in cases {
            #expect(ConversationTitlePolicy.title(for: question, option: .automatic) == expected)
        }
    }

    @Test("Automatic titles fit the header budget without ending on a minor word")
    func automaticTitleFitsBudget() {
        let title = ConversationTitlePolicy.title(
            for: "What does Aquinas say about the relationship of the intellect and the will?",
            option: .automatic
        ) ?? ""
        #expect(title.count <= ConversationTitlePolicy.headlineCharacterBudget)
        #expect(title == "Relationship of the Intellect")
    }

    @Test("First Question keeps the submitted question")
    func firstQuestionConversationTitle() {
        #expect(
            ConversationTitlePolicy.title(
                for: "What is the relationship between faith and reason?",
                option: .firstQuestion
            ) == "What is the relationship between faith and reason"
        )
    }

    @Test("Manual title policy does not create a title")
    func manualConversationTitle() {
        #expect(
            ConversationTitlePolicy.title(
                for: "What is grace?",
                option: .manual
            ) == nil
        )
    }

    @Test("App Lock grace periods map to elapsed seconds")
    func appLockGraceDurations() {
        #expect(AppLockGracePeriodOption.immediately.duration == 0)
        #expect(AppLockGracePeriodOption.oneMinute.duration == 60)
        #expect(AppLockGracePeriodOption.fiveMinutes.duration == 300)
        #expect(AppLockGracePeriodOption.fifteenMinutes.duration == 900)
    }
}
