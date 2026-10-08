import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Deferred encrypted writes", .serialized)
struct PersistenceDeferredWriteTests {
    @Test("A save refused while the phone is locked stays readable and is written after unlock")
    func lockedSaveIsRetried() async throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "AngroveDeferred-\(UUID())")
        let suite = "AngroveDeferredWriteTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: base)
            defaults.removePersistentDomain(forName: suite)
        }
        let fileManager = LockableFileManager()
        let store = InsightTreeLocalStateFileStore(rootDirectory: base, defaults: defaults, fileManager: fileManager)
        let persistence = SerializedPersonalStore()

        fileManager.isLocked = true
        persistence.save(["Virtue"], key: "deferred-test", store: store)
        await persistence.flush()
        #expect(!PersonalDataProtection.isBlocked)
        #expect(persistence.load([String].self, key: "deferred-test", store: store) == ["Virtue"])
        #expect(!FileManager.default.fileExists(atPath: store.url(for: "deferred-test").path))

        fileManager.isLocked = false
        persistence.retryDeferredWrites()
        await persistence.flush()
        #expect(SerializedPersonalStore().load([String].self, key: "deferred-test", store: store) == ["Virtue"])
    }

    @Test("Completed-answer notifications carry a short plain-text preview")
    @MainActor
    func notificationPreview() {
        let response = "**Prudence** is right reason applied to action. " + String(repeating: "It weighs means and ends. ", count: 20)
        let preview = AngroveSystemNotifications.responsePreview(from: response)
        #expect(preview.hasPrefix("Prudence is right reason"))
        #expect(!preview.contains("**"))
        #expect(preview.count <= 161)
        #expect(preview.hasSuffix("…"))
        #expect(AngroveSystemNotifications.responsePreview(from: "A short answer.") == "A short answer.")
    }
}

/// Simulates complete file protection while the device is locked.
private final class LockableFileManager: FileManager, @unchecked Sendable {
    var isLocked = false

    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        if isLocked { throw CocoaError(.fileWriteNoPermission) }
        try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }
}
