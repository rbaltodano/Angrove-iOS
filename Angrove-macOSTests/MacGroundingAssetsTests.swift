import Foundation
import Testing
@testable import AngroveMac

struct MacGroundingAssetsTests {
    private static var hasBundledEncoder: Bool {
        (Bundle.main.url(forResource: "MiniLM", withExtension: "mlmodelc", subdirectory: "LocalGrounding")
            ?? Bundle.main.url(forResource: "MiniLM", withExtension: "mlmodelc")) != nil
    }

    @Test(.enabled(if: hasBundledEncoder, "LocalGrounding assets are not bundled"))
    func bundledRetrieverLoadsAndReturnsTheActualCouncilReference() throws {
        let provider = try MiniLMGroundingProvider(bundle: .main)
        let references = provider.references(for: "When was the council of nicaea?", limit: 3)
        #expect(references.contains { $0.id == "nicaea-325" && $0.facts.contains("325") })
    }
}
