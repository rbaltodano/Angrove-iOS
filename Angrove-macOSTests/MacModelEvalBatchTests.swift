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
    }

    @Test(.enabled(if: environment["ANGROVE_EVAL_TIER"] != nil))
    func evalBatch() async throws {
        let tier = try #require(Self.environment["ANGROVE_EVAL_TIER"].flatMap(MacModelTier.init(rawValue:)))
        let evalURL = URL(fileURLWithPath: try #require(Self.environment["ANGROVE_EVAL_FILE"]))
        let output = URL(fileURLWithPath: try #require(Self.environment["ANGROVE_EVAL_OUT"]), isDirectory: true)
        let fileManager = FileManager.default
        #expect(!fileManager.fileExists(atPath: output.appending(path: "litert-eval-results.jsonl").path))
        try fileManager.createDirectory(at: output, withIntermediateDirectories: true)

        let store = tier.modelStore()
        let modelURL = try store.installedModelURL()
        let modelSHA256 = try LiteRTModelInstaller.sha256(of: modelURL)
        #expect(modelSHA256 == store.manifest.sha256)
        let cases = try String(contentsOf: evalURL, encoding: .utf8)
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { try JSONDecoder().decode(EvalCase.self, from: Data($0.utf8)) }

        let runtime = LiteRTAngroveRuntime(modelStore: store, contextTokens: tier.contextTokens)
        let loadStart = ContinuousClock.now
        try await runtime.loadModelWeights()
        let loadSeconds = Self.seconds(since: loadStart)
        let model = LiteRTAngroveModel(runtime: runtime, groundingProvider: LazyGroundingProvider())

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
                error: didFail ? "local generation failed" : nil
            )
            var line = try JSONEncoder().encode(result)
            line.append(0x0A)
            let handle = try FileHandle(forWritingTo: resultsURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.close()
            print("MacEval \(evalCase.id) \(String(format: "%.1f", elapsed))s")
        }
        await runtime.unloadModelWeights()

        let summary: [String: Any] = [
            "tier": tier.rawValue,
            "model": ["fileName": store.manifest.fileName, "sha256": modelSHA256],
            "evalFile": evalURL.lastPathComponent,
            "evalFileSHA256": try LiteRTModelInstaller.sha256(of: evalURL),
            "loadSeconds": loadSeconds,
            "caseCount": cases.count,
            "failedCount": failed,
            "contextTokens": tier.contextTokens,
            "backend": "gpu",
            "thinkingEnabled": false,
            "physicalMemoryBytes": ProcessInfo.processInfo.physicalMemory,
            "finishedAt": Date.now.ISO8601Format(),
        ]
        let data = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.appending(path: "litert-eval-result.json"), options: .atomic)
    }

    private static func seconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now).components
        return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
    }
}
