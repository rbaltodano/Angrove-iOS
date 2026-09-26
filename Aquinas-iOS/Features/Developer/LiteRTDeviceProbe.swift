//
//  LiteRTDeviceProbe.swift
//  Aquinas-iOS
//

import LiteRTLM
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class LiteRTDeviceProbeModel {
    enum Phase: Equatable {
        case ready
        case locatingModel
        case loadingModel
        case generating
        case completed
        case failed

        var title: LocalizedStringResource {
            switch self {
            case .ready:
                "Ready"
            case .locatingModel:
                "Locating model"
            case .loadingModel:
                "Loading Aquinas"
            case .generating:
                "Generating on device"
            case .completed:
                "Probe passed"
            case .failed:
                "Probe failed"
            }
        }
    }

    private(set) var phase: Phase = .ready
    private(set) var detail = "The probe has not run yet."
    private(set) var response = ""
    private(set) var loadSeconds: Double?
    private(set) var generationSeconds: Double?
    private(set) var modelSizeBytes: Int64?
    private(set) var didStart = false

    private var engine: Engine?
    private var conversation: Conversation?
    private var productionRuntime: LiteRTAquinasRuntime?
    private let launchMemory = LiteRTProbeMemory.sample()

    var copySummary: String {
        let sizeText = modelSizeBytes.map {
            ByteCountFormatStyle(
                style: .file,
                allowedUnits: [.gb],
                spellsOutZero: false,
                includesActualByteCount: false
            ).format($0)
        } ?? "—"
        let loadText = loadSeconds.map { "\($0.formatted(.number.precision(.fractionLength(2))))s" } ?? "—"
        let generationText = generationSeconds.map { "\($0.formatted(.number.precision(.fractionLength(2))))s" } ?? "—"
        return """
        Model size: \(sizeText)
        Cold load: \(loadText)
        Generation: \(generationText)
        Response: \(response)
        """
    }

    var isRunning: Bool {
        switch phase {
        case .locatingModel, .loadingModel, .generating:
            true
        case .ready, .completed, .failed:
            false
        }
    }

    func run() async {
        guard !didStart else { return }
        didStart = true
        LiteRTProbeLogCapture.shared.start()

        if ProcessInfo.processInfo.arguments.contains("--litert-diagnostics-probe") {
            phase = .generating
            detail = "Running every local generation contract once."
            do {
                await LiteRTDiagnosticsProbe.run(modelURL: try Self.locateModel())
                phase = .completed
                detail = "Diagnostics finished; see litert-diagnostics-result.json."
            } catch {
                phase = .failed
                detail = error.localizedDescription
            }
            return
        }

        if ProcessInfo.processInfo.arguments.contains("--litert-quality-probe") {
            await runConversationQualityProbe()
            return
        }

        phase = .locatingModel
        detail = "Looking for the local Aquinas LiteRT-LM package."
        response = ""
        loadSeconds = nil
        generationSeconds = nil
        modelSizeBytes = nil

        let arguments = ProcessInfo.processInfo.arguments
        var report = LiteRTProbeReport(
            mode: "raw",
            arguments: arguments,
            launchMemory: launchMemory
        )
        do {
            let options = try LiteRTRawProbeOptions.parse(arguments)
            let modelURL = try Self.locateModel()
            modelSizeBytes = try modelURL.resourceValues(
                forKeys: [.fileSizeKey]
            ).fileSize.map(Int64.init)
            report.model = .init(path: modelURL.path, byteCount: modelSizeBytes ?? 0)

            let systemMessage = options.systemMessage
            let sampling = options.sampling
            report.settings = .init(
                backend: options.usesCPU ? "cpu" : "gpu",
                contextTokens: options.contextTokens,
                sampler: .init(
                    mode: options.sampled ? "sampled" : "greedy",
                    topK: sampling.topK,
                    topP: sampling.topP,
                    temperature: sampling.temperature,
                    seed: sampling.seed
                ),
                systemMessage: systemMessage,
                benchmarkEnabled: options.benchmark
            )
            var question = options.question
            report.input = .init(question: question, fixturePath: nil, priorTurnCount: 0)
            if let questionFile = options.questionFile {
                let questionURL = try LiteRTModelOverride.resolvedInputURL(
                    questionFile,
                    documentsDirectory: Self.documentsDirectory
                )
                question = try String(contentsOf: questionURL, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !question.isEmpty else { throw LiteRTDeviceProbeError.emptyQuestionFile }
                report.input = .init(
                    question: question,
                    fixturePath: nil,
                    priorTurnCount: 0,
                    questionFilePath: questionURL.path,
                    questionFileSHA256: try LiteRTModelInstaller.sha256(of: questionURL)
                )
            }

            if options.benchmark {
                ExperimentalFlags.optIntoExperimentalAPIs()
                ExperimentalFlags.enableBenchmark = true
            }
            let cacheURL = try Self.cacheDirectory()
            let config = try EngineConfig(
                modelPath: modelURL.path,
                backend: options.usesCPU ? .cpu() : .gpu,
                maxNumTokens: options.contextTokens,
                cacheDir: cacheURL.path
            )
            let engine = Engine(engineConfig: config)
            self.engine = engine

            phase = .loadingModel
            detail = options.usesCPU
                ? "Initializing the checkpoint with the CPU backend."
                : "Initializing the checkpoint with the Metal backend."
            report.memory.beforeLoad = LiteRTProbeMemory.sample()
            let loadClock = ContinuousClock.now
            try await engine.initialize()
            loadSeconds = Self.seconds(since: loadClock)
            report.timing.loadSeconds = loadSeconds
            report.memory.afterLoad = LiteRTProbeMemory.sample()

            if options.loadOnly {
                try await Self.hold(options.holdSeconds, report: &report)
                phase = .completed
                detail = "Aquinas loaded on device (load-only run)."
                report.status = "passed"
                await Self.finish(&report)
                return
            }

            let sampler = try SamplerConfig(
                topK: sampling.topK,
                topP: sampling.topP,
                temperature: sampling.temperature,
                seed: sampling.seed
            )
            let conversation = try await engine.createConversation(
                with: ConversationConfig(
                    systemMessage: Message(systemMessage, role: .system),
                    samplerConfig: sampler
                )
            )
            self.conversation = conversation

            phase = .generating
            detail = "The response is being generated entirely on this device."
            let generationClock = ContinuousClock.now
            let message = try await conversation.sendMessage(
                Message(question)
            )
            generationSeconds = Self.seconds(since: generationClock)
            report.timing.generationSeconds = generationSeconds
            report.memory.afterGeneration = LiteRTProbeMemory.sample()
            if options.benchmark, let info = try? conversation.getBenchmarkInfo() {
                report.timing.timeToFirstTokenSeconds = info.timeToFirstTokenInSecond
                report.timing.prefillTokens = info.lastPrefillTokenCount
                report.timing.decodeTokens = info.lastDecodeTokenCount
                report.timing.prefillTokensPerSecond = info.lastPrefillTokensPerSecond
                report.timing.decodeTokensPerSecond = info.lastDecodeTokensPerSecond
                report.timing.tokenCountSource = "LiteRT-LM BenchmarkInfo (last turn)"
            }
            response = message.toString
            report.response = response
            guard !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LiteRTDeviceProbeError.emptyResponse
            }
            try await Self.hold(options.holdSeconds, report: &report)

            phase = .completed
            detail = "Aquinas loaded and generated a non-empty response on device."
            report.status = "passed"
        } catch {
            phase = .failed
            detail = error.localizedDescription
            report.status = "failed"
            report.error = error.localizedDescription
            report.memory.afterGeneration = report.memory.afterGeneration
                ?? LiteRTProbeMemory.sample()
        }
        await Self.finish(&report)
    }

    private func runConversationQualityProbe() async {
        phase = .locatingModel
        detail = "Looking for the local Aquinas LiteRT-LM package."
        response = ""
        loadSeconds = nil
        generationSeconds = nil
        modelSizeBytes = nil

        let arguments = ProcessInfo.processInfo.arguments
        var report = LiteRTProbeReport(
            mode: "quality",
            arguments: arguments,
            launchMemory: launchMemory
        )
        report.timing.tokenCountSource =
            "unavailable: the production runtime owns and releases the native conversation"
        do {
            let modelURL = try Self.locateModel()
            modelSizeBytes = try modelURL.resourceValues(
                forKeys: [.fileSizeKey]
            ).fileSize.map(Int64.init)
            report.model = .init(path: modelURL.path, byteCount: modelSizeBytes ?? 0)

            let context: ConversationContext
            let fixturePath: String?
            if let fixtureValue = LiteRTProbeArguments.value(
                after: "--litert-probe-fixture",
                in: arguments
            ) {
                let fixtureURL = try LiteRTModelOverride.resolvedInputURL(
                    fixtureValue,
                    documentsDirectory: Self.documentsDirectory
                )
                context = try LiteRTProbeFixture.load(from: fixtureURL).conversationContext()
                fixturePath = fixtureURL.path
            } else {
                let question = LiteRTProbeArguments.value(
                    after: "--litert-probe-question",
                    in: arguments
                ) ?? "How can justice and mercy work together when someone repeatedly does wrong?"
                context = ConversationContext(
                    transcript: [.user(question, nil, [])]
                )
                fixturePath = nil
            }
            let sampling = LiteRTSampling.conversation
            let usesCPU = arguments.contains("--litert-probe-cpu")
            report.settings = .init(
                backend: usesCPU ? "cpu" : "gpu",
                contextTokens: LiteRTAquinasRuntime.maxNumTokens,
                sampler: .init(
                    mode: "production conversation (greedy)",
                    topK: sampling.topK,
                    topP: sampling.topP,
                    temperature: sampling.temperature,
                    seed: sampling.seed
                ),
                systemMessage: nil,
                benchmarkEnabled: false
            )
            if case let .user(question, _, _)? = context.transcript.last {
                report.input = .init(
                    question: question,
                    fixturePath: fixturePath,
                    priorTurnCount: context.transcript.count - 1
                )
            }

            let runtime = LiteRTAquinasRuntime(
                modelStore: try LiteRTModelOverride.developmentStore(for: modelURL)
            )
            productionRuntime = runtime
            if usesCPU {
#if DEBUG
                // Diagnostic only (plan D2): lets the production path run where the Metal
                // delegate can't, such as the simulator's 256 MiB allocation ceiling.
                await runtime.configureEvidenceExperimentCPU()
#else
                throw LiteRTDeviceProbeError.cpuQualityProbeUnavailable
#endif
            }
            phase = .loadingModel
            detail = "Initializing the production Aquinas conversation runtime."
            report.memory.beforeLoad = LiteRTProbeMemory.sample()
            let loadClock = ContinuousClock.now
            try await runtime.loadModelWeights()
            loadSeconds = Self.seconds(since: loadClock)
            report.timing.loadSeconds = loadSeconds
            report.memory.afterLoad = LiteRTProbeMemory.sample()

            let groundingProvider = try MiniLMGroundingProvider()
            let model = LiteRTAquinasModel(
                runtime: runtime,
                fallback: BackendAquinasModel(
                    baseURL: URL(string: "http://127.0.0.1:9")!
                ),
                groundingProvider: groundingProvider
            )

            phase = .generating
            detail = "Testing production answer depth and repetition safeguards."
            let generationClock = ContinuousClock.now
            let result = await model.respond(
                to: context,
                thinkingEnabled: false,
                onUpdate: { _ in }
            )
            generationSeconds = Self.seconds(since: generationClock)
            report.timing.generationSeconds = generationSeconds
            report.memory.afterGeneration = LiteRTProbeMemory.sample()
            response = result.text
            report.response = response
            report.validatedKeyTermCount = result.keyTerms.count
            report.evidenceBasis = result.evidenceBasis.map { String(describing: $0) }
            guard !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LiteRTDeviceProbeError.emptyResponse
            }
            if response.contains("couldn't reach the local Aquinas backend")
                || response.contains("on-device Aquinas model couldn't complete") {
                throw LiteRTDeviceProbeError.productionPathFailed(response)
            }

            phase = .completed
            detail = "The production conversation path completed locally with \(result.keyTerms.count) validated Insight links."
            report.status = "passed"
        } catch {
            phase = .failed
            detail = error.localizedDescription
            report.status = "failed"
            report.error = error.localizedDescription
            report.memory.afterGeneration = report.memory.afterGeneration
                ?? LiteRTProbeMemory.sample()
        }
        await Self.finish(&report)
    }

    /// Keeps the loaded engine (and conversation) resident for `seconds`, then samples memory,
    /// so pressure or jetsam after a large run shows up before the process exits.
    private static func hold(_ seconds: Int, report: inout LiteRTProbeReport) async throws {
        guard seconds > 0 else { return }
        try await Task.sleep(for: .seconds(seconds))
        report.memory.afterHold = LiteRTProbeMemory.sample()
        report.holdSeconds = seconds
    }

    /// Hashes the model (after every timed phase), attaches the captured native log lines, and
    /// writes the report.
    private static func finish(_ report: inout LiteRTProbeReport) async {
        if let path = report.model?.path {
            let url = URL(filePath: path)
            report.model?.sha256 = await Task.detached(priority: .userInitiated) {
                (try? LiteRTModelInstaller.sha256(of: url)) ?? "unreadable"
            }.value
        }
        // Give the stderr reader a moment to drain what the native side just wrote.
        try? await Task.sleep(for: .milliseconds(300))
        report.activation = LiteRTProbeLogCapture.shared.activation()
        report.diagnosticLogLines = LiteRTProbeLogCapture.shared.diagnosticLines()
        report.finishedAt = Date.now.ISO8601Format()
        report.write()
    }

    private static var documentsDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    /// The override flags go through the same resolver the DEBUG app runtime uses; otherwise
    /// the probe looks for the manifest's package where `LiteRTModelStore` would.
    private static func locateModel() throws -> URL {
        if let overrideURL = try LiteRTModelOverride.resolvedModelURL(
            arguments: ProcessInfo.processInfo.arguments,
            documentsDirectory: documentsDirectory
        ) {
            return overrideURL
        }
        let fileManager = FileManager.default
        let fileName = LiteRTModelManifest.aquinas.fileName
        let resourceName = (fileName as NSString).deletingPathExtension
        let resourceExtension = (fileName as NSString).pathExtension
        let candidateURLs = [
            Bundle.main.url(
                forResource: resourceName,
                withExtension: resourceExtension,
                subdirectory: "LocalModels"
            ),
            Bundle.main.url(
                forResource: resourceName,
                withExtension: resourceExtension
            ),
            fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first?.appending(
                path: "Models/\(fileName)"
            )
        ].compactMap { $0 }

        guard let modelURL = candidateURLs.first(
            where: { fileManager.fileExists(atPath: $0.path) }
        ) else {
            throw LiteRTDeviceProbeError.modelMissing
        }
        return modelURL
    }

    private static func cacheDirectory() throws -> URL {
        guard let root = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            throw LiteRTDeviceProbeError.cacheUnavailable
        }
        let directory = root.appending(path: "LiteRTLM")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private static func seconds(
        since start: ContinuousClock.Instant
    ) -> Double {
        let duration = start.duration(to: .now)
        return Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
    }
}

nonisolated enum LiteRTRawProbeOptionsError: LocalizedError, Equatable {
    case conflictingSamplers
    case invalidContext(String)
    case invalidHold(String)

    var errorDescription: String? {
        switch self {
        case .conflictingSamplers:
            "Pass either --litert-probe-greedy or --litert-probe-sampled, not both."
        case let .invalidContext(value):
            "--litert-probe-context needs a positive token count, not \"\(value)\"."
        case let .invalidHold(value):
            "--litert-probe-hold-seconds needs a non-negative whole number, not \"\(value)\"."
        }
    }
}

/// Raw-probe launch flags. Greedy decoding with the production conversation sampler is the
/// default for every gate; the old temperature-0.2 sampler needs an explicit
/// `--litert-probe-sampled`. `--litert-probe-benchmark` reports prefill/decode token counts and
/// rates, but it also switches the engine into LiteRT-LM's benchmark mode (for example
/// `disable_delegate_clustering`), so it is opt-in and recorded in the report.
nonisolated struct LiteRTRawProbeOptions: Equatable {
    static let defaultContextTokens = 2_048
    static let defaultQuestion = "What is prudence?"
    static let defaultSystemMessage = "Answer clearly and in one concise sentence."

    let contextTokens: Int
    let sampled: Bool
    let question: String
    let usesCPU: Bool
    let benchmark: Bool
    /// Stops after the engine loads (plan C5 "load only").
    var loadOnly = false
    var holdSeconds = 0
    /// An absolute path or Documents name whose UTF-8 text replaces `question` (long prefills).
    var questionFile: String?
    var systemMessage = defaultSystemMessage

    var sampling: LiteRTSampling {
        sampled
            ? LiteRTSampling(topK: 40, topP: 0.95, temperature: 0.2, seed: 7, isStructured: false)
            : .conversation
    }

    static func parse(_ arguments: [String]) throws -> Self {
        let greedy = arguments.contains("--litert-probe-greedy")
        let sampled = arguments.contains("--litert-probe-sampled")
        guard !(greedy && sampled) else {
            throw LiteRTRawProbeOptionsError.conflictingSamplers
        }
        var contextTokens = defaultContextTokens
        if arguments.contains("--litert-probe-context") {
            let value = LiteRTProbeArguments.value(
                after: "--litert-probe-context",
                in: arguments
            ) ?? ""
            guard let parsed = Int(value), parsed > 0 else {
                throw LiteRTRawProbeOptionsError.invalidContext(value)
            }
            contextTokens = parsed
        }
        var holdSeconds = 0
        if arguments.contains("--litert-probe-hold-seconds") {
            let value = LiteRTProbeArguments.value(
                after: "--litert-probe-hold-seconds",
                in: arguments
            ) ?? ""
            guard let parsed = Int(value), parsed >= 0 else {
                throw LiteRTRawProbeOptionsError.invalidHold(value)
            }
            holdSeconds = parsed
        }
        var options = Self(
            contextTokens: contextTokens,
            sampled: sampled,
            question: LiteRTProbeArguments.value(
                after: "--litert-probe-raw-question",
                in: arguments
            ) ?? defaultQuestion,
            usesCPU: arguments.contains("--litert-probe-cpu"),
            benchmark: arguments.contains("--litert-probe-benchmark")
        )
        options.loadOnly = arguments.contains("--litert-probe-load-only")
        options.holdSeconds = holdSeconds
        options.questionFile = LiteRTProbeArguments.value(
            after: "--litert-probe-raw-question-file",
            in: arguments
        )
        if let systemMessage = LiteRTProbeArguments.value(
            after: "--litert-probe-system-message",
            in: arguments
        ) {
            options.systemMessage = systemMessage
        }
        return options
    }
}

private enum LiteRTDeviceProbeError: LocalizedError {
    case modelMissing
    case cacheUnavailable
    case emptyResponse
    case productionPathFailed(String)
    case cpuQualityProbeUnavailable
    case emptyQuestionFile

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            "The Aquinas LiteRT-LM model is not installed in this build."
        case .cacheUnavailable:
            "The app could not create a writable LiteRT-LM cache."
        case .emptyResponse:
            "Aquinas initialized but returned an empty response."
        case .productionPathFailed(let message):
            "The production local path failed: \(message)"
        case .cpuQualityProbeUnavailable:
            "The CPU quality probe is available only in Debug builds."
        case .emptyQuestionFile:
            "The raw probe's question file is empty."
        }
    }
}

struct LiteRTDeviceProbeView: View {
    @State private var model = LiteRTDeviceProbeModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LiteRTProbeHeader()
                LiteRTProbeStatus(model: model)
                LiteRTProbeMetrics(
                    modelSizeBytes: model.modelSizeBytes,
                    loadSeconds: model.loadSeconds,
                    generationSeconds: model.generationSeconds
                )
                LiteRTProbeResponse(response: model.response)
                Button {
                    Task {
                        await model.run()
                    }
                } label: {
                    Text(
                        model.isRunning
                            ? "Running…"
                            : model.didStart
                                ? "Probe finished"
                                : "Run device probe"
                    )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.didStart)
                if model.didStart {
                    Button {
                        UIPasteboard.general.string = model.copySummary
                    } label: {
                        Label("Copy results", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(AquinasTheme.Spacing.screenPadding)
        }
        .background(AquinasTheme.Colors.canvas)
        .task {
            guard ProcessInfo.processInfo.arguments.contains(
                "--litert-probe-auto"
            ) else {
                return
            }
            await model.run()
        }
    }
}

private struct LiteRTProbeHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("On-device model probe")
                .font(AquinasTheme.Typography.title)
                .foregroundStyle(AquinasTheme.Colors.headingText)
            Text(
                "This isolated diagnostic loads the fine-tuned Aquinas checkpoint through LiteRT-LM and generates one response entirely on this device or simulator."
            )
            .font(AquinasTheme.Typography.bodyLarge)
            .foregroundStyle(AquinasTheme.Colors.paragraphText)
        }
    }
}

private struct LiteRTProbeStatus: View {
    let model: LiteRTDeviceProbeModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if model.isRunning {
                ProgressView()
            } else {
                Image(
                    systemName: model.phase == .completed
                        ? "checkmark.circle.fill"
                        : model.phase == .failed
                            ? "xmark.circle.fill"
                            : "circle"
                )
                .foregroundStyle(
                    model.phase == .failed
                        ? AquinasTheme.Colors.accentRed
                        : AquinasTheme.Colors.accentGreen
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(model.phase.title)
                    .font(AquinasTheme.Typography.uiSubheading)
                Text(model.detail)
                    .font(AquinasTheme.Typography.body)
                    .foregroundStyle(AquinasTheme.Colors.paragraphText)
            }
        }
        .padding(AquinasTheme.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AquinasTheme.Colors.componentBackground,
            in: RoundedRectangle(
                cornerRadius: AquinasTheme.Spacing.smallCardRadius
            )
        )
    }
}

private struct LiteRTProbeMetrics: View {
    let modelSizeBytes: Int64?
    let loadSeconds: Double?
    let generationSeconds: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Measurements")
                .font(AquinasTheme.Typography.uiSubheading)
            LabeledContent(
                "Model size",
                value: modelSizeBytes.map(Self.formattedBytes) ?? "—"
            )
            LabeledContent(
                "Cold load",
                value: loadSeconds.map(Self.formattedSeconds) ?? "—"
            )
            LabeledContent(
                "Generation",
                value: generationSeconds.map(Self.formattedSeconds) ?? "—"
            )
        }
        .font(AquinasTheme.Typography.body)
    }

    private static func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatStyle(
            style: .file,
            allowedUnits: [.gb],
            spellsOutZero: false,
            includesActualByteCount: false
        ).format(bytes)
    }

    private static func formattedSeconds(_ seconds: Double) -> String {
        seconds.formatted(
            .number.precision(.fractionLength(2))
        ) + " s"
    }
}

private struct LiteRTProbeResponse: View {
    let response: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Response")
                .font(AquinasTheme.Typography.uiSubheading)
            Text(response.isEmpty ? "No response yet." : response)
                .font(AquinasTheme.Typography.bodyLarge)
                .foregroundStyle(AquinasTheme.Colors.paragraphText)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
