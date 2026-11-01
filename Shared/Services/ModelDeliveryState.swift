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
        case .storage: ModelPlatformPolicy.current.storageFailureMessage
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
        case .ready, .development: ""
        case .failed: "Model needs attention"
        }
    }

    /// The ready and development states are silent; there is nothing to report.
    var showsStatus: Bool { self != .ready && self != .development }

    /// Model work can't run until the person chooses to download (or re-download) the model.
    var needsInstall: Bool {
        switch self {
        case .notInstalled, .failed: true
        default: false
        }
    }

    /// The model is on its way: Model Controls show it loading and Model Tasks show progress.
    var isDownloading: Bool {
        switch self {
        case .waiting, .downloading, .paused, .verifying: true
        default: false
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
    private static var states: [String: ModelDeliveryState] = [:]

    /// The one state for a pack: E4B's is `shared`; other packs (the Mac's larger models, which
    /// download when chosen rather than at install) get their own on first use.
    static func state(for pack: AngroveModelAssetPack) -> ModelDeliveryState {
        if pack == .e4b { return shared }
        if let existing = states[pack.id] { return existing }
        let state = ModelDeliveryState(pack: pack, prepare: preparation(for: pack))
        states[pack.id] = state
        return state
    }

    nonisolated private static func preparation(for pack: AngroveModelAssetPack) -> @Sendable () async throws -> Void {
        {
            guard let delivery = AppleHostedModelDelivery.delivery(for: pack.manifest) else {
                throw LiteRTModelStoreError.modelMissing
            }
            _ = try await delivery.prepareModel(manifest: pack.manifest)
        }
    }
    private(set) var phase: ModelDeliveryPhase = .checking
    let pack: AngroveModelAssetPack
    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored private let prepare: @Sendable () async throws -> Void

    init(pack: AngroveModelAssetPack = .e4b, prepare: @escaping @Sendable () async throws -> Void = {
        _ = try await AppleHostedModelDelivery.shared.prepareModel()
    }) {
        self.pack = pack
        self.prepare = prepare
    }

    func update(_ phase: ModelDeliveryPhase) { self.phase = phase }

    func refreshAvailability() async {
        guard preparation == nil, phase == .checking else { return }
        if ModelPlatformPolicy.current.hasLocalCopy(pack.manifest) { phase = .development; return }
        let pack = self.pack
        let available = await Task.detached(priority: .utility) {
            AppleHostedModelAssets.isAvailableLocally(pack)
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
