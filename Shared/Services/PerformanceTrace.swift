import Foundation
import os

/// Low-overhead intervals without prompt text, personal content, or file payloads.
nonisolated enum PerformanceTrace {
    private static let signposter = OSSignposter(subsystem: "com.angrove.performance", category: "AppPipeline")

    static func measure<Value>(_ name: StaticString, _ operation: () throws -> Value) rethrows -> Value {
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID())
        defer { signposter.endInterval(name, state) }
        return try operation()
    }

    static func measure<Value>(_ name: StaticString, _ operation: () async throws -> Value) async rethrows -> Value {
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID())
        defer { signposter.endInterval(name, state) }
        return try await operation()
    }
}
