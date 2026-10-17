import CryptoKit
import Foundation
import Testing
@testable import AngroveMac

/// The Mac gets its models as Apple-hosted packs: Standard (E4B) is essential at install, Large
/// (12B) downloads on demand. These cover the routing and verification; the hosted service itself
/// needs TestFlight or Apple's local mock server.
struct MacModelDeliveryTests {
    @Test func eachTierHasItsOwnPinnedPack() {
        #expect(MacModelTier.standard.assetPack == .e4b)
        #expect(MacModelTier.large.assetPack == .gemma12B)
        #expect(MacModelTier.standard.manifest == .angrove)
        #expect(AngroveModelAssetPack.pack(for: .angrove) == .e4b)
        #expect(AngroveModelAssetPack.pack(for: MacModelTier.large.manifest) == .gemma12B)
        // Pack paths carry the pinned digest prefix, so a new model can never reuse an ID.
        for pack in AngroveModelAssetPack.all {
            #expect(pack.id.hasSuffix(String(pack.manifest.sha256.prefix(8))))
            #expect(pack.path.hasSuffix("/" + pack.manifest.fileName))
            #expect(pack.path.contains(pack.id))
        }
    }

    @Test func packManifestsMatchTheCode() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for (file, pack, policy) in [("Mac-Gemma4-E4B.json", AngroveModelAssetPack.e4b, "essential"),
                                     ("Mac-Gemma4-12B.json", AngroveModelAssetPack.gemma12B, "onDemand")] {
            let data = try Data(contentsOf: root.appending(path: "AssetPacks/\(file)"))
            let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(json["assetPackID"] as? String == pack.id)
            #expect(json["platforms"] as? [String] == ["macOS"])
            #expect((json["downloadPolicy"] as? [String: Any])?.keys.first == policy)
            let selector = try #require((json["fileSelectors"] as? [[String: String]])?.first)
            #expect(selector["fileDestination"] == pack.path)
        }
    }

    @Test func deliveriesAreRoutedByManifest() {
        #expect(AppleHostedModelDelivery.delivery(for: .angrove) === AppleHostedModelDelivery.shared)
        let large = AppleHostedModelDelivery.delivery(for: MacModelTier.large.manifest)
        #expect(large != nil)
        #expect(large === AppleHostedModelDelivery.delivery(for: MacModelTier.large.manifest))
        #expect(large !== AppleHostedModelDelivery.shared)
        let unknown = LiteRTModelManifest(fileName: "other.litertlm", byteCount: 1, sha256: String(repeating: "0", count: 64))
        #expect(AppleHostedModelDelivery.delivery(for: unknown) == nil)
    }

    @MainActor @Test func eachTierReportsItsOwnDownload() {
        #expect(MacModelTier.standard.delivery === ModelDeliveryState.shared)
        #expect(MacModelTier.large.delivery === ModelDeliveryState.state(for: .gemma12B))
        #expect(MacModelTier.large.delivery !== ModelDeliveryState.shared)
        #expect(MacModelTier.large.delivery.pack == .gemma12B)
    }

    @Test func receiptsArePerPackAndTheIPhoneKeyIsUnchanged() throws {
        #expect(ModelVerificationReceipt.defaultsKey(for: .e4b) == "modelDelivery.verifiedFile.v1")
        #expect(ModelVerificationReceipt.defaultsKey(for: .gemma12B) != ModelVerificationReceipt.defaultsKey(for: .e4b))

        let fixture = try Fixture()
        defer { fixture.remove() }
        let suite = "MacModelDeliveryTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let large = try ModelVerificationReceipt(manifest: fixture.manifest, url: fixture.url, pack: .gemma12B)
        large.store(in: defaults)
        #expect(large.matchesStored(in: defaults))
        // Verifying the Large pack never vouches for Standard's file, or the reverse.
        #expect(!(try ModelVerificationReceipt(manifest: fixture.manifest, url: fixture.url, pack: .e4b)).matchesStored(in: defaults))
        ModelVerificationReceipt.clear(in: defaults, pack: .gemma12B)
        #expect(!large.matchesStored(in: defaults))
    }

    @Test func largePackIsVerifiedBeforeUse() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let delivery = AppleHostedModelDelivery(assets: FixedAssets(url: fixture.url), pack: .gemma12B)
        #expect(try await delivery.prepareModel(manifest: fixture.manifest) == fixture.url)
        try Data(repeating: 0, count: fixture.data.count).write(to: fixture.url)
        await #expect(throws: LiteRTModelStoreError.self) {
            try await delivery.prepareModel(manifest: fixture.manifest)
        }
    }

    @MainActor @Test func downloadStateFollowsPreparation() async throws {
        let state = ModelDeliveryState(pack: .gemma12B, prepare: { throw URLError(.notConnectedToInternet) })
        state.retry()
        for _ in 0..<100 where state.phase.isBusy { try await Task.sleep(for: .milliseconds(10)) }
        #expect(state.phase == .failed(.network))
    }

    @Test func storageFailureNamesTheMac() {
        #expect(String(localized: ModelDeliveryFailure.storage.message).contains("this Mac"))
    }
}

private struct FixedAssets: ManagedModelAssetProviding {
    let url: URL
    func availableModelURL() async throws -> URL { url }
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
