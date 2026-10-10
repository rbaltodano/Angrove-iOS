import Foundation
import Testing
@testable import Angrove_iOS

@MainActor
struct NewUserCardEligibilityTests {
    @Test
    func sevenDayBoundaryAndCompletedGuide() {
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        let topics: Set<String> = ["conversation", "tree", "privacy"]
        #expect(NewUserCardEligibility.shouldShow(firstUse: first, now: first, visited: [], topics: topics))
        #expect(NewUserCardEligibility.shouldShow(firstUse: first, now: first.addingTimeInterval(604_799), visited: ["tree", "unknown"], topics: topics))
        #expect(!NewUserCardEligibility.shouldShow(firstUse: first, now: first.addingTimeInterval(604_800), visited: [], topics: topics))
        #expect(!NewUserCardEligibility.shouldShow(firstUse: first, now: first.addingTimeInterval(604_801), visited: [], topics: topics))
        #expect(!NewUserCardEligibility.shouldShow(firstUse: first, now: first, visited: topics, topics: topics))
        #expect(!NewUserCardEligibility.shouldShow(firstUse: nil, now: first, visited: [], topics: topics))
    }

    @Test
    func updatingDoesNotRestartFirstWeek() throws {
        let name = "new-user-card-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let original = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.set(original.timeIntervalSince1970, forKey: NewUserCardEligibility.firstUseKey)
        NewUserCardEligibility.registerFirstUse(defaults: defaults, now: original.addingTimeInterval(900_000))
        #expect(defaults.double(forKey: NewUserCardEligibility.firstUseKey) == original.timeIntervalSince1970)
    }
}
