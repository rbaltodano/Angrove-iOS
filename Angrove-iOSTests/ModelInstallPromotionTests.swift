import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Verified model promotion")
struct ModelInstallPromotionTests {
    @Test("A verified replacement installs and a failed replacement preserves the installed bytes")
    func replacesWithoutDeletingFirst() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("model.bin")
        let staged = root.appendingPathComponent("model.installing")
        try Data("first".utf8).write(to: staged)
        try LiteRTModelInstaller.promote(staged: staged, to: destination)
        #expect(try Data(contentsOf: destination) == Data("first".utf8))
        try Data("replacement".utf8).write(to: staged)
        try LiteRTModelInstaller.promote(staged: staged, to: destination)
        #expect(try Data(contentsOf: destination) == Data("replacement".utf8))
        #expect(throws: (any Error).self) {
            try LiteRTModelInstaller.promote(staged: staged, to: destination)
        }
        #expect(try Data(contentsOf: destination) == Data("replacement".utf8))
    }
}
