import Foundation
import Testing
@testable import Aquinas_iOS

@Suite("LiteRT probe harness and model override")
struct LiteRTProbeHarnessTests {
    private static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    @Test("No override flag resolves to no override")
    func noFlagResolvesToNil() throws {
        #expect(
            try LiteRTModelOverride.resolvedModelURL(
                arguments: ["Aquinas-iOS", "--litert-probe"],
                documentsDirectory: nil
            ) == nil
        )
    }

    @Test("An absolute model path resolves to that file")
    func absolutePathResolves() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "candidate.litertlm")
        try Data([0, 1, 2, 3]).write(to: fileURL)

        let resolved = try LiteRTModelOverride.resolvedModelURL(
            arguments: ["--litert-model-path", fileURL.path],
            documentsDirectory: nil
        )
        #expect(resolved?.path == fileURL.path)
    }

    @Test("A Documents model name resolves inside Documents")
    func documentNameResolves() throws {
        let documents = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: documents) }
        try Data([0, 1]).write(to: documents.appending(path: "candidate.litertlm"))

        let resolved = try LiteRTModelOverride.resolvedModelURL(
            arguments: ["--litert-model-document", "candidate.litertlm"],
            documentsDirectory: documents
        )
        #expect(resolved?.path == documents.appending(path: "candidate.litertlm").path)
    }

    @Test("Missing override files are rejected in both flag forms")
    func missingFilesAreRejected() throws {
        let documents = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: documents) }
        let missingPath = documents.appending(path: "absent.litertlm").path

        #expect(throws: LiteRTModelOverrideError.fileMissing(missingPath)) {
            try LiteRTModelOverride.resolvedModelURL(
                arguments: ["--litert-model-path", missingPath],
                documentsDirectory: documents
            )
        }
        #expect(throws: LiteRTModelOverrideError.fileMissing(missingPath)) {
            try LiteRTModelOverride.resolvedModelURL(
                arguments: ["--litert-model-document", "absent.litertlm"],
                documentsDirectory: documents
            )
        }
    }

    @Test("Ambiguous, relative, empty, and path-like override values are rejected")
    func invalidOverrideValuesAreRejected() {
        #expect(throws: LiteRTModelOverrideError.conflictingFlags) {
            try LiteRTModelOverride.resolvedModelURL(
                arguments: [
                    "--litert-model-path", "/tmp/a.litertlm",
                    "--litert-model-document", "a.litertlm"
                ],
                documentsDirectory: nil
            )
        }
        #expect(throws: LiteRTModelOverrideError.relativePath("models/a.litertlm")) {
            try LiteRTModelOverride.resolvedModelURL(
                arguments: ["--litert-model-path", "models/a.litertlm"],
                documentsDirectory: nil
            )
        }
        #expect(throws: LiteRTModelOverrideError.missingValue(flag: "--litert-model-path")) {
            try LiteRTModelOverride.resolvedModelURL(
                arguments: ["--litert-model-path"],
                documentsDirectory: nil
            )
        }
        #expect(throws: LiteRTModelOverrideError.invalidDocumentName("../a.litertlm")) {
            try LiteRTModelOverride.resolvedModelURL(
                arguments: ["--litert-model-document", "../a.litertlm"],
                documentsDirectory: URL(filePath: "/tmp")
            )
        }
    }

    @Test("The override store is pinned to the file with a derived manifest")
    func overrideStoreDerivesManifest() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "candidate.litertlm")
        try Data([0, 1, 2, 3, 4]).write(to: fileURL)

        let store = try #require(
            try AquinasApplicationRuntime.developmentOverrideModelStore(
                arguments: ["--litert-model-path", fileURL.path],
                documentsDirectory: nil,
                isDebugBuild: true
            )
        )
        #expect(store.manifest.fileName == "candidate.litertlm")
        #expect(store.manifest.byteCount == 5)
        #expect(store.manifest.sha256 == LiteRTModelOverride.developmentSHA256)
        #expect(try store.installedModelURL().path == fileURL.path)
    }

    @Test("Release builds ignore the model override flags")
    func releaseIgnoresOverride() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "candidate.litertlm")
        try Data([0]).write(to: fileURL)

        #expect(
            try AquinasApplicationRuntime.developmentOverrideModelStore(
                arguments: ["--litert-model-path", fileURL.path],
                documentsDirectory: nil,
                isDebugBuild: false
            ) == nil
        )
        // A bad value must not even be inspected when the override is compiled out.
        #expect(
            try AquinasApplicationRuntime.developmentOverrideModelStore(
                arguments: ["--litert-model-path", "relative"],
                documentsDirectory: nil,
                isDebugBuild: false
            ) == nil
        )
    }

    @MainActor
    @Test("A multi-turn fixture becomes the app's transcript shape")
    func fixtureParsesToTranscript() throws {
        let json = """
        {
          "turns": [
            { "role": "user", "text": "Can mercy conflict with justice?" },
            { "role": "assistant", "text": "They can seem to." }
          ],
          "question": "What's the capital of Portugal?",
          "personality": "scholarly"
        }
        """
        let context = try LiteRTProbeFixture.parse(Data(json.utf8)).conversationContext()
        #expect(context.transcript == [
            .user("Can mercy conflict with justice?", nil, []),
            .text("They can seem to."),
            .user("What's the capital of Portugal?", nil, [])
        ])
        #expect(context.personality == .scholarly)
    }

    @MainActor
    @Test("A single-question fixture needs no prior turns")
    func fixtureWithoutTurns() throws {
        let fixture = try LiteRTProbeFixture.parse(Data(#"{"question":"What is prudence?"}"#.utf8))
        #expect(try fixture.conversationContext().transcript == [.user("What is prudence?", nil, [])])
    }

    @MainActor
    @Test("Malformed fixtures are rejected with a specific reason")
    func malformedFixturesAreRejected() {
        #expect(throws: LiteRTProbeFixtureError.self) {
            try LiteRTProbeFixture.parse(Data("{ not json".utf8))
        }
        #expect(throws: LiteRTProbeFixtureError.self) {
            try LiteRTProbeFixture.parse(Data(#"{"turns":[]}"#.utf8))
        }
        #expect(throws: LiteRTProbeFixtureError.unknownRole("system")) {
            try LiteRTProbeFixture.parse(
                Data(#"{"turns":[{"role":"system","text":"x"}],"question":"q"}"#.utf8)
            )
        }
        #expect(throws: LiteRTProbeFixtureError.emptyTurn(index: 0)) {
            try LiteRTProbeFixture.parse(
                Data(#"{"turns":[{"role":"user","text":"  "}],"question":"q"}"#.utf8)
            )
        }
        #expect(throws: LiteRTProbeFixtureError.emptyQuestion) {
            try LiteRTProbeFixture.parse(Data(#"{"question":" "}"#.utf8))
        }
        #expect(throws: LiteRTProbeFixtureError.unknownPersonality("pirate")) {
            try LiteRTProbeFixture.parse(
                Data(#"{"question":"q","personality":"pirate"}"#.utf8)
            )
        }
    }

    @Test("Raw probe defaults to greedy production sampling at 2,048 tokens")
    func rawProbeDefaults() throws {
        let options = try LiteRTRawProbeOptions.parse(["--litert-probe"])
        #expect(options.contextTokens == 2_048)
        #expect(!options.sampled)
        #expect(options.question == "What is prudence?")
        #expect(options.sampling.topK == LiteRTSampling.conversation.topK)
        #expect(options.sampling.temperature == 0)
        #expect(!options.benchmark)
    }

    @Test("Raw probe flags set context, question, and the explicit sampled mode")
    func rawProbeFlags() throws {
        let options = try LiteRTRawProbeOptions.parse([
            "--litert-probe-context", "4096",
            "--litert-probe-raw-question", "What is natural law?",
            "--litert-probe-sampled",
            "--litert-probe-cpu",
            "--litert-probe-benchmark"
        ])
        #expect(options.contextTokens == 4_096)
        #expect(options.question == "What is natural law?")
        #expect(options.sampled)
        #expect(options.sampling.temperature == 0.2)
        #expect(options.sampling.seed == 7)
        #expect(options.usesCPU)
        #expect(options.benchmark)
    }

    @Test("Raw probe supports load-only, hold, question-file, and system-message runs")
    func rawProbeScreenFlags() throws {
        let defaults = try LiteRTRawProbeOptions.parse([])
        #expect(!defaults.loadOnly)
        #expect(defaults.holdSeconds == 0)
        #expect(defaults.questionFile == nil)
        #expect(defaults.systemMessage == LiteRTRawProbeOptions.defaultSystemMessage)

        let options = try LiteRTRawProbeOptions.parse([
            "--litert-probe-load-only",
            "--litert-probe-hold-seconds", "60",
            "--litert-probe-raw-question-file", "prefill-4k.txt",
            "--litert-probe-system-message", "Summarize the passage."
        ])
        #expect(options.loadOnly)
        #expect(options.holdSeconds == 60)
        #expect(options.questionFile == "prefill-4k.txt")
        #expect(options.systemMessage == "Summarize the passage.")
        #expect(throws: LiteRTRawProbeOptionsError.invalidHold("-1")) {
            try LiteRTRawProbeOptions.parse(["--litert-probe-hold-seconds", "-1"])
        }
    }

    @Test("Raw probe rejects conflicting samplers and invalid contexts")
    func rawProbeRejectsInvalidFlags() {
        #expect(throws: LiteRTRawProbeOptionsError.conflictingSamplers) {
            try LiteRTRawProbeOptions.parse(["--litert-probe-greedy", "--litert-probe-sampled"])
        }
        #expect(throws: LiteRTRawProbeOptionsError.invalidContext("0")) {
            try LiteRTRawProbeOptions.parse(["--litert-probe-context", "0"])
        }
        #expect(throws: LiteRTRawProbeOptionsError.invalidContext("")) {
            try LiteRTRawProbeOptions.parse(["--litert-probe-context"])
        }
    }
}
