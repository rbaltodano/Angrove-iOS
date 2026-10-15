import Foundation
import Testing
@testable import AngroveMac

@MainActor
struct MacPageTransitionTests {
    @Test func departureKeepsTheOldPageAndCommitsOnlyTheLatestRequestWhileHidden() async throws {
        let transition = MacPageTransition(fadeDuration: 0.03, pauseDuration: 0.02)
        let original = MacWorkspacePage(destination: .conversations, conversationID: UUID())
        let home = MacWorkspacePage(destination: .home)
        let library = MacWorkspacePage(destination: .library)
        var displayed = original
        var arrivals: [MacWorkspacePage] = []
        transition.navigate(to: home) { displayed = home; arrivals.append(home) }
        try await wait { !transition.isVisible }
        #expect(displayed == original)
        #expect(transition.canRevealContent)
        transition.navigate(to: library) {
            #expect(!transition.isVisible)
            #expect(!transition.canRevealContent)
            displayed = library
            arrivals.append(library)
        }
        try await wait { !transition.isTransitioning }
        #expect(displayed == library)
        #expect(arrivals == [library])
        #expect(transition.isVisible && transition.canRevealContent)
        #expect(transition.destination == nil)
    }

    @Test func anotherRequestDuringArrivalStartsAFreshDeparture() async throws {
        let transition = MacPageTransition(fadeDuration: 0.06, pauseDuration: 0.01)
        let first = MacWorkspacePage(destination: .home)
        let second = MacWorkspacePage(destination: .settings)
        var arrivals: [MacWorkspacePage] = []
        transition.navigate(to: first) { arrivals.append(first) }
        try await wait { arrivals == [first] && transition.isVisible }
        transition.navigate(to: second) { arrivals.append(second) }
        try await wait { !transition.isVisible }
        #expect(transition.destination == second)
        try await wait { !transition.isTransitioning }
        #expect(arrivals == [first, second])
        #expect(transition.isVisible)
        #expect(transition.destination == nil)
    }

    @Test func cancellationPreventsLateNavigationAndAllowsTheNextTransition() async throws {
        let transition = MacPageTransition(fadeDuration: 0.03, pauseDuration: 0.02)
        let home = MacWorkspacePage(destination: .home)
        var arrivals = 0
        transition.navigate(to: home) { arrivals += 1 }
        try await wait { !transition.isVisible }
        transition.cancel()
        try await Task.sleep(for: .milliseconds(100))
        #expect(arrivals == 0)
        #expect(!transition.isTransitioning && transition.isVisible && transition.canRevealContent)
        transition.navigate(to: home) { arrivals += 1 }
        try await wait { !transition.isTransitioning }
        #expect(arrivals == 1)
    }

    @Test func returningToTheDepartingPageDiscardsTheSupersededArrivalAction() async throws {
        let transition = MacPageTransition(fadeDuration: 0.03, pauseDuration: 0.02)
        let original = MacWorkspacePage(destination: .conversations, conversationID: UUID())
        var receivedQuote = false
        var restored = false
        transition.navigate(to: MacWorkspacePage(destination: .insights)) { receivedQuote = true }
        try await wait { !transition.isVisible }
        transition.navigate(to: original) { restored = true }
        try await wait { !transition.isTransitioning }
        #expect(!receivedQuote)
        #expect(restored)
    }

    private func wait(until predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !predicate() && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(predicate())
    }
}
