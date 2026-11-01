import Foundation
import Testing
@testable import AngroveMac

struct MacModelTierTests {
    private let gib: UInt64 = 1_024 * 1_024 * 1_024

    @Test func noSelectionUsesStandard() {
        #expect(MacModelTier.resolve(selected: nil, physicalMemory: 64 * gib, isInstalled: { _ in true }) == .standard)
    }

    @Test func eligibleInstalledSelectionIsUsed() {
        #expect(MacModelTier.resolve(selected: .large, physicalMemory: 24 * gib, offered: MacModelTier.allCases, isInstalled: { _ in true }) == .large)
    }

    @Test func largeFallsBackBelowItsMemoryMinimum() {
        #expect(MacModelTier.resolve(selected: .large, physicalMemory: 16 * gib, offered: MacModelTier.allCases, isInstalled: { _ in true }) == .standard)
    }

    @Test func missingModelFallsBackToStandard() {
        #expect(MacModelTier.resolve(selected: .large, physicalMemory: 64 * gib, isInstalled: { $0 == .standard }) == .standard)
    }

    @Test func firstBetaOffersOnlyStandard() {
        #expect(MacModelTier.offered == [.standard])
    }

    @Test func storedLargeSelectionResolvesToStandardWhileNotOffered() {
        #expect(MacModelTier.resolve(selected: .large, physicalMemory: 64 * gib, isInstalled: { _ in true }) == .standard)
    }

    @Test func standardKeepsTheIPhonePackageAndContext() {
        #expect(MacModelTier.standard.manifest == .angrove)
        #expect(MacModelTier.allCases.allSatisfy { $0.contextTokens == AngroveContextBudget.totalTokenLimit })
    }

    @Test func tiersUseDistinctModelFiles() {
        let names = MacModelTier.allCases.map(\.manifest.fileName)
        #expect(Set(names).count == names.count)
        // Cache cleanup matches by file-name prefix, so no name may prefix another.
        for name in names {
            #expect(names.filter { $0.hasPrefix(name) } == [name])
        }
    }

    @Test func cacheCleanupRemovesOnlyInactiveTiers() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "MacModelTierTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let standard = "gemma-4-E4B-it.litertlm_1_2_mldrift_program_cache.bin"
        let large = "gemma-4-12B-it.litertlm_1_2_mldrift_weight_cache.bin"
        let other = "unrelated.bin"
        for name in [standard, large, other] {
            FileManager.default.createFile(atPath: directory.appending(path: name).path, contents: Data())
        }
        MacModelTier.removeCaches(except: .standard, in: directory)
        let remaining = try Set(FileManager.default.contentsOfDirectory(atPath: directory.path))
        #expect(remaining == [standard, other])
    }
}
