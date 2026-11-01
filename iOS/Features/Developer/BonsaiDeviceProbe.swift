#if DEBUG
import Foundation
import LiteRTLM

/// Measures Ternary Bonsai 2 9B on a device without touching the UI. Launch with
/// `--bonsai-9b --bonsai-probe`; the report is written to Documents/Bonsai/probe.json after each
/// step, so a jetsam kill still leaves the steps that finished.
enum BonsaiDeviceProbe {
    static let argument = "--bonsai-probe"

    private struct Step: Encodable {
        let name: String
        let thinking: Bool
        let stats: LlamaAngroveRuntime.GenerationStats?
        let answer: String?
        let thoughtCharacters: Int
        let error: String?
        let memoryAfter: LiteRTProbeMemory.Sample
    }

    private struct Report: Encodable {
        var loadSeconds: Double?
        var memoryBeforeLoad = LiteRTProbeMemory.sample()
        var memoryAfterLoad: LiteRTProbeMemory.Sample?
        var steps: [Step] = []
        var finished = false
    }

    private static let system = "You are Angrove, a learned friend who helps a reader think through ideas carefully. Answer in clear prose."

    private static let prompts: [(name: String, question: String, thinking: Bool)] = [
        ("short", "In two sentences, what did Aquinas mean by the five ways?", false),
        ("long", "Explain the difference between Aristotle's and Plato's views of the forms, with one example each.", false),
        ("thinking", "Is the argument from contingency stronger than the argument from motion? Give your reasoning.", true),
    ]

    private static let conversation: [(name: String, question: String)] = [
        ("app-first-turn", "Give me an overview of Thomas Aquinas."),
        ("app-follow-up", "where do you think Augustine stands in regards to classic philosophy"),
        ("app-second-follow-up", "How did Aquinas use Augustine differently than Aristotle?"),
    ]

    static func run(runtime: LlamaAngroveRuntime) async {
        var report = Report()
        let url = reportURL()
        do {
            try await runtime.loadModelWeights()
            report.loadSeconds = await runtime.lastLoadSeconds
            report.memoryAfterLoad = LiteRTProbeMemory.sample()
        } catch {
            report.steps.append(Step(name: "load", thinking: false, stats: nil, answer: nil, thoughtCharacters: 0,
                                     error: error.localizedDescription, memoryAfter: LiteRTProbeMemory.sample()))
            write(report, to: url)
            return
        }
        write(report, to: url)

        for prompt in prompts {
            let thought = ThoughtBox()
            var answer: String?
            var failure: String?
            var onThought: (@Sendable (String) async -> Void)?
            if prompt.thinking {
                onThought = { text in await thought.set(text) }
            }
            do {
                answer = try await runtime.generate(
                    systemInstruction: system,
                    initialMessages: [],
                    message: Message(prompt.question),
                    sampling: .conversation,
                    onText: nil,
                    onThought: onThought
                )
            } catch {
                failure = error.localizedDescription
            }
            report.steps.append(Step(
                name: prompt.name,
                thinking: prompt.thinking,
                stats: await runtime.lastStats,
                answer: answer,
                thoughtCharacters: await thought.count,
                error: failure,
                memoryAfter: LiteRTProbeMemory.sample()
            ))
            write(report, to: url)
        }
        // The app's full conversation path (system prompt, references, history), first turn
        // then a follow-up — the case that failed when the context was reserved too tightly.
        let model = LiteRTAngroveModel(runtime: runtime)
        var transcript: [ChatBlock] = []
        for (name, question) in conversation {
            transcript.append(.user(question, [], []))
            LiteRTAngroveModel.debugLastResponseError = nil
            let response = await model.respond(to: ConversationContext(transcript: transcript))
            let failed = response.text.hasPrefix("The on-device Angrove model couldn't complete")
            report.steps.append(Step(
                name: name,
                thinking: false,
                stats: await runtime.lastStats,
                answer: response.text,
                thoughtCharacters: 0,
                error: failed ? (LiteRTAngroveModel.debugLastResponseError ?? "failed") : nil,
                memoryAfter: LiteRTProbeMemory.sample()
            ))
            write(report, to: url)
            transcript.append(.text(response.text))
        }

        report.finished = true
        write(report, to: url)
        print("BonsaiDeviceProbe finished: \(url.path)")
    }

    private actor ThoughtBox {
        private(set) var count = 0
        func set(_ text: String) { count = text.count }
    }

    private static func reportURL() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appending(path: "Bonsai")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "probe.json")
    }

    private static func write(_ report: Report, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(report).write(to: url, options: .atomic)
    }
}
#endif
