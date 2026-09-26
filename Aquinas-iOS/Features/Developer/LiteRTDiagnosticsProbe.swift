//
//  LiteRTDiagnosticsProbe.swift
//  Aquinas-iOS
//

import Foundation
import UIKit

/// `--litert-diagnostics-probe`: runs every locally generated contract once through the
/// production `LiteRTAquinasModel`, on fixed inputs, and writes
/// `Documents/litert-diagnostics-result.json` (E4B migration plan, C6). Pair it with
/// `--litert-record-generations` so each case's exact rendered prompt and raw output are captured
/// for classifying failures as template/parsing, retrieval, or model.
@MainActor
enum LiteRTDiagnosticsProbe {
    struct CaseResult: Encodable {
        let name: String
        var status = "failed"
        var seconds: Double = 0
        var summary: String?
        var error: String?
    }

    struct Report: Encodable {
        let runID: String?
        let startedAt: String
        var finishedAt: String?
        let device: LiteRTProbeReport.Device
        let launchArguments: [String]
        let recordsGenerations: Bool
        let usesCPU: Bool
        var model: LiteRTProbeReport.Model?
        var loadSeconds: Double?
        var activation: LiteRTProbeReport.Activation?
        var cases: [CaseResult] = []
        var error: String?
    }

    static func run(modelURL: URL) async {
        let arguments = ProcessInfo.processInfo.arguments
        var report = Report(
            runID: LiteRTProbeArguments.value(after: "--litert-probe-run-id", in: arguments),
            startedAt: Date.now.ISO8601Format(),
            device: .current,
            launchArguments: arguments,
            recordsGenerations: arguments.contains("--litert-record-generations"),
            usesCPU: arguments.contains("--litert-probe-cpu")
        )
        let byteCount = (try? modelURL.resourceValues(forKeys: [.fileSizeKey]))?
            .fileSize.map(Int64.init) ?? 0
        report.model = .init(path: modelURL.path, byteCount: byteCount)
        do {
            let runtime = LiteRTAquinasRuntime(
                modelStore: try LiteRTModelOverride.developmentStore(for: modelURL)
            )
            if report.usesCPU {
#if DEBUG
                // Diagnostic only: the simulator's Metal delegate can't run these packages.
                await runtime.configureEvidenceExperimentCPU()
#endif
            }
            let clock = ContinuousClock.now
            try await runtime.loadModelWeights()
            report.loadSeconds = seconds(since: clock)
            let model = LiteRTAquinasModel(
                runtime: runtime,
                fallback: BackendAquinasModel(baseURL: URL(string: "http://127.0.0.1:9")!),
                groundingProvider: try MiniLMGroundingProvider()
            )
            for diagnosticCase in cases(model: model) {
                report.cases.append(await measure(diagnosticCase.name, diagnosticCase.body))
            }
        } catch {
            report.error = String(reflecting: error)
        }
        report.model?.sha256 = await Task.detached(priority: .userInitiated) {
            (try? LiteRTModelInstaller.sha256(of: modelURL)) ?? "unreadable"
        }.value
        try? await Task.sleep(for: .milliseconds(300))
        report.activation = LiteRTProbeLogCapture.shared.activation()
        report.finishedAt = Date.now.ISO8601Format()
        write(report)
    }

    private typealias Body = () async throws -> String

    private static func cases(model: LiteRTAquinasModel) -> [(name: String, body: Body)] {
        let prudence = ConceptDefinition(
            word: "Prudence",
            partOfSpeech: "noun",
            pronunciation: "",
            meaning: "Right reason applied to action: the virtue that deliberates well, judges, and commands what is to be done toward a good end.",
            example: "Prudence chooses the fitting means to justice in this case."
        )
        let justice = ConceptDefinition(
            word: "Justice",
            partOfSpeech: "noun",
            pronunciation: "",
            meaning: "The constant and perpetual will to render to each what is due.",
            example: "Justice requires paying a fair wage."
        )
        let naturalLawAnswer = "Natural law is the rational creature's participation in the eternal law. Its first precept is that good is to be done and pursued and evil avoided, and reason grasps further precepts from the natural inclinations of human beings."
        let naturalLawContext = ConversationContext(transcript: [
            .user("What is natural law?", nil, []),
            .text(naturalLawAnswer)
        ])
        let mercyContext = ConversationContext(transcript: [
            .user("Think carefully about whether mercy can conflict with justice.", nil, []),
            .text("Mercy and justice can seem to conflict, since justice gives each what is due while mercy remits some of what is due. Aquinas holds that mercy does not destroy justice but is a kind of fullness of it."),
            .user("Can you give a concrete example?", nil, [])
        ])
        let image = UploadedFile(name: "probe.png", imageData: probeImagePNG(), rotationDegrees: 0)

        return [
            ("conversation: single turn with key terms (What is natural law?)", {
                describe(await model.respond(
                    to: ConversationContext(transcript: [.user("What is natural law?", nil, [])]),
                    thinkingEnabled: false,
                    onUpdate: { _ in }
                ))
            }),
            ("conversation: multi-turn follow-up (mercy/justice, then example)", {
                describe(await model.respond(to: mercyContext, thinkingEnabled: false, onUpdate: { _ in }))
            }),
            ("conversation: topic shift (mercy/justice, then capital of Portugal)", {
                describe(await model.respond(
                    to: ConversationContext(transcript: Array(mercyContext.transcript.prefix(2))
                        + [.user("What's the capital of Portugal?", nil, [])]),
                    thinkingEnabled: false,
                    onUpdate: { _ in }
                ))
            }),
            ("images: latest turn attaches an image (text-only runtime)", {
                describe(await model.respond(
                    to: ConversationContext(transcript: [
                        .user("What does this picture show about prudence?", nil, [image])
                    ]),
                    thinkingEnabled: false,
                    onUpdate: { _ in }
                ))
            }),
            ("images: image-bearing history, then a text follow-up", {
                describe(await model.respond(
                    to: ConversationContext(transcript: [
                        .user("Here is a diagram of the virtues.", nil, [image]),
                        .text("The diagram places prudence at the center, guiding the other moral virtues."),
                        .user("Why is prudence placed at the center?", nil, [])
                    ]),
                    thinkingEnabled: false,
                    onUpdate: { _ in }
                ))
            }),
            ("structured: contextual definition (prudence in a natural-law conversation)", {
                let definition = try await model.defineTerm("prudence", in: naturalLawContext)
                return "word=\(definition.word) | meaning=\(definition.meaning) | contexts=\(definition.contextualDefinitions.count)"
            }),
            ("structured: node label (labelSubject over four virtues)", {
                try await model.labelSubject(
                    forTitles: ["Prudence", "Justice", "Fortitude", "Temperance"]
                )
            }),
            ("structured: response-driven tree seed (insightTreeSeedCandidate)", {
                guard let seed = try await model.insightTreeSeedCandidate(
                    question: "What is natural law?",
                    response: naturalLawAnswer
                ) else { return "nil (extraction failed)" }
                return "label=\(seed.label) | summary=\(seed.summary)"
            }),
            ("structured: Midpoint (blend prudence and justice, equal weights)", {
                let blends = try await model.blendConceptCandidates(
                    [prudence, justice],
                    weights: [0.5, 0.5]
                )
                return "count=\(blends.count) | " + blends.map { "\($0.word): \($0.meaning)" }
                    .joined(separator: " || ")
            }),
            ("structured: Make Node (generateChildren for prudence; must be exactly 3)", {
                let children = try await model.generateChildren(for: prudence)
                guard children.count == 3 else {
                    throw DiagnosticsError.unexpectedCount(children.count)
                }
                return "count=3 | " + children.map { "\($0.word): \($0.meaning)" }
                    .joined(separator: " || ")
            }),
            ("structured: Question of the Day", {
                let draft = try await model.generateQuestionOfTheDay(
                    from: naturalLawContext,
                    conversationTitle: "Natural law",
                    insights: [prudence, justice]
                )
                return "question=\(draft.question) | reason=\(draft.reasonForAsking) | cited=\(draft.citedInsightTitle ?? "nil")"
            }),
            ("structured: compaction (mercy/justice transcript)", {
                let compacted = await model.compact(mercyContext)
                guard !compacted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw DiagnosticsError.emptyCompaction
                }
                return compacted
            })
        ]
    }

    private enum DiagnosticsError: LocalizedError {
        case unexpectedCount(Int)
        case emptyCompaction

        var errorDescription: String? {
            switch self {
            case let .unexpectedCount(count): "Expected exactly 3 children, got \(count)."
            case .emptyCompaction: "Compaction returned no text."
            }
        }
    }

    private static func measure(_ name: String, _ body: Body) async -> CaseResult {
        var result = CaseResult(name: name)
        let clock = ContinuousClock.now
        do {
            result.summary = try await body()
            result.status = "ok"
        } catch {
            result.error = String(reflecting: error)
        }
        result.seconds = seconds(since: clock)
        return result
    }

    private static func describe(_ response: ModelResponse) -> String {
        let terms = response.keyTerms.map(\.displayText).joined(separator: ", ")
        let basis = response.evidenceBasis.map { String(describing: $0) } ?? "nil"
        return "evidence=\(basis) | keyTerms[\(response.keyTerms.count)]=\(terms) | text=\(response.text)"
    }

    private static func probeImagePNG() -> Data? {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
    }

    private static func write(_ report: Report) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report),
              let documents = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
              ).first else { return }
        try? data.write(
            to: documents.appending(path: "litert-diagnostics-result.json"),
            options: .atomic
        )
    }

    private static func seconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now).components
        return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
    }
}
