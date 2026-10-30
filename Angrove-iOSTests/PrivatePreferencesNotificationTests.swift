import CryptoKit
import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Encrypted preference notification isolation", .serialized, EncryptedProtectionIsolation())
struct PrivatePreferencesNotificationTests {
    @Test("Background encrypted saves preserve the app domain without notifying AppStorage's defaults")
    @MainActor
    func encryptedSaveDoesNotEnterSwiftUIOnWorker() async throws {
        let key = "aquinas.test.notification-isolation.\(UUID())"
        let defaults = UserDefaults.standard
        let cipherKey = SymmetricKey(size: .bits256)
        let preferences = PrivatePreferences(defaults: defaults, cipher: LocalDataCipher { _ in cipherKey })
        let notifications = NotificationCount()
        let observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: nil
        ) { _ in
            if !Thread.isMainThread { notifications.increment() }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
            preferences.removeObject(forKey: key)
        }

        let persistence = SerializedPersonalStore()
        persistence.savePreference(["question": "What is prudence?"], key: key, preferences: preferences)
        // A pending replacement remains visible before the worker finishes saving it.
        #expect(persistence.loadPreference([String: String].self, key: key, preferences: preferences)
            == ["question": "What is prudence?"])
        await persistence.flush()

        #expect(notifications.value == 0)
        // The bytes stay in the existing application domain and retain their encrypted format.
        let encrypted = try #require(defaults.data(forKey: key))
        #expect(LocalDataCipher.isEncrypted(encrypted))
        #expect(preferences.decoded([String: String].self, forKey: key)
            == ["question": "What is prudence?"])
        #expect(preferences.defaults === defaults)
        preferences.removeObject(forKey: key)
        #expect(defaults.object(forKey: key) == nil)
    }
}

private nonisolated final class NotificationCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
