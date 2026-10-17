import Foundation
import Testing
@testable import AngroveMac

/// The Question of the Day widget shares one encrypted string through the App Group.
struct MacWidgetTests {
    @Test func widgetLinkIsTheIPhoneScheme() throws {
        #expect(DailyQuestionWidgetLink.matches(try #require(URL(string: "angrove://question-of-the-day"))))
        #expect(!DailyQuestionWidgetLink.matches(try #require(URL(string: "angrove://home"))))
        let types = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        #expect(types.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains("angrove") == true })
    }

    @Test func macUsesTheSharedProductionGroup() {
        #expect(DailyQuestionWidgetStore.appGroup == AngroveAppGroup.production)
        #expect(Bundle.main.object(forInfoDictionaryKey: "BAAppGroupID") as? String == AngroveAppGroup.production)
    }

    @Test func containerMigrationMovesOnlyAngroveData() throws {
        let url = try #require(Bundle.main.url(forResource: "container-migration", withExtension: "plist"))
        let plist = try #require(NSDictionary(contentsOf: url) as? [String: Any])
        let moves = try #require(plist["Move"] as? [String])
        #expect(moves.count == 3)
        #expect(moves.allSatisfy { $0.contains("Angrove-macOS") || $0.hasSuffix("com.ryanbaltodano.Angrove.macOS.plist") })
    }
}
