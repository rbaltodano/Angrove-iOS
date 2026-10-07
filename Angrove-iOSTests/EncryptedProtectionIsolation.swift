import Foundation
import Testing
@testable import Angrove_iOS

/// Fault tests close a process-wide production gate. Restore an empty test-only boundary between
/// cases; never reopen or discard the app's live stores to make a failing test pass.
nonisolated struct EncryptedProtectionIsolation: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(for test: Test, testCase: Test.Case?, performing function: @concurrent @Sendable () async throws -> Void) async throws {
        guard !test.isSuite else { try await function(); return }
        let suite = "EncryptedProtectionIsolation.\(UUID())"
        guard let defaults = UserDefaults(suiteName: suite) else { throw InquiryPersistenceError.applicationSupportUnavailable }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        func restore() throws {
            try PersonalDataProtection.prepare(preferences: PrivatePreferences(defaults: defaults),
                rootDirectory: root, migrateWidget: {})
        }
        try restore()
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
            try? restore()
        }
        try await function()
    }
}
