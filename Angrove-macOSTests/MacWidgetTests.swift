import CryptoKit
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

    @Test func questionRoundTripsEncryptedThroughGroupDefaults() throws {
        let suite = "MacWidgetTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = SymmetricKeyBox()
        let cipher = LocalDataCipher { _ in key.value }
        #expect(DailyQuestionWidgetStore.save("What makes a life meaningful?", defaults: defaults, cipher: cipher))
        #expect(DailyQuestionWidgetStore.load(defaults: defaults, cipher: cipher) == "What makes a life meaningful?")
        // Stored as ciphertext, never the plain question.
        let stored = try #require(defaults.data(forKey: "angrove.widget.latestQuestion.v1"))
        #expect(LocalDataCipher.isEncrypted(stored))
        // A different key (e.g. from before the shared keychain item) reads nothing.
        let other = LocalDataCipher { _ in SymmetricKeyBox().value }
        #expect(DailyQuestionWidgetStore.load(defaults: defaults, cipher: other) == nil)
    }

    @Test func containerMigrationMovesOnlyAngroveData() throws {
        let url = try #require(Bundle.main.url(forResource: "container-migration", withExtension: "plist"))
        let plist = try #require(NSDictionary(contentsOf: url) as? [String: Any])
        let moves = try #require(plist["Move"] as? [String])
        #expect(moves.count == 3)
        #expect(moves.allSatisfy { $0.contains("Angrove-macOS") || $0.hasSuffix("com.ryanbaltodano.Angrove.macOS.plist") })
    }
}

private final class SymmetricKeyBox: Sendable {
    let value = SymmetricKey(size: .bits256)
}
