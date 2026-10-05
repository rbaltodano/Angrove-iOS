import CryptoKit
import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Apple-hosted model integrity and recovery")
struct AppleHostedModelDeliveryTests {
    @Test("Verified hosted content returns its original URL without a copied model")
    func verifiedModel() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let delivery = AppleHostedModelDelivery(assets: TestAssets(url: fixture.url))
        #expect(try await delivery.prepareModel(manifest: fixture.manifest) == fixture.url)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).count == 1)
    }

    @Test("An incomplete pack is rejected before runtime initialization")
    func wrongSize() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let wrong = LiteRTModelManifest(fileName: fixture.manifest.fileName,
            byteCount: fixture.manifest.byteCount + 1, sha256: fixture.manifest.sha256)
        let delivery = AppleHostedModelDelivery(assets: TestAssets(url: fixture.url))
        await #expect(throws: LiteRTModelStoreError.self) {
            try await delivery.prepareModel(manifest: wrong)
        }
    }

    @Test("Same-size corruption fails the digest and a later corrected file can be retried")
    func corruptThenRetry() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let delivery = AppleHostedModelDelivery(assets: TestAssets(url: fixture.url))
        try Data(repeating: 0, count: fixture.data.count).write(to: fixture.url)
        await #expect(throws: LiteRTModelStoreError.self) {
            try await delivery.prepareModel(manifest: fixture.manifest)
        }
        try fixture.data.write(to: fixture.url)
        #expect(try await delivery.prepareModel(manifest: fixture.manifest) == fixture.url)
    }

    @Test("Missing content fails rather than admitting an unverified path")
    func missingContent() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.removeItem(at: fixture.url)
        let delivery = AppleHostedModelDelivery(assets: TestAssets(url: fixture.url))
        await #expect(throws: LiteRTModelStoreError.self) {
            try await delivery.prepareModel(manifest: fixture.manifest)
        }
    }

    @Test("Asset delivery errors propagate and remain retryable")
    func unavailableThenRetry() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let assets = RecoveringAssets(url: fixture.url)
        let delivery = AppleHostedModelDelivery(assets: assets)
        await #expect(throws: URLError.self) { try await delivery.prepareModel(manifest: fixture.manifest) }
        #expect(try await delivery.prepareModel(manifest: fixture.manifest) == fixture.url)
    }

    @Test("A verified file is remembered by identity and forgotten once its bytes change")
    func verificationReceipt() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let suite = "AngroveModelReceiptTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let receipt = try ModelVerificationReceipt(manifest: fixture.manifest, url: fixture.url)
        #expect(!receipt.matchesStored(in: defaults))
        receipt.store(in: defaults)
        #expect(try ModelVerificationReceipt(manifest: fixture.manifest, url: fixture.url).matchesStored(in: defaults))
        // A different pinned digest never reuses the receipt.
        let other = LiteRTModelManifest(fileName: fixture.manifest.fileName,
            byteCount: fixture.manifest.byteCount, sha256: String(repeating: "0", count: 64))
        #expect(!(try ModelVerificationReceipt(manifest: other, url: fixture.url).matchesStored(in: defaults)))
        try Data("replaced model fixture bytes".utf8).write(to: fixture.url)
        #expect(!(try ModelVerificationReceipt(manifest: fixture.manifest, url: fixture.url).matchesStored(in: defaults)))
    }
}

private struct TestAssets: ManagedModelAssetProviding {
    let url: URL
    func availableModelURL() async throws -> URL { url }
}

private actor RecoveringAssets: ManagedModelAssetProviding {
    let url: URL
    private var first = true
    init(url: URL) { self.url = url }
    func availableModelURL() async throws -> URL {
        if first { first = false; throw URLError(.notConnectedToInternet) }
        return url
    }
}

private struct Fixture {
    let directory: URL
    let url: URL
    let data = Data("verified model fixture".utf8)
    var manifest: LiteRTModelManifest {
        LiteRTModelManifest(fileName: "model.litertlm", byteCount: Int64(data.count),
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }
    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        url = directory.appending(path: "model.litertlm")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url)
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}
