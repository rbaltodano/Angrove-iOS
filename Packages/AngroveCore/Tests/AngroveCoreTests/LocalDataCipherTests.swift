import CryptoKit
import Foundation
import Testing
@testable import AngroveCore

struct LocalDataCipherTests {
    private let key = SymmetricKey(size: .bits256)

    @Test func sealedDataOpensOnlyWithItsKeyAndContext() throws {
        let cipher = LocalDataCipher { _ in key }
        let sealed = try cipher.seal(Data("private question".utf8), context: "a")
        #expect(LocalDataCipher.isEncrypted(sealed))
        #expect(String(decoding: try cipher.open(sealed, context: "a"), as: UTF8.self) == "private question")
        // Ciphertext can't be swapped between stores, or opened with another key.
        #expect(throws: (any Error).self) { try cipher.open(sealed, context: "b") }
        #expect(throws: (any Error).self) { try LocalDataCipher { _ in SymmetricKey(size: .bits256) }.open(sealed, context: "a") }
    }

    @Test func plaintextIsNeverMistakenForCiphertext() {
        #expect(!LocalDataCipher.isEncrypted(Data("plain".utf8)))
        #expect(throws: LocalDataEncryptionError.self) { try LocalDataCipher { _ in key }.open(Data("plain".utf8), context: "a") }
    }
}

/// The Question of the Day widget shares one encrypted string through the App Group.
struct DailyQuestionWidgetStoreTests {
    @Test func questionRoundTripsEncryptedThroughGroupDefaults() throws {
        let suite = "AngroveCoreWidgetTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = SymmetricKey(size: .bits256)
        let cipher = LocalDataCipher { _ in key }
        #expect(DailyQuestionWidgetStore.save("What makes a life meaningful?", defaults: defaults, cipher: cipher))
        #expect(DailyQuestionWidgetStore.load(defaults: defaults, cipher: cipher) == "What makes a life meaningful?")
        let stored = try #require(defaults.data(forKey: "angrove.widget.latestQuestion.v1"))
        #expect(LocalDataCipher.isEncrypted(stored))
        // A different key (e.g. from before the shared keychain item) reads nothing.
        #expect(DailyQuestionWidgetStore.load(defaults: defaults, cipher: LocalDataCipher { _ in SymmetricKey(size: .bits256) }) == nil)
    }

    @Test func widgetLinkMatchesOnlyItsURL() throws {
        #expect(DailyQuestionWidgetLink.matches(try #require(URL(string: "angrove://question-of-the-day"))))
        #expect(!DailyQuestionWidgetLink.matches(try #require(URL(string: "angrove://home"))))
    }
}

struct ModelManifestTests {
    @Test func e4bPackIsPinnedToItsDigest() {
        let pack = AngroveModelAssetPack.e4b
        #expect(pack.manifest == .angrove)
        #expect(pack.id.hasSuffix(String(pack.manifest.sha256.prefix(8))))
        #expect(pack.path == "Models/\(pack.id)/\(pack.manifest.fileName)")
        #expect(AngroveModelAssetPack.id == pack.id && AngroveModelAssetPack.path == pack.path)
    }
}
