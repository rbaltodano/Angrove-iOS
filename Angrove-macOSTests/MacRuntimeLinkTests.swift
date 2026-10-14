import Foundation
import LiteRTLM
import Testing

struct MacRuntimeLinkTests {
    @Test func nativeLibraryRejectsMissingModel() {
        // Exercise the vendored Swift wrapper and native Mac binary without loading weights.
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing.litertlm").path
        #expect(Capabilities(modelPath: missingPath) == nil)
    }
}
