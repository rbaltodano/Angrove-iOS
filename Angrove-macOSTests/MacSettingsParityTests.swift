import Foundation
import Testing
@testable import AngroveMac

@MainActor
struct MacSettingsParityTests {
    /// The Mac app is not sandboxed for local use, so resets must never reach shared folders.
    @Test func dataResetIsConfinedToAngroveFolders() throws {
        let support = try #require(MacAppData.supportRoot)
        let cache = try #require(MacAppData.cacheRoot)
        #expect(support.lastPathComponent == "Angrove-macOS")
        #expect(cache.lastPathComponent == "Angrove-macOS")
        #expect(support.deletingLastPathComponent().lastPathComponent == "Application Support")
        #expect(cache.deletingLastPathComponent().lastPathComponent == "Caches")
    }

    @Test func conversationTitlesFollowTheSharedSetting() {
        let key = SettingsStorageKey.conversationTitles
        let previous = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }
        let question = "What does Aquinas say about the virtue of justice?"

        UserDefaults.standard.set(ConversationTitleOption.manual.rawValue, forKey: key)
        #expect(MacConversationState.automaticTitle(for: question) == nil)
        UserDefaults.standard.set(ConversationTitleOption.firstQuestion.rawValue, forKey: key)
        #expect(MacConversationState.automaticTitle(for: question) == "What does Aquinas say about the virtue of justice")
        UserDefaults.standard.set(ConversationTitleOption.automatic.rawValue, forKey: key)
        #expect(MacConversationState.automaticTitle(for: question) == ConversationTitlePolicy.title(for: question, option: .automatic))
    }
}
