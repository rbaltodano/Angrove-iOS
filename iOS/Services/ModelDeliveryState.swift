import Foundation
import Observation

nonisolated enum ModelDeliveryFailure: Equatable, Sendable {
    case network, storage, integrity, unavailable, other

    static func classify(_ error: Error, depth: Int = 0) -> Self {
        guard depth < 8 else { return .other }
        if let error = error as? LiteRTModelStoreError {
            switch error {
            case .invalidModelSize, .invalidModelDigest, .missingVerificationReceipt: return .integrity
            default: return .unavailable
            }
        }
        let error = error as NSError
        if (error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError)
            || (error.domain == NSPOSIXErrorDomain && error.code == 28) { return .storage }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error {
            let reason = classify(underlying, depth: depth + 1)
            if reason != .other { return reason }
        }
        if error.domain == NSURLErrorDomain { return .network }
        return .other
    }

    var message: LocalizedStringResource {
        switch self {
        case .network: "The model download was interrupted. Check your connection and try again."
        case .storage: "There isn’t enough space to download the model. Free up storage in iPhone Settings, then retry. Installation may need more space than the 3.66 GB model file."
        case .integrity: "The downloaded model didn’t pass its integrity check. It won’t be used. Retry to check the installed pack again. If this continues, contact support."
        case .unavailable: "The model pack isn’t available yet. Check your connection and retry. If this continues, contact support."
        case .other: "The model couldn’t be prepared. Retry, or contact support if this continues."
        }
    }
}

nonisolated enum ModelDeliveryPhase: Equatable, Sendable {
    case checking, notInstalled, available, waiting, downloading(completed: Int64, total: Int64)
    case paused, verifying, ready, development, failed(ModelDeliveryFailure)

    var title: LocalizedStringResource {
        switch self {
        case .checking: "Checking model"
        case .notInstalled: "Model not downloaded"
        case .available: "Model downloaded"
        case .waiting: "Waiting for download"
        case .downloading: "Downloading model"
        case .paused: "Download paused"
        case .verifying: "Verifying model"
        case .ready: "Model ready"
        case .development: ""
        case .failed: "Model needs attention"
        }
    }

    var isBusy: Bool {
        switch self {
        case .checking, .waiting, .downloading, .paused, .verifying: true
        default: false
        }
    }

    var fractionCompleted: Double? {
        guard case let .downloading(completed, total) = self, total > 0 else { return nil }
        return min(1, max(0, Double(completed) / Double(total)))
    }
}

/// Both Settings and Model Tasks observe the state reported by the same delivery actor used by
/// the process-scoped runtime. Opening/closing a view never cancels an essential asset download.
@MainActor @Observable
final class ModelDeliveryState {
    static let shared = ModelDeliveryState()
    private(set) var phase: ModelDeliveryPhase = .checking
    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored private let prepare: @Sendable () async throws -> Void

    init(prepare: @escaping @Sendable () async throws -> Void = {
        _ = try await AppleHostedModelDelivery.shared.prepareModel()
    }) {
        self.prepare = prepare
    }

    func update(_ phase: ModelDeliveryPhase) { self.phase = phase }

    func refreshAvailability() async {
        guard preparation == nil, phase == .checking else { return }
#if DEBUG
        if LiteRTModelStore().hasInstalledModel() { phase = .development; return }
#endif
        let available = await Task.detached(priority: .utility) {
            AppleHostedModelAssets.isAvailableLocally()
        }.value
        guard phase == .checking else { return }
        phase = available ? .available : .notInstalled
    }

    func retry() {
        guard preparation == nil else { return }
        phase = .waiting
        preparation = Task {
            defer { preparation = nil }
            do {
                try await prepare()
                phase = .ready
            } catch is CancellationError {
                phase = .notInstalled
            } catch {
                phase = .failed(.classify(error))
            }
        }
    }
}
