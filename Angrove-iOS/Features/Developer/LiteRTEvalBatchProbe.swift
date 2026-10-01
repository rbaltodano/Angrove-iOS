//
//  LiteRTEvalBatchProbe.swift
//  Angrove-iOS
//

import Foundation

/// `--litert-eval-batch <file>`: runs every case of a frozen eval-set JSONL file (plan C8)
/// through the production `LiteRTAngroveModel` with one loaded runtime, as a user would meet it.
/// Each case's result is appended to `Documents/litert-eval-results.jsonl` as soon as it
/// finishes, so an interrupted run keeps what it produced; `Documents/litert-eval-result.json`
/// is written last as the completion marker. Pair with `--litert-record-generations` to keep
/// each case's raw output (needed for link validity).
@MainActor
enum LiteRTEvalBatchProbe {
    private struct EvalCase: Decodable {
        let id: String
        let turns: [LiteRTProbeFixture.Turn]
        let question: String
    }

    struct CaseResult: Encodable {
        let id: String
        let seconds: Double
        let text: String
        let keyTerms: [String]
        let evidenceBasis: String?
        /// Native generations this case triggered; 0 means a verified grounded answer (or an
        /// abstention) was returned without generating.
        let generationCount: Int?
        let firstGenerationIndex: Int?
        let error: String?
    }

    struct Summary: Encodable {
        let runID: String?
        let startedAt: String
        var finishedAt: String?
        let device: LiteRTProbeReport.Device
        let launchArguments: [String]
        let evalFile: String
        var evalFileSHA256: String?
        var model: LiteRTProbeReport.Model?
        let usesCPU: Bool
        var loadSeconds: Double?
        var caseCount = 0
        var failedCount = 0
        var activation: LiteRTProbeReport.Activation?
        var error: String?
    }

    static func run(modelURL: URL, evalFile: String) async {
        let arguments = ProcessInfo.processInfo.arguments
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let usesCPU = arguments.contains("--litert-probe-cpu")
        var summary = Summary(
            runID: LiteRTProbeArguments.value(after: "--litert-probe-run-id", in: arguments),
            startedAt: Date.now.ISO8601Format(),
            device: .current,
            launchArguments: arguments,
            evalFile: evalFile,
            usesCPU: usesCPU
        )
        let resultsURL = documents?.appending(path: "litert-eval-results.jsonl")
        if let resultsURL {
            FileManager.default.createFile(atPath: resultsURL.path, contents: nil)
        }
        let byteCount = (try? modelURL.resourceValues(forKeys: [.fileSizeKey]))?
            .fileSize.map(Int64.init) ?? 0
        summary.model = .init(path: modelURL.path, byteCount: byteCount)
        do {
            let evalURL = try LiteRTModelOverride.resolvedInputURL(
                evalFile,
                documentsDirectory: documents
            )
            summary.evalFileSHA256 = try LiteRTModelInstaller.sha256(of: evalURL)
            let only = LiteRTProbeArguments.value(after: "--litert-eval-ids", in: arguments)
                .map { Set($0.split(separator: ",").map(String.init)) }
            let cases = try String(contentsOf: evalURL, encoding: .utf8)
                .split(separator: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { try JSONDecoder().decode(EvalCase.self, from: Data($0.utf8)) }
                .filter { only?.contains($0.id) ?? true }

            let runtime = LiteRTAngroveRuntime(
                modelStore: try LiteRTModelOverride.developmentStore(for: modelURL)
            )
            if usesCPU {
#if DEBUG
                await runtime.configureEvidenceExperimentCPU()
#endif
            }
#if DEBUG
            if arguments.contains("--litert-eval-sampled") {
                await runtime.configureEvidenceConversationSampling(
                    LiteRTSampling(topK: 40, topP: 0.95, temperature: 0.2, seed: 7, isStructured: false)
                )
            }
#endif
            let clock = ContinuousClock.now
            try await runtime.loadModelWeights()
            summary.loadSeconds = seconds(since: clock)
            let model = LiteRTAngroveModel(
                runtime: runtime,
                groundingProvider: try MiniLMGroundingProvider()
            )

            for evalCase in cases {
                let result = await run(evalCase, model: model)
                summary.caseCount += 1
                if result.error != nil { summary.failedCount += 1 }
                if let resultsURL { append(result, to: resultsURL) }
            }
        } catch {
            summary.error = String(reflecting: error)
        }
        summary.model?.sha256 = await Task.detached(priority: .userInitiated) {
            (try? LiteRTModelInstaller.sha256(of: modelURL)) ?? "unreadable"
        }.value
        try? await Task.sleep(for: .milliseconds(300))
        summary.activation = LiteRTProbeLogCapture.shared.activation()
        summary.finishedAt = Date.now.ISO8601Format()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let documents, let data = try? encoder.encode(summary) {
            try? data.write(to: documents.appending(path: "litert-eval-result.json"), options: .atomic)
        }
    }

    private static func run(_ evalCase: EvalCase, model: LiteRTAngroveModel) async -> CaseResult {
        var transcript: [ChatBlock] = evalCase.turns.map { turn in
            turn.role == "assistant" ? .text(turn.text) : .user(turn.text, nil, [])
        }
        transcript.append(.user(evalCase.question, nil, []))
#if DEBUG
        let before = LiteRTGenerationRecorder.shared.startedCount
#endif
        let clock = ContinuousClock.now
        let response = await model.respond(
            to: ConversationContext(transcript: transcript),
            thinkingEnabled: false,
            onUpdate: { _ in }
        )
        let elapsed = seconds(since: clock)
#if DEBUG
        let after = LiteRTGenerationRecorder.shared.startedCount
        let generationCount: Int? = LiteRTGenerationRecorder.isEnabled ? after - before : nil
        let firstIndex: Int? = LiteRTGenerationRecorder.isEnabled && after > before ? before : nil
#else
        let generationCount: Int? = nil
        let firstIndex: Int? = nil
#endif
        let failed = response.text.contains("on-device Angrove model couldn't complete")
            || response.text.contains("couldn't reach the local Angrove backend")
            || response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return CaseResult(
            id: evalCase.id,
            seconds: elapsed,
            text: response.text,
            keyTerms: response.keyTerms.map(\.displayText),
            evidenceBasis: response.evidenceBasis.map { String(describing: $0) },
            generationCount: generationCount,
            firstGenerationIndex: firstIndex,
            error: failed ? "local generation failed" : nil
        )
    }

    private static func append(_ result: CaseResult, to url: URL) {
        guard var line = try? JSONEncoder().encode(result),
              let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        line.append(0x0A)
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line)
    }

    private static func seconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now).components
        return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
    }
}
