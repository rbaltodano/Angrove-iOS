import Foundation
import Testing
@testable import AngroveMac

/// Opt-in Mac counterpart of the iPhone's `LiteRTEvalBatchProbe`: runs every case of a frozen
/// eval-set JSONL file through the production `LiteRTAngroveModel` on the Mac GPU, for one tier,
/// and writes `litert-eval-results.jsonl` (same per-case format, scored by Angrove-Eval's
/// `score_objective_v2.py`) plus `litert-eval-result.json` as the completion marker.
/// Generations are not recorded, so `generationCount` is absent. Thinking stays off.
///
/// `TEST_RUNNER_ANGROVE_EVAL_TIER=large TEST_RUNNER_ANGROVE_EVAL_FILE=<cases.jsonl>
/// TEST_RUNNER_ANGROVE_EVAL_OUT=<new run dir> xcodebuild … test
/// -only-testing:Angrove-macOSTests/MacModelEvalBatchTests`
/// Optional `TEST_RUNNER_ANGROVE_EVAL_IDS=id1,id2` selects cases in file order; unknown or
/// repeated IDs are rejected before loading the model. Always use a fresh output run directory.
/// `TEST_RUNNER_ANGROVE_EVAL_MODEL_LABEL` optionally names the GGUF model in the summary.
/// `TEST_RUNNER_ANGROVE_EVAL_BONSAI_PROFILE=prismRecommended` opts into Prism's sampler.
/// `TEST_RUNNER_ANGROVE_EVAL_FOLLOWUP_ROUTING=evaluativeAware` opts into the experimental
/// follow-up routing (`LiteRTAngroveModel.FollowUpRouting`).
struct MacModelEvalBatchTests {
    private static let environment = ProcessInfo.processInfo.environment

    private struct EvalCase: Decodable {
        struct Turn: Decodable {
            let role: String
            let text: String
        }
        let id: String
        let turns: [Turn]
        let question: String
    }

    private struct CaseResult: Encodable {
        let id: String
        let seconds: Double
        let text: String
        let keyTerms: [String]
        let evidenceBasis: String?
        let thinking: [String]
        let error: String?
        let runtimeGenerations: [LlamaAngroveRuntime.GenerationStats]?
    }

    /// `TEST_RUNNER_ANGROVE_EVAL_GGUF=<path>` runs that Ternary Bonsai 2 model through llama.cpp
    /// instead of a LiteRT tier.
    private static let bonsaiPath = environment["ANGROVE_EVAL_GGUF"]
    private static var usesBonsai: Bool { bonsaiPath != nil }

    @Test(.enabled(if: environment["ANGROVE_EVAL_TIER"] != nil || usesBonsai))
    func evalBatch() async throws {
        let tier = Self.environment["ANGROVE_EVAL_TIER"].flatMap(MacModelTier.init(rawValue:)) ?? .standard
        let evalURL = URL(fileURLWithPath: try #require(Self.environment["ANGROVE_EVAL_FILE"]))
        let output = URL(fileURLWithPath: try #require(Self.environment["ANGROVE_EVAL_OUT"]), isDirectory: true)
        let fileManager = FileManager.default
        #expect(!fileManager.fileExists(atPath: output.appending(path: "litert-eval-results.jsonl").path))
        try? fileManager.createDirectory(at: output, withIntermediateDirectories: true)

        let store = tier.modelStore()
        let modelURL = try Self.bonsaiPath.map { URL(fileURLWithPath: $0) } ?? store.installedModelURL()
        let modelSHA256 = try LiteRTModelInstaller.sha256(of: modelURL)
        if !Self.usesBonsai { #expect(modelSHA256 == store.manifest.sha256) }
        let allCases = try String(contentsOf: evalURL, encoding: .utf8)
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { try JSONDecoder().decode(EvalCase.self, from: Data($0.utf8)) }
        let selectedIDs = Self.environment["ANGROVE_EVAL_IDS"].map {
            $0.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        if let selectedIDs {
            try #require(!selectedIDs.isEmpty && !selectedIDs.contains(""), "Eval IDs must be nonempty")
            try #require(Set(selectedIDs).count == selectedIDs.count, "Duplicate eval IDs")
            let unknown = Set(selectedIDs).subtracting(allCases.map(\.id))
            try #require(unknown.isEmpty, "Unknown eval IDs: \(unknown.sorted())")
        }
        let selection = selectedIDs.map { Set($0) }
        let cases = allCases.filter { selection?.contains($0.id) ?? true }
        try #require(!cases.isEmpty, "No eval cases selected")

        let profileName = Self.environment["ANGROVE_EVAL_BONSAI_PROFILE"] ?? "caller"
        let profile = try #require(LlamaAngroveRuntime.SamplingProfile(rawValue: profileName), "Unknown Bonsai profile")
        let bonsaiRuntime = Self.usesBonsai ? LlamaAngroveRuntime(
            modelURL: modelURL, samplingProfile: profile, recordsGenerationStats: true
        ) : nil
        let runtime: any AngroveTextRuntime
        if let bonsaiRuntime { runtime = bonsaiRuntime }
        else { runtime = LiteRTAngroveRuntime(modelStore: store, contextTokens: tier.contextTokens) }
        let loadStart = ContinuousClock.now
        try await runtime.loadModelWeights()
        let loadSeconds = Self.seconds(since: loadStart)
        let promptStyleName = Self.environment["ANGROVE_EVAL_PROMPT_STYLE"] ?? "standard"
        let promptStyle = try #require(LiteRTAngroveModel.ConversationPromptStyle(rawValue: promptStyleName))
        try #require(promptStyle == .standard || Self.usesBonsai, "Compact Bonsai prompt requires a GGUF runtime")
        let routingName = Self.environment["ANGROVE_EVAL_FOLLOWUP_ROUTING"] ?? "standard"
        let routing = try #require(LiteRTAngroveModel.FollowUpRouting(rawValue: routingName), "Unknown follow-up routing")
        let model = LiteRTAngroveModel(
            runtime: runtime, groundingProvider: LazyGroundingProvider(), conversationPromptStyle: promptStyle,
            followUpRouting: routing
        )

        let resultsURL = output.appending(path: "litert-eval-results.jsonl")
        fileManager.createFile(atPath: resultsURL.path, contents: nil)
        var failed = 0
        for evalCase in cases {
            var transcript: [ChatBlock] = evalCase.turns.map { turn in
                turn.role == "assistant" ? .text(turn.text) : .user(turn.text, nil, [])
            }
            transcript.append(.user(evalCase.question, nil, []))
            let start = ContinuousClock.now
            let response = await model.respond(to: ConversationContext(transcript: transcript))
            let elapsed = Self.seconds(since: start)
            let didFail = response.text.contains("on-device Angrove model couldn't complete")
                || response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if didFail { failed += 1 }
            let result = CaseResult(
                id: evalCase.id,
                seconds: elapsed,
                text: response.text,
                keyTerms: response.keyTerms.map(\.displayText),
                evidenceBasis: response.evidenceBasis.map { String(describing: $0) },
                thinking: response.thinkingSummary,
                error: didFail ? "local generation failed" : nil,
                runtimeGenerations: await bonsaiRuntime?.takeGenerationStats()
            )
            var line = try JSONEncoder().encode(result)
            // The sandboxed test host may not be allowed to write the run folder; the console
            // copy lets the results file be rebuilt from the log.
            print("MacEvalResult \(String(decoding: line, as: UTF8.self))")
            line.append(0x0A)
            if let handle = try? FileHandle(forWritingTo: resultsURL) {
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.close()
            }
            print("MacEval \(evalCase.id) \(String(format: "%.1f", elapsed))s")
        }
        await runtime.unloadModelWeights()

        let summary: [String: Any] = [
            "tier": Self.usesBonsai
                ? (Self.environment["ANGROVE_EVAL_MODEL_LABEL"] ?? modelURL.deletingPathExtension().lastPathComponent)
                : tier.rawValue,
            "model": ["fileName": modelURL.lastPathComponent, "sha256": modelSHA256],
            "evalFile": evalURL.lastPathComponent,
            "evalFileSHA256": try LiteRTModelInstaller.sha256(of: evalURL),
            "loadSeconds": loadSeconds,
            "caseCount": cases.count,
            "selectedIDs": cases.map(\.id),
            "failedCount": failed,
            "contextTokens": Self.usesBonsai ? LlamaAngroveRuntime.defaultContextTokens : tier.contextTokens,
            "backend": Self.usesBonsai ? "llama.cpp metal" : "gpu",
            "thinkingEnabled": false,
            "bonsaiSamplingProfile": Self.usesBonsai ? profileName : "notApplicable",
            "conversationPromptStyle": promptStyleName,
            "followUpRouting": routingName,
            "physicalMemoryBytes": ProcessInfo.processInfo.physicalMemory,
            "finishedAt": Date.now.ISO8601Format(),
        ]
        let data = try JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys])
        print("MacEvalSummary \(String(decoding: data, as: UTF8.self))")
        try? data.write(to: output.appending(path: "litert-eval-result.json"), options: .atomic)
    }

    private static func seconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now).components
        return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
    }
}
