//
//  LiteRTGenerationRecorder.swift
//  Angrove-iOS
//

#if DEBUG
import Foundation

/// DEBUG-only record of every native generation: the exact prompt LiteRT-LM renders (preface and
/// message, from the runtime's own template), the sampler, and the raw output or error. Enabled
/// only by `--litert-record-generations`; it writes encrypted JSON lines to
/// `Documents/litert-generations.jsonl`. It exists so integration diagnostics can tell a template
/// or parsing failure from a model failure (E4B migration plan, C6) without changing production
/// behavior.
nonisolated final class LiteRTGenerationRecorder: @unchecked Sendable {
    static let shared = LiteRTGenerationRecorder()
    static let isEnabled = ProcessInfo.processInfo.arguments.contains(
        "--litert-record-generations"
    )

    struct Sampling: Encodable {
        let topK: Int
        let topP: Float
        let temperature: Float
        let seed: Int
        let isStructured: Bool
    }

    struct Entry: Encodable {
        let index: Int
        let startedAt: String
        let sampling: Sampling
        let systemInstruction: String
        let message: String
        let initialMessageCount: Int
        let renderedPreface: String?
        let renderedMessage: String?
        let renderError: String?
        var output: String?
        var error: String?
        var seconds: Double?
    }

    private let lock = NSLock()
    private var nextIndex = 0
    private var open: [Int: (entry: Entry, start: ContinuousClock.Instant)] = [:]
    private let fileURL: URL? = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
    ).first?.appending(path: "litert-generations.jsonl")

    private init() {}

    /// How many generations have started so far; brackets one caller's generations.
    var startedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return nextIndex
    }

    func begin(
        sampling: Sampling,
        systemInstruction: String,
        message: String,
        initialMessageCount: Int,
        renderedPreface: String?,
        renderedMessage: String?,
        renderError: String?
    ) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let index = nextIndex
        nextIndex += 1
        open[index] = (
            Entry(
                index: index,
                startedAt: Date.now.ISO8601Format(),
                sampling: sampling,
                systemInstruction: systemInstruction,
                message: message,
                initialMessageCount: initialMessageCount,
                renderedPreface: renderedPreface,
                renderedMessage: renderedMessage,
                renderError: renderError
            ),
            .now
        )
        return index
    }

    func finish(_ index: Int, output: String?, error: Error?) {
        lock.lock()
        guard let removed = open.removeValue(forKey: index) else {
            lock.unlock()
            return
        }
        lock.unlock()
        var entry = removed.entry
        let start = removed.start
        let duration = start.duration(to: .now).components
        entry.output = output
        entry.error = error.map { String(reflecting: $0) }
        entry.seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        append(entry)
    }

    private func append(_ entry: Entry) {
        guard let fileURL,
              var line = try? JSONEncoder().encode(entry) else { return }
        line.append(0x0A)
        lock.lock()
        defer { lock.unlock() }
        do {
            var contents = FileManager.default.fileExists(atPath: fileURL.path)
                ? try EncryptedPersonalFile.read(fileURL) : Data()
            contents.append(line)
            try EncryptedPersonalFile.write(contents, to: fileURL)
        } catch {
            PersonalDataProtection.report(error, duringWrite: true)
        }
    }
}
#endif
