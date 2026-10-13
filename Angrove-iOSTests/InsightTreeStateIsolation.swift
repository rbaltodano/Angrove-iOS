import Foundation
import Testing
@testable import Angrove_iOS

/// Global-tree cases must retain nil scope without inheriting another case's saved anchors.
nonisolated struct InsightTreeStateIsolation: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(for test: Test, testCase: Test.Case?, performing function: @concurrent @Sendable () async throws -> Void) async throws {
        guard !test.isSuite else { try await function(); return }
        let suite = "InsightTreeStateIsolation.\(UUID())"
        guard let defaults = UserDefaults(suiteName: suite) else { throw InquiryPersistenceError.applicationSupportUnavailable }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = InsightTreeLocalStateFileStore(rootDirectory: root, defaults: defaults)
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        try await InsightTreeLocalStateStore.$scopedStore.withValue(store) {
            do {
                try await function()
            } catch {
                await SerializedPersonalStore.shared.flush()
                throw error
            }
            await SerializedPersonalStore.shared.flush()
        }
    }
}
