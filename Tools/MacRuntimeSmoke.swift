// Opt-in, one-question diagnostic. This is not the Mac app's live model adapter.
// Mirrors the existing iOS raw LiteRT probe; no production prompt or model changes.
import Foundation
import LiteRTLM

@main
struct MacRuntimeSmoke {
    static func main() async {
        guard CommandLine.arguments.count == 5 else {
            fputs("Usage: MacRuntimeSmoke <model-path> <gpu|cpu> <report-directory> <question>\n", stderr)
            exit(2)
        }
        let modelPath = CommandLine.arguments[1]
        let backendName = CommandLine.arguments[2]
        guard let backend = Backend(rawValue: backendName) else { exit(2) }
        let directory = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        let question = CommandLine.arguments[4]
        let systemInstruction = "Answer clearly and in one concise sentence."
        var report: [String: Any] = [
            "status": "starting", "mode": "raw-mac-diagnostic",
            "modelPath": modelPath, "backend": backendName,
            "contextTokens": 4_096, "activationDataTypeOverride": 0,
            "nativeThinking": false, "speculativeDecoding": false,
            "vision": false, "audio": false,
            "topK": 1, "topP": 1, "temperature": 0, "seed": 0,
            "systemInstruction": systemInstruction, "question": question,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "physicalMemoryBytes": ProcessInfo.processInfo.physicalMemory,
            "startedAt": ISO8601DateFormatter().string(from: Date())
        ]
        func save() {
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: directory.appendingPathComponent("report.json"), options: .atomic)
            }
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let cache = directory.appendingPathComponent("cache", isDirectory: true)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            ExperimentalFlags.optIntoExperimentalAPIs()
            ExperimentalFlags.activationDataType = 0
            ExperimentalFlags.enableSpeculativeDecoding = false
            let config = try EngineConfig(modelPath: modelPath, backend: backend, maxNumTokens: 4_096, cacheDir: cache.path)
            let engine = Engine(engineConfig: config)
            report["status"] = "loading"
            save()
            let loadStart = Date()
            try await engine.initialize()
            report["loadSeconds"] = Date().timeIntervalSince(loadStart)
            report["status"] = "creating-conversation"
            save()
            let sampler = try SamplerConfig(topK: 1, topP: 1, temperature: 0, seed: 0)
            let conversation = try await engine.createConversation(with: ConversationConfig(
                systemMessage: Message(systemInstruction, role: .system), samplerConfig: sampler
            ))
            report["status"] = "generating"
            save()
            let generationStart = Date()
            let message = try await conversation.sendMessage(Message(question))
            report["generationSeconds"] = Date().timeIntervalSince(generationStart)
            report["answer"] = message.toString
            report["channels"] = message.channels
            report["status"] = message.toString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "failed-empty" : "completed"
            report["finishedAt"] = ISO8601DateFormatter().string(from: Date())
            save()
            print(message.toString)
            // The diagnostic process ends after saving its report. Native runtime objects
            // have the same teardown implementation as the production vendored wrapper.
        } catch {
            report["status"] = "failed"
            report["error"] = String(reflecting: error)
            report["finishedAt"] = ISO8601DateFormatter().string(from: Date())
            save()
            fputs("Mac runtime check failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
