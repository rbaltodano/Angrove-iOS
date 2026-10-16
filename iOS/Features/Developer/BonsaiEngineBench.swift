#if DEBUG
import Foundation
import UIKit

/// `--bonsai-bench <gguf in Documents>`: llama-bench-style prefill/decode measurements for one
/// Bonsai model across llama.cpp engine settings, one fresh load per setting, with a cool-down
/// between settings. Captures llama.cpp's Metal setup lines (tensor API, flash attention) so we
/// know what actually ran. Writes `Documents/bonsai-bench-result.json` (with `runID` and
/// `finishedAt`, so Angrove-Eval's run-device-probe.sh can wait for it).
@MainActor
enum BonsaiEngineBench {
    private struct Setting: Encodable {
        let name: String
        let engine: LlamaAngroveRuntime.EngineConfiguration
        var loadSeconds: Double?
        var memoryAfterLoad: LiteRTProbeMemory.Sample?
        var runs: [LlamaAngroveRuntime.BenchmarkResult] = []
        var thermalStart = ""
        var thermalEnd = ""
        var engineLog: [String] = []
        var error: String?
    }

    private struct Report: Encodable {
        let runID: String?
        let startedAt: String
        var finishedAt: String?
        let model: String
        let promptTokens: Int
        let generateTokens: Int
        let repeats: Int
        let coolDownSeconds: Double
        var settings: [Setting] = []
    }

    private static let text = """
    Whether charity is the greatest of the theological virtues? Faith, hope, and charity are \
    virtues infused by God that direct the soul to its supernatural end. Faith perfects the \
    intellect by assent to divine truth; hope perfects the will by desire of the good to come; \
    charity unites the soul to God in friendship. Aquinas argues that a virtue is greater the \
    more it attains its object, and that charity attains God as He is in Himself, while faith \
    and hope attain Him as the source of knowledge or of good things to come. The cardinal \
    virtues of prudence, justice, fortitude, and temperance order human acts according to \
    reason, and prudence is the measure of the moral virtues because it applies right reason \
    to action. Law is an ordinance of reason for the common good, promulgated by one who has \
    care of the community. Eternal law is the plan of divine wisdom; natural law is the rational \
    creature's participation in it; human law particularizes natural law for a political \
    community; divine law, given in revelation, directs man to his supernatural end.
    """

    static func run(modelDocument: String) async {
        let arguments = ProcessInfo.processInfo.arguments
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelURL = documents.appending(path: modelDocument)
        let promptTokens = LiteRTProbeArguments.value(after: "--bonsai-bench-prompt", in: arguments).flatMap(Int.init) ?? 1_024
        let generateTokens = LiteRTProbeArguments.value(after: "--bonsai-bench-generate", in: arguments).flatMap(Int.init) ?? 128
        let repeats = 2
        let coolDown = LiteRTProbeArguments.value(after: "--bonsai-bench-cooldown", in: arguments).flatMap(Double.init) ?? 30
        var report = Report(
            runID: LiteRTProbeArguments.value(after: "--litert-probe-run-id", in: arguments),
            startedAt: Date.now.ISO8601Format(), model: modelDocument,
            promptTokens: promptTokens, generateTokens: generateTokens,
            repeats: repeats, coolDownSeconds: coolDown
        )
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }

        typealias Engine = LlamaAngroveRuntime.EngineConfiguration
        let baseline = Engine()
        let settings: [(String, Engine)] = [
            ("baseline-16k-b512-ub512-fa-auto", baseline),
            ("ub256", Engine(batch: 512, microBatch: 256)),
            ("b1024-ub1024", Engine(batch: 1_024, microBatch: 1_024)),
            ("b2048-ub2048", Engine(batch: 2_048, microBatch: 2_048)),
            ("fa-enabled", Engine(flashAttention: .enabled)),
            ("fa-disabled", Engine(flashAttention: .disabled)),
            ("ctx-8k", Engine(contextTokens: 8_192)),
            ("baseline-repeat", baseline),
        ]

        for (index, (name, engine)) in settings.enumerated() {
            if index > 0, coolDown > 0 { try? await Task.sleep(for: .seconds(coolDown)) }
            var setting = Setting(name: name, engine: engine)
            setting.thermalStart = thermalName()
            let runtime = LlamaAngroveRuntime(modelURL: modelURL, engine: engine)
            LlamaEngineLog.start()
            do {
                try await runtime.loadModelWeights()
                setting.loadSeconds = await runtime.lastLoadSeconds
                setting.memoryAfterLoad = LiteRTProbeMemory.sample()
                _ = try await runtime.benchmark(text: text, promptTokens: 64, generateTokens: 8)  // warm-up
                for _ in 0..<repeats {
                    setting.runs.append(try await runtime.benchmark(
                        text: text, promptTokens: promptTokens, generateTokens: generateTokens))
                }
            } catch {
                setting.error = String(describing: error)
            }
            let log = LlamaEngineLog.stop()
            // The full setup log once; afterwards only the lines that differ by setting.
            setting.engineLog = index == 0 ? log : log.filter {
                let lower = $0.lowercased()
                return lower.contains("flash") || lower.contains("tensor") || lower.contains("batch") || lower.contains("n_ctx")
            }
            await runtime.unloadModelWeights()
            setting.thermalEnd = thermalName()
            report.settings.append(setting)
            write(report, to: documents)
        }
        report.finishedAt = Date.now.ISO8601Format()
        write(report, to: documents)
    }

    private static func thermalName() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    private static func write(_ report: Report, to documents: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(report).write(to: documents.appending(path: "bonsai-bench-result.json"), options: .atomic)
    }
}
#endif
