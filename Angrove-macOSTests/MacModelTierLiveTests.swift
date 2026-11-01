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
            transcript: [.user("How many chapters are in the Gospel of John?", [], [])]
        ))
        let answerSeconds = Date().timeIntervalSince(answerStart)
        print("MacModelTierLive tier=\(tier.rawValue) load=\(loadSeconds)s answer=\(answerSeconds)s text=\(response.text)")
        #expect(response.text.contains("21") || response.text.lowercased().contains("twenty-one"))
        await runtime.unloadModelWeights()
    }

    /// `TEST_RUNNER_ANGROVE_LIVE_MODEL_SWITCH=1`: answers on Standard, switches to Large in the
    /// same process through the lifecycle manager, and answers again.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ANGROVE_LIVE_MODEL_SWITCH"] != nil))
    func switchesModelsWithoutRelaunching() async throws {
        let standard = MacModelTier.standard.modelStore()
        let large = MacModelTier.large.modelStore()
        let runtime = LiteRTAngroveRuntime(modelStore: standard, contextTokens: MacModelTier.standard.contextTokens)
        let driver = VerifiedMacRuntimeDriver(
            runtime: runtime,
            target: .init(store: standard, url: try standard.installedModelURL(), contextTokens: MacModelTier.standard.contextTokens)
        )
        let lifecycle = ModelRuntimeLifecycleManager(driver: driver, configuration: .adaptiveOnDevice)
        let model = LiteRTAngroveModel(runtime: runtime, groundingProvider: LazyGroundingProvider())
        let question = ConversationContext(transcript: [.user("How many chapters are in the Gospel of John?", [], [])])

        let first = try #require(await lifecycle.acquireLease())
        let firstAnswer = await model.respond(to: question).text
        await lifecycle.releaseLease(first)
        #expect(await driver.loadedFileName == MacModelTier.standard.manifest.fileName)

        await driver.switchTarget(to: .init(store: large, url: try large.installedModelURL(), contextTokens: MacModelTier.large.contextTokens))
        await lifecycle.unloadAsSoonAsIdle(reason: .modelSwitch)
        #expect(await lifecycle.currentState() == .unloaded)

        let start = Date()
        let second = try #require(await lifecycle.acquireLease())
        let secondAnswer = await model.respond(to: question).text
        await lifecycle.releaseLease(second)
        print("MacModelSwitch standard=\(firstAnswer) | large(\(Date().timeIntervalSince(start))s incl. verify+load)=\(secondAnswer)")
        #expect(await driver.loadedFileName == MacModelTier.large.manifest.fileName)
        #expect(await !driver.hasPendingSwitch)
        for answer in [firstAnswer, secondAnswer] {
            #expect(answer.contains("21") || answer.lowercased().contains("twenty-one"))
        }
        await lifecycle.unloadAsSoonAsIdle(reason: .modelSwitch)
    }
}
