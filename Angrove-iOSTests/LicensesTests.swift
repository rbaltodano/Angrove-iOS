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

    @Test("Each acknowledged work names its copyright holder")
    func worksCarryNotices() {
        let works = AcknowledgedWork.models + AcknowledgedWork.software + AcknowledgedWork.fonts
        #expect(works.allSatisfy { $0.notice.hasPrefix("Copyright") })
        #expect(Set(works.map(\.license)) == Set(BundledLicense.allCases))
    }
}
