import CryptoKit
import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Latest question widget storage")
struct DailyQuestionWidgetStoreTests {
    @Test("Latest question replaces the previous text and survives answering and expiration")
    func latestQuestionPersists() throws {
        let key = SymmetricKey(size: .bits256)
        let cipher = LocalDataCipher { _ in key }
        let suite = "angrove.widget.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(DailyQuestionWidgetStore.load(defaults: defaults, cipher: cipher) == nil)
        #expect(DailyQuestionWidgetStore.save("What follows?", defaults: defaults, cipher: cipher))
        let answered = HomeQuestionOfTheDay(
            question: "What matters most?",
            generatedAt: .distantPast,
            expiresAt: .distantPast,
            answeredAt: .distantPast
        )
        #expect(DailyQuestionWidgetStore.save(answered.question, defaults: defaults, cipher: cipher))
        #expect(DailyQuestionWidgetStore.load(defaults: defaults, cipher: cipher) == answered.question)
        #expect(!DailyQuestionWidgetStore.save(answered.question, defaults: defaults, cipher: cipher))
        #expect(!DailyQuestionWidgetStore.save(" \n ", defaults: defaults, cipher: cipher))
        #expect(DailyQuestionWidgetStore.load(defaults: defaults, cipher: cipher) == answered.question)
        let stored = try #require(defaults.data(forKey: "angrove.widget.latestQuestion.v1"))
        #expect(LocalDataCipher.isEncrypted(stored))
        #expect(!String(decoding: stored, as: UTF8.self).contains(answered.question))
    }
}
