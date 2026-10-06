import Testing
@testable import Angrove_iOS

@Suite("Page return notifications")
@MainActor
struct PageReturnNotificationTests {
    @Test("The newest redirect replaces the previous return destination")
    func latestRedirectWins() async {
        let center = ModelCompletionNotificationCenter()
        var returnedTo = ""
        let first = center.schedulePageReturn(title: "Return to Home", returnPage: .home) { returnedTo = "Home" }
        let latest = center.schedulePageReturn(title: "Return to Conversation", returnPage: .conversation) { returnedTo = "Conversation" }
        #expect(center.notifications.isEmpty)
        await first.value
        await latest.value
        #expect(center.notifications.count == 1)
        let notification = center.notifications[0]
        #expect(notification.title == "Return to Conversation")
        #expect(notification.returnPage == .conversation)
        center.open(id: notification.id)
        #expect(returnedTo == "Conversation")
        #expect(center.notifications.isEmpty)
        center.open(id: notification.id)
        #expect(center.notifications.isEmpty)
    }

    @Test("Declining a return keeps the current page")
    func declineDoesNotNavigate() {
        let center = ModelCompletionNotificationCenter()
        var didReturn = false
        center.post(title: "Return to Conversation", kind: .pageReturn, returnPage: .conversation) { didReturn = true }
        center.dismiss(id: center.notifications[0].id)
        #expect(!didReturn)
        #expect(center.notifications.isEmpty)
    }

    @Test("Explicit navigation clears a stale return action")
    func explicitNavigationClearsReturn() async {
        let center = ModelCompletionNotificationCenter()
        var didReturn = false
        let pending = center.schedulePageReturn(title: "Return to Home", returnPage: .home) { didReturn = true }
        center.dismissPageReturn()
        await pending.value
        #expect(!didReturn)
        #expect(center.notifications.isEmpty)
    }
}
