import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Settings licenses")
struct LicensesTests {
    @Test("Every bundled license loads and reflows into paragraphs", arguments: BundledLicense.allCases)
    func licenseTextLoads(_ license: BundledLicense) {
        let paragraphs = license.paragraphs
        #expect(paragraphs.count > 3)
        #expect(paragraphs.allSatisfy { !$0.contains("\n") })
    }

    @Test("Library acknowledgments have complete, unique notices")
    func libraryNoticesAreComplete() {
        let works = AcknowledgedWork.library
        #expect(works.count == 37)
        #expect(Set(works.map(\.id)).count == works.count)
        #expect(works.allSatisfy { $0.license == .libraryPublicDomain })
        #expect(works.allSatisfy { !$0.notice.isEmpty })
    }

    @Test("Library acknowledgments cover every bundled work",
          .enabled(if: BundledLibraryAssets.areAvailable, "Local Library corpus is not bundled"))
    func libraryWorksAreAcknowledged() throws {
        let corpus = try #require(BundledPassageCorpus.bundled())
        #expect(Set(AcknowledgedWork.library.map(\.name)) == Set(corpus.passages.map(\.title)))
    }

    @Test("Each acknowledged work names its copyright holder")
    func worksCarryNotices() {
        let works = AcknowledgedWork.models + AcknowledgedWork.software + AcknowledgedWork.fonts
        #expect(works.allSatisfy { $0.notice.hasPrefix("Copyright") })
        #expect(Set(works.map(\.license)) == Set(BundledLicense.allCases.filter { $0 != .libraryPublicDomain }))
    }
}
