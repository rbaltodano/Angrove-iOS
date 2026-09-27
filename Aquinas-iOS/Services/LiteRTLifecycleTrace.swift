//
//  LiteRTLifecycleTrace.swift
//  Aquinas-iOS
//

import Foundation
import LiteRTLM
import os

/// Counts native LiteRT work that is still running and marks each piece with a "Native Call"
/// signpost interval: Swift-side calls, plus what the wrapper reports through
/// `NativeActivityMonitor` (engine and conversation deletes on their own threads, and streams
/// that keep generating after the stall watchdog or a cancellation stopped listening). A new
/// engine load that starts while any of it is running is an overlap (plan C7). DEBUG builds
/// launched with `--litert-lifecycle-trace` also append every event, with memory, to
/// `Documents/litert-lifecycle.jsonl`.
nonisolated final class LiteRTLifecycleTrace: @unchecked Sendable {
    static let shared = LiteRTLifecycleTrace()

    private let lock = NSLock()
    private var inFlight: [UUID: String] = [:]
    private var detachedCounts: [String: Int] = [:]
    private var detachedStates: [String: [OSSignpostIntervalState]] = [:]
    private let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "com.aquinas",
        category: "ModelRuntime"
    )
#if DEBUG
    private let fileURL: URL? = ProcessInfo.processInfo.arguments
        .contains("--litert-lifecycle-trace")
        ? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appending(path: "litert-lifecycle.jsonl")
        : nil
#endif

    /// Runs `operation` as one tracked native call. The count drops only when the native work
    /// actually returns, not when a caller stops waiting for it.
    func tracking<T>(_ kind: String, _ operation: () async throws -> T) async throws -> T {
        let id = UUID()
        let state = signposter.beginInterval("Native Call", id: signposter.makeSignpostID())
        let count = begin(id, kind: kind)
        record("native-begin", ["kind": kind, "inFlight": count])
        defer {
            signposter.endInterval("Native Call", state)
            let remaining = end(id)
            record("native-end", ["kind": kind, "inFlight": remaining])
        }
        return try await operation()
    }

    private init() {
        NativeActivityMonitor.setObserver { [weak self] kind, isBegin in
            self?.detached(kind, isBegin: isBegin)
        }
    }

    /// Native work still running, by kind.
    func inFlightKinds() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let detached = detachedCounts.flatMap { kind, count in
            Array(repeating: kind, count: count)
        }
        return (Array(inFlight.values) + detached).sorted()
    }

    private func detached(_ kind: String, isBegin: Bool) {
        lock.lock()
        detachedCounts[kind] = max(0, (detachedCounts[kind] ?? 0) + (isBegin ? 1 : -1))
        if isBegin {
            detachedStates[kind, default: []].append(
                signposter.beginInterval("Native Call", id: signposter.makeSignpostID())
            )
        } else if let state = detachedStates[kind]?.popLast() {
            signposter.endInterval("Native Call", state)
        }
        let total = inFlight.count + detachedCounts.values.reduce(0, +)
        lock.unlock()
        record(isBegin ? "native-begin" : "native-end", ["kind": kind, "inFlight": total])
    }

    func record(_ event: String, _ fields: [String: Any] = [:]) {
#if DEBUG
        guard let fileURL else { return }
        let memory = LiteRTProbeMemory.sample()
        var line = fields
        line["event"] = event
        line["uptime"] = ProcessInfo.processInfo.systemUptime
        line["at"] = Date.now.ISO8601Format(.iso8601.time(includingFractionalSeconds: true))
        line["physFootprint"] = memory.physFootprintBytes ?? 0
        line["peakPhysFootprint"] = memory.peakPhysFootprintBytes ?? 0
        guard var data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys])
        else { return }
        data.append(0x0A)
        lock.lock()
        defer { lock.unlock() }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
#endif
    }

    private func begin(_ id: UUID, kind: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        inFlight[id] = kind
        return inFlight.count + detachedCounts.values.reduce(0, +)
    }

    private func end(_ id: UUID) -> Int {
        lock.lock()
        defer { lock.unlock() }
        inFlight[id] = nil
        return inFlight.count + detachedCounts.values.reduce(0, +)
    }
}
