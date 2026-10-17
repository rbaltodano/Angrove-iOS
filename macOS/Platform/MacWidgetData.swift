import Foundation
import WidgetKit

/// The Question of the Day widget reads one encrypted string from the shared App Group.
@MainActor enum MacWidgetData {
    /// Drops a shared question this build can't open, such as one sealed with a key from before
    /// the widget's shared keychain item existed, so the next daily question can be published.
    static func prepare() {
        do { try DailyQuestionWidgetStore.migrate() } catch { DailyQuestionWidgetStore.discard() }
        HomeQuestionOfTheDayStore.reloadWidgetTimeline()
    }

    /// Clicking the widget starts the saved question's conversation, as on iPhone, or opens
    /// Home when there is no question yet. Posted on the next turn so a cold launch's workspace
    /// is already listening.
    static func open(_ url: URL) {
        guard DailyQuestionWidgetLink.matches(url) else { return }
        let request = HomeQuestionOfTheDayStore.load()
            .flatMap { HomeQuestionOfTheDay.isValidQuestionText($0.question) ? $0.conversationRequest : nil }
        DispatchQueue.main.async { NotificationCenter.default.post(name: .macOpenHome, object: request) }
    }

    /// Removes the shared question, its App Group preferences and its keychain key.
    static func erase() throws {
        DailyQuestionWidgetStore.discard()
        if let defaults = UserDefaults(suiteName: DailyQuestionWidgetStore.appGroup) {
            defaults.removePersistentDomain(forName: DailyQuestionWidgetStore.appGroup)
        }
        try LocalDataKeychain.remove(service: "com.angrove.widget-data.v1", accessGroup: DailyQuestionWidgetStore.appGroup)
        HomeQuestionOfTheDayStore.reloadWidgetTimeline()
    }
}
