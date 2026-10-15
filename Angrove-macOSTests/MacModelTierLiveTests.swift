import Foundation
import Testing
@testable import AngroveMac

/// Opt-in: loads real weights through the production tier, store, checksum, runtime, and model
/// path, with no personal data. Run with `TEST_RUNNER_ANGROVE_LIVE_MODEL_TIER=large` (or
/// `standard`) in the environment of `xcodebuild test`.
struct MacModelTierLiveTests {
    private static let tierName = ProcessInfo.processInfo.environment["ANGROVE_LIVE_MODEL_TIER"]

    @Test(.enabled(if: tierName != nil))
    func installedTierAnswersThroughTheProductionModel() async throws {
        let tier = try #require(Self.tierName.flatMap(MacModelTier.init(rawValue:)))
        let store = tier.modelStore()
        let url = try store.installedModelURL()
        #expect(try LiteRTModelInstaller.sha256(of: url) == store.manifest.sha256)
        print("MacModelTierLive verified \(url.lastPathComponent)")

        let runtime = LiteRTAngroveRuntime(modelStore: store, contextTokens: tier.contextTokens)
        let loadStart = Date()
        try await runtime.loadModelWeights()
        let loadSeconds = Date().timeIntervalSince(loadStart)
        print("MacModelTierLive loaded in \(loadSeconds)s")

        let model = LiteRTAngroveModel(runtime: runtime, groundingProvider: LazyGroundingProvider())
        let answerStart = Date()
        let response = await model.respond(to: ConversationContext(
            transcript: [.user("How many chapters are in the Gospel of John?", nil, [])]
        ))
        let answerSeconds = Date().timeIntervalSince(answerStart)
        print("MacModelTierLive tier=\(tier.rawValue) load=\(loadSeconds)s answer=\(answerSeconds)s text=\(response.text)")
        #expect(response.text.contains("21") || response.text.lowercased().contains("twenty-one"))
        await runtime.unloadModelWeights()
    }
}
