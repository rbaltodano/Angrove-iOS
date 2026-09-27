#if DEBUG
import Foundation
import UIKit

/// C9 uses the process-scoped app model and queue. Native prefill boundaries are not
/// exposed by the production conversation API; never substitute stream callbacks for them.
@MainActor
enum LiteRTSustainedProbe {
    static let shortQuestion = "In one sentence, what is prudence?"
    static let longQuestion = "How can justice and mercy work together when someone repeatedly does wrong? Answer in at most 180 words."

    static func run(showAnswer: @escaping (String) -> Void) async {
        let args = ProcessInfo.processInfo.arguments
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let runID = LiteRTProbeArguments.value(after: "--litert-probe-run-id", in: args) ?? "missing"
        var result: [String: Any] = [
            "runID": runID, "startedAt": Date.now.ISO8601Format(), "launchArguments": args,
            "backend": "gpu", "contextTokens": 4096, "sampler": "production greedy",
            "nativePrefillStart": NSNull(), "nativePrefillEnd": NSNull(),
            "prefillUnavailableReason": "Production conversation API exposes no prefill boundary callbacks; benchmark mode is disabled.",
            "device": UIDevice.current.model, "os": UIDevice.current.systemVersion,
            "thermalStart": ProcessInfo.processInfo.thermalState.rawValue
        ]
        func save() {
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: docs.appending(path: "litert-sustained-result.json"), options: .atomic)
            }
        }
        UIDevice.current.isBatteryMonitoringEnabled = true
        result["batteryState"] = UIDevice.current.batteryState.rawValue
        result["batteryLevel"] = UIDevice.current.batteryLevel
        save()
        do {
            guard Bundle.main.bundleIdentifier == "com.ryanbaltodano.Aquinas-iOS.ModelProbe" else {
                throw ProbeError.unsafeBundle
            }
            guard ProcessInfo.processInfo.thermalState == .nominal else { throw ProbeError.notNominal }
            let override = try LiteRTModelOverride.resolvedModelURL(arguments: args, documentsDirectory: docs)
            let store = try override.map { try LiteRTModelOverride.developmentStore(for: $0) } ?? LiteRTModelStore()
            let url = try store.installedModelURL()
            result["modelPath"] = url.path
            result["modelBytes"] = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            let cache = try store.cacheDirectory()
            result["cachePath"] = cache.path
            result["cacheFilesBefore"] = (try? FileManager.default.subpathsOfDirectory(atPath: cache.path)) ?? []
            if args.contains("--litert-c9-cold") {
                guard LiteRTLifecycleTrace.shared.inFlightKinds().isEmpty else { throw ProbeError.nativeBusy }
                try FileManager.default.removeItem(at: cache)
                try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            }
            let app = AquinasApplicationRuntime.shared
            guard app.isOnDevice else { throw ProbeError.noModel }
            var samples: [[String: Any]] = []
            let sampler = Task { @MainActor in
                while !Task.isCancelled {
                    LiteRTLifecycleTrace.shared.record("c9-sample", ["thermal": ProcessInfo.processInfo.thermalState.rawValue])
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            defer { sampler.cancel() }
            let count = args.contains("--litert-c9-twenty-turns") ? 21 : 1
            let question = args.contains("--litert-c9-long") ? longQuestion : shortQuestion
            for turn in 0..<count {
                let start = ProcessInfo.processInfo.systemUptime
                let box = RequestResult()
                LiteRTLifecycleTrace.shared.record("c9-request-accepted", ["turn": turn, "uptime": start])
                app.modelTasks.enqueue(kind: .userQuestion(branchID: UUID(), responseIndex: 1)) {
                    let response = await app.model.respond(
                        to: ConversationContext(transcript: [.user(question, nil, [])]),
                        thinkingEnabled: false,
                        onUpdate: { update in
                            if case let .responseText(text) = update, !text.isEmpty {
                                showAnswer(text)
                                let now = ProcessInfo.processInfo.systemUptime
                                if box.firstVisible == nil { box.firstVisible = now }
                                box.lastVisible = now
                                LiteRTLifecycleTrace.shared.record("c9-ui-answer-delivered", ["uptime": now, "characters": text.count])
                            }
                        }
                    )
                    box.text = response.text
                    box.metadataComplete = ProcessInfo.processInfo.systemUptime
                    box.done = true
                }
                while !box.done, ProcessInfo.processInfo.systemUptime - start < 600 {
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard box.done else { throw ProbeError.timeout }
                let memory = LiteRTProbeMemory.sample()
                let row: [String: Any] = [
                    "turn": turn, "warmup": count > 1 && turn == 0, "question": question,
                    "acceptedUptime": start,
                    "firstVisibleSeconds": box.firstVisible.map { $0 - start } as Any? ?? NSNull(),
                    "answerCompleteSeconds": box.lastVisible.map { $0 - start } as Any? ?? NSNull(),
                    "metadataCompleteSeconds": box.metadataComplete - start,
                    "text": box.text, "words": box.text.split(whereSeparator: \.isWhitespace).count,
                    "thermal": ProcessInfo.processInfo.thermalState.rawValue,
                    "peakPhysFootprintBytes": memory.peakPhysFootprintBytes as Any? ?? NSNull(),
                    "succeeded": box.firstVisible != nil && !box.text.contains("couldn't complete")
                ]
                samples.append(row)
                result["samples"] = samples
                save()
            }
            result["modelSHA256"] = try await Task.detached(priority: .utility) {
                try LiteRTModelInstaller.sha256(of: url)
            }.value
            result["status"] = "completed"
            result["cacheFilesAfter"] = (try? FileManager.default.subpathsOfDirectory(atPath: cache.path)) ?? []
        } catch {
            result["status"] = "error"
            result["error"] = String(describing: error)
        }
        result["finishedAt"] = Date.now.ISO8601Format()
        save()
    }

    private final class RequestResult {
        var done = false
        var firstVisible: TimeInterval?
        var lastVisible: TimeInterval?
        var metadataComplete: TimeInterval = 0
        var text = ""
    }
    private enum ProbeError: Error { case unsafeBundle, notNominal, nativeBusy, noModel, timeout }
}

/// Observes the existing retrieval call without changing its inputs or results.
nonisolated struct LiteRTC9GroundingObserver: AquinasGroundingProviding {
    let base: any AquinasGroundingProviding
    func references(for question: String, limit: Int) -> [AquinasGroundingReference] {
        let references = base.references(for: question, limit: limit)
        LiteRTLifecycleTrace.shared.record("c9-retrieval-complete", [
            "uptime": ProcessInfo.processInfo.systemUptime, "count": references.count
        ])
        return references
    }
}
#endif
