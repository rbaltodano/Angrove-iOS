//
//  LiteRTProbeReport.swift
//  Angrove-iOS
//

import Darwin
import Foundation
import os
import UIKit

/// The effective-settings report every probe run writes to `Documents/litert-probe-result.json`
/// (E4B migration plan, C3 step 3). Fields the runtime can't provide stay `nil` rather than
/// being estimated.
struct LiteRTProbeReport: Encodable {
    struct Device: Encodable {
        let modelIdentifier: String
        let systemName: String
        let systemVersion: String
        let isSimulator: Bool
    }

    struct Model: Encodable {
        let path: String
        let byteCount: Int64
        /// Computed from the file's bytes after generation, so hashing never warms the page
        /// cache ahead of the timed load.
        var sha256: String?
    }

    struct Sampler: Encodable {
        let mode: String
        let topK: Int
        let topP: Float
        let temperature: Float
        let seed: Int
    }

    struct Settings: Encodable {
        let backend: String
        let contextTokens: Int
        let sampler: Sampler
        let systemMessage: String?
        let benchmarkEnabled: Bool
    }

    struct Input: Encodable {
        let question: String
        let fixturePath: String?
        let priorTurnCount: Int
        var questionFilePath: String?
        var questionFileSHA256: String?
    }

    struct Activation: Encodable {
        let resolvedType: String?
        let source: String
        let logLines: [String]
    }

    struct Timing: Encodable {
        var loadSeconds: Double?
        var generationSeconds: Double?
        var timeToFirstTokenSeconds: Double?
        var prefillTokens: Int?
        var decodeTokens: Int?
        var prefillTokensPerSecond: Double?
        var decodeTokensPerSecond: Double?
        var tokenCountSource: String
    }

    struct Memory: Encodable {
        var launch: LiteRTProbeMemory.Sample?
        var beforeLoad: LiteRTProbeMemory.Sample?
        var afterLoad: LiteRTProbeMemory.Sample?
        var afterGeneration: LiteRTProbeMemory.Sample?
        var afterHold: LiteRTProbeMemory.Sample?
    }

    let runID: String?
    let mode: String
    var status = "running"
    var error: String?
    let startedAt: String
    var finishedAt: String?
    let device: Device
    let launchArguments: [String]
    var model: Model?
    var settings: Settings?
    var input: Input?
    var activation: Activation?
    var diagnosticLogLines: [String] = []
    var timing = Timing(tokenCountSource: "unavailable")
    var memory = Memory()
    var holdSeconds: Int?
    var response: String?
    var validatedKeyTermCount: Int?
    var evidenceBasis: String?

    init(mode: String, arguments: [String], launchMemory: LiteRTProbeMemory.Sample) {
        self.mode = mode
        runID = LiteRTProbeArguments.value(after: "--litert-probe-run-id", in: arguments)
        startedAt = Date.now.ISO8601Format()
        launchArguments = arguments
        device = Device.current
        memory.launch = launchMemory
    }

    /// Writes the report as the probe's single source of truth, and echoes it to stdout so a
    /// console capture carries the same record.
    func write() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        if let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first {
            try? data.write(
                to: documents.appending(path: "litert-probe-result.json"),
                options: .atomic
            )
        }
        if let text = String(data: data, encoding: .utf8) {
            print("LITERT_PROBE_RESULT_BEGIN\n\(text)\nLITERT_PROBE_RESULT_END")
        }
    }
}

extension LiteRTProbeReport.Device {
    static var current: Self {
        let environment = ProcessInfo.processInfo.environment
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: &systemInfo.machine) { buffer in
            String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return Self(
            modelIdentifier: environment["SIMULATOR_MODEL_IDENTIFIER"] ?? machine,
            systemName: UIDevice.current.systemName,
            systemVersion: UIDevice.current.systemVersion,
            isSimulator: environment["SIMULATOR_DEVICE_NAME"] != nil
        )
    }
}

nonisolated enum LiteRTProbeArguments {
    static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        let value = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

/// Process memory as jetsam sees it: `phys_footprint` (and its lifetime peak) from
/// `task_vm_info`, plus `os_proc_available_memory()`, which is 0 in the simulator.
nonisolated enum LiteRTProbeMemory {
    struct Sample: Encodable, Sendable {
        let physFootprintBytes: UInt64?
        let peakPhysFootprintBytes: Int64?
        let availableMemoryBytes: UInt64
    }

    static func sample() -> Sample {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        let available = UInt64(os_proc_available_memory())
        guard result == KERN_SUCCESS else {
            return Sample(
                physFootprintBytes: nil,
                peakPhysFootprintBytes: nil,
                availableMemoryBytes: available
            )
        }
        return Sample(
            physFootprintBytes: info.phys_footprint,
            peakPhysFootprintBytes: info.ledger_phys_footprint_peak,
            availableMemoryBytes: available
        )
    }
}

/// Tees the process's stderr, where LiteRT-LM's native logging lands, so the report can quote
/// the lines that reveal the resolved activation type and any delegate or kernel fallback.
/// The runtime exposes neither through its Swift API. The full stream is also saved to
/// `Documents/litert-probe-stderr.log`, and everything still reaches the original stderr.
nonisolated final class LiteRTProbeLogCapture: @unchecked Sendable {
    static let shared = LiteRTProbeLogCapture()

    private static let maximumRetainedLines = 20_000
    private static let activationPattern = try! NSRegularExpression(
        pattern: #"\b(FLOAT16|FLOAT32|FP16|FP32|BF16|BFLOAT16|INT8|INT16|F16|F32)\b"#,
        options: [.caseInsensitive]
    )
    private static let diagnosticKeywords = [
        "delegate", "kernel", "metal", "fallback", "rollback", "buffer", "backend", "gpu",
        "error", "failed", "warning"
    ]

    private let lock = NSLock()
    private var lines: [String] = []
    private var started = false

    private init() {}

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        var descriptors: [Int32] = [0, 0]
        guard pipe(&descriptors) == 0 else { return }
        let originalDescriptor = dup(STDERR_FILENO)
        guard originalDescriptor >= 0,
              dup2(descriptors[1], STDERR_FILENO) >= 0 else {
            close(descriptors[0])
            close(descriptors[1])
            return
        }
        close(descriptors[1])
        setvbuf(stderr, nil, _IONBF, 0)
        started = true

        let logFile: FileHandle? = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first.flatMap { documents in
            let url = documents.appending(path: "litert-probe-stderr.log")
            FileManager.default.createFile(atPath: url.path, contents: nil)
            return try? FileHandle(forWritingTo: url)
        }
        let readDescriptor = descriptors[0]
        Thread.detachNewThread { [self] in
            var buffer = [UInt8](repeating: 0, count: 16_384)
            var pending = Data()
            while true {
                let count = read(readDescriptor, &buffer, buffer.count)
                guard count > 0 else { break }
                _ = buffer.withUnsafeBytes {
                    write(originalDescriptor, $0.baseAddress, count)
                }
                let chunk = Data(buffer[0..<count])
                try? logFile?.write(contentsOf: chunk)
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 0x0A) {
                    let line = String(decoding: pending[..<newline], as: UTF8.self)
                    pending.removeSubrange(...newline)
                    append(line)
                }
            }
        }
    }

    /// Lines mentioning activation, and the dtype the engine resolved. The executor settings
    /// dump (`activation_data_type: …`) is authoritative; a section's preference line is only
    /// used when that dump is absent.
    func activation() -> LiteRTProbeReport.Activation {
        let activationLines = snapshot().filter {
            $0.localizedCaseInsensitiveContains("activation")
                || $0.contains("CalculationsPrecision")
        }
        // The GPU "artisan" executor leaves `activation_data_type` unset and states its
        // precision as `CalculationsPrecision::F16` instead.
        let settingsLines = activationLines.filter {
            $0.contains("CalculationsPrecision")
                || ($0.contains("activation_data_type") && !$0.contains("Not set"))
        }
        let resolved = (settingsLines + activationLines).lazy.compactMap { line -> String? in
            let range = NSRange(line.startIndex..., in: line)
            guard let match = Self.activationPattern.firstMatch(in: line, range: range),
                  let tokenRange = Range(match.range(at: 1), in: line) else {
                return nil
            }
            return line[tokenRange].uppercased()
        }.first
        return LiteRTProbeReport.Activation(
            resolvedType: resolved,
            source: !settingsLines.isEmpty
                ? "native executor settings (activation_data_type or CalculationsPrecision, stderr)"
                : activationLines.isEmpty
                    ? "not exposed by the LiteRT-LM Swift API, and no native log line mentioned it"
                    : "native LiteRT-LM preference log line (stderr); no executor settings dump",
            logLines: Array(activationLines.prefix(40))
        )
    }

    func diagnosticLines(limit: Int = 200) -> [String] {
        let matches = snapshot().filter { line in
            let lowered = line.lowercased()
            return Self.diagnosticKeywords.contains { lowered.contains($0) }
        }
        return Array(matches.prefix(limit))
    }

    private func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        guard lines.count < Self.maximumRetainedLines else { return }
        lines.append(line)
    }

    private func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}
