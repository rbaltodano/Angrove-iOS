//
//  LiteRTEvalBatchProbe.swift
//  Angrove-iOS
//

import Foundation
import UIKit

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
        /// The model's native thought lines when the run enables thinking; empty otherwise.
        let thinking: [String]
        let error: String?
        /// Every Bonsai engine call this case made (audits and retries included).
        var runtimeGenerations: [LlamaAngroveRuntime.GenerationStats]? = nil
        /// Device conditions, so phone runs can be matched and thermal effects seen.
        var device: CaseDevice? = nil
    }

    struct CaseDevice: Encodable {
        /// Seconds from the start of the first case.
        let startOffsetSeconds: Double
        let thermalStateStart: String
        let thermalStateEnd: String
        let batteryLevelStart: Float
        let batteryLevelEnd: Float
        let batteryState: String
        let memoryAfter: LiteRTProbeMemory.Sample
    }

    struct ThermalTransition: Encodable {
        let offsetSeconds: Double
        let state: String
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
        /// `--litert-eval-thinking`: every case runs with the native thought channel on.
        let thinkingEnabled: Bool
        var loadSeconds: Double?
        var caseCount = 0
        var failedCount = 0
        var activation: LiteRTProbeReport.Activation?
        var error: String?
        var engine = "litert"
        var bonsaiSamplingProfile = "notApplicable"
        var conversationPromptStyle = "standard"
        var followUpRouting = "standard"
        var caseGapSeconds = 0.0
        var thermalStateAtStart = ""
        var thermalTransitions: [ThermalTransition] = []
        var memoryAfterLoad: LiteRTProbeMemory.Sample?
    }

    static func run(modelURL: URL, evalFile: String) async {
        let arguments = ProcessInfo.processInfo.arguments
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let usesCPU = arguments.contains("--litert-probe-cpu")
        let thinkingEnabled = Self.thinkingEnabled
        var summary = Summary(
            runID: LiteRTProbeArguments.value(after: "--litert-probe-run-id", in: arguments),
            startedAt: Date.now.ISO8601Format(),
            device: .current,
            launchArguments: arguments,
            evalFile: evalFile,
            usesCPU: usesCPU,
            thinkingEnabled: thinkingEnabled
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

            let runtime: any AngroveTextRuntime
            var bonsaiRuntime: LlamaAngroveRuntime?
            let promptStyleName = LiteRTProbeArguments.value(after: "--litert-eval-prompt-style", in: arguments) ?? "standard"
            guard let promptStyle = LiteRTAngroveModel.ConversationPromptStyle(rawValue: promptStyleName) else {
                throw ProbeOptionError.unknown("--litert-eval-prompt-style \(promptStyleName)")
            }
            let routingName = LiteRTProbeArguments.value(after: "--litert-eval-followup-routing", in: arguments) ?? "standard"
            guard let routing = LiteRTAngroveModel.FollowUpRouting(rawValue: routingName) else {
                throw ProbeOptionError.unknown("--litert-eval-followup-routing \(routingName)")
            }
            summary.conversationPromptStyle = promptStyleName
            summary.followUpRouting = routingName
            if modelURL.pathExtension == "gguf" {
                // A Ternary Bonsai 2 GGUF: the same pipeline through llama.cpp.
                let profileName = LiteRTProbeArguments.value(after: "--bonsai-profile", in: arguments) ?? "caller"
                guard let profile = LlamaAngroveRuntime.SamplingProfile(rawValue: profileName) else {
                    throw ProbeOptionError.unknown("--bonsai-profile \(profileName)")
                }
                let llama = LlamaAngroveRuntime(modelURL: modelURL, samplingProfile: profile, recordsGenerationStats: true)
                bonsaiRuntime = llama
                runtime = llama
                summary.engine = "llama.cpp"
                summary.bonsaiSamplingProfile = profileName
            } else {
                guard promptStyle == .standard else {
                    throw ProbeOptionError.unknown("the compact prompt applies to Bonsai GGUF runs only")
                }
                let liteRT = LiteRTAngroveRuntime(
                    modelStore: try LiteRTModelOverride.developmentStore(for: modelURL)
                )
                if usesCPU {
#if DEBUG
                    await liteRT.configureEvidenceExperimentCPU()
#endif
                }
#if DEBUG
                if arguments.contains("--litert-eval-sampled") {
                    await liteRT.configureEvidenceConversationSampling(
                        LiteRTSampling(topK: 40, topP: 0.95, temperature: 0.2, seed: 7, isStructured: false)
                    )
                }
#endif
                runtime = liteRT
            }
            UIDevice.current.isBatteryMonitoringEnabled = true
            // A long run must not be suspended by auto-lock partway through.
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            let runStart = ContinuousClock.now
            summary.thermalStateAtStart = Self.thermalName(ProcessInfo.processInfo.thermalState)
            let thermalObserver = NotificationCenter.default.addObserver(
                forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    thermalLog.append(ThermalTransition(
                        offsetSeconds: seconds(since: runStart),
                        state: thermalName(ProcessInfo.processInfo.thermalState)
                    ))
                }
            }
            defer { NotificationCenter.default.removeObserver(thermalObserver) }

            let clock = ContinuousClock.now
            try await runtime.loadModelWeights()
            summary.loadSeconds = seconds(since: clock)
            summary.memoryAfterLoad = LiteRTProbeMemory.sample()
            let model = LiteRTAngroveModel(
                runtime: runtime,
                groundingProvider: try MiniLMGroundingProvider(),
                conversationPromptStyle: promptStyle,
                followUpRouting: routing
            )
            // `--litert-eval-case-gap-seconds <n>` spaces cases so workloads can be matched.
            let gap = LiteRTProbeArguments.value(after: "--litert-eval-case-gap-seconds", in: arguments)
                .flatMap(Double.init) ?? 0
            summary.caseGapSeconds = gap
            let caseStart = ContinuousClock.now
            _ = await bonsaiRuntime?.takeGenerationStats()

            for (index, evalCase) in cases.enumerated() {
                if index > 0, gap > 0 { try? await Task.sleep(for: .seconds(gap)) }
                let offset = seconds(since: caseStart)
                let thermalStart = Self.thermalName(ProcessInfo.processInfo.thermalState)
                let batteryStart = UIDevice.current.batteryLevel
                var result = await run(evalCase, model: model)
                result.runtimeGenerations = await bonsaiRuntime?.takeGenerationStats()
                result.device = CaseDevice(
                    startOffsetSeconds: offset,
                    thermalStateStart: thermalStart,
                    thermalStateEnd: Self.thermalName(ProcessInfo.processInfo.thermalState),
                    batteryLevelStart: batteryStart,
                    batteryLevelEnd: UIDevice.current.batteryLevel,
                    batteryState: Self.batteryName(UIDevice.current.batteryState),
                    memoryAfter: LiteRTProbeMemory.sample()
                )
                summary.caseCount += 1
                if result.error != nil { summary.failedCount += 1 }
                if let resultsURL { append(result, to: resultsURL) }
            }
            summary.thermalTransitions = thermalLog
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

    private static let thinkingEnabled = ProcessInfo.processInfo.arguments
        .contains("--litert-eval-thinking")

    private enum ProbeOptionError: LocalizedError {
        case unknown(String)
        var errorDescription: String? {
            switch self { case .unknown(let option): "Unsupported probe option: \(option)" }
        }
    }

    private static var thermalLog: [ThermalTransition] = []

    private static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    private static func batteryName(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .charging: "charging"
        case .full: "full"
        case .unplugged: "unplugged"
        case .unknown: "unknown"
        @unknown default: "unknown"
        }
    }

    private static func run(_ evalCase: EvalCase, model: LiteRTAngroveModel) async -> CaseResult {
        var transcript: [ChatBlock] = evalCase.turns.map { turn in
            turn.role == "assistant" ? .text(turn.text) : .user(turn.text, [], [])
        }
        transcript.append(.user(evalCase.question, [], []))
#if DEBUG
        let before = LiteRTGenerationRecorder.shared.startedCount
#endif
        let clock = ContinuousClock.now
        let response = await model.respond(
            to: ConversationContext(transcript: transcript),
            thinkingEnabled: thinkingEnabled,
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
            thinking: response.thinkingSummary,
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
