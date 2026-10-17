//
//  LiteRTModelStore.swift
//  Angrove-iOS
//

import Foundation

nonisolated enum LiteRTModelStoreError: LocalizedError, Sendable {
    case modelMissing
    case invalidModelSize(expected: Int64, actual: Int64)
    case invalidModelDigest
    case missingVerificationReceipt
    case cacheUnavailable

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            "The Angrove on-device model has not been installed."
        case let .invalidModelSize(expected, actual):
            "The installed Angrove model is incomplete (\(actual) of \(expected) bytes)."
        case .invalidModelDigest:
            "The Angrove model did not pass its integrity check."
        case .missingVerificationReceipt:
            "The downloaded Angrove model has not been verified."
        case .cacheUnavailable:
            "The app could not create the LiteRT model cache."
        }
    }
}

/// Development resolves local artifacts synchronously. Release prepares the pinned Apple-hosted
/// essential asset pack and verifies its bytes before the runtime uses its process-local URL.
nonisolated struct LiteRTModelStore: Sendable {
    let manifest: LiteRTModelManifest
    private let developmentModelURL: URL?

    init(
        manifest: LiteRTModelManifest = .angrove,
        developmentModelURL: URL? = nil
    ) {
        self.manifest = manifest
        self.developmentModelURL = developmentModelURL
    }

    var usesAppleHostedDelivery: Bool {
        developmentModelURL == nil && Bundle.main.object(forInfoDictionaryKey: "BAUsesAppleHosting") as? Bool == true
    }

    func preparedModelURL() async throws -> URL {
        // A verified local copy: development artifacts (both apps), or a Mac set up before Apple
        // hosting. Distribution installs have none and use their pack.
        if ModelPlatformPolicy.current.prefersLocalCopy, let local = try? installedModelURL() { return local }
        guard usesAppleHostedDelivery, let delivery = AppleHostedModelDelivery.delivery(for: manifest) else {
            return try installedModelURL()
        }
        return try await delivery.prepareModel(manifest: manifest)
    }

    func installedModelURL() throws -> URL {
        let fileManager = FileManager.default
        if let developmentModelURL {
            try validateModel(at: developmentModelURL)
            return developmentModelURL
        }
        if let downloaded = applicationSupportModelURL(
            fileManager: fileManager
        ), fileManager.fileExists(atPath: downloaded.path) {
            try validateModel(at: downloaded)
            let receiptURL = verificationReceiptURL(for: downloaded)
            guard let data = try? Data(contentsOf: receiptURL),
                  let receipt = try? JSONDecoder().decode(
                    LiteRTModelVerificationReceipt.self,
                    from: data
                  ),
                  receipt.byteCount == manifest.byteCount,
                  receipt.sha256 == manifest.sha256 else {
                throw LiteRTModelStoreError.missingVerificationReceipt
            }
            return downloaded
        }
        if let bundled = bundledModelURL(),
           fileManager.fileExists(atPath: bundled.path) {
            try validateModel(at: bundled)
            return bundled
        }
        throw LiteRTModelStoreError.modelMissing
    }

    func hasInstalledModel() -> Bool {
        (try? installedModelURL()) != nil
    }

    func cacheDirectory() throws -> URL {
        guard let root = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            throw LiteRTModelStoreError.cacheUnavailable
        }
        var directory = root.appending(path: ModelPlatformPolicy.current.storagePath("LiteRTLM"))
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--litert-sustained-probe"),
           Bundle.main.bundleIdentifier == "com.ryanbaltodano.Aquinas-iOS.ModelProbe" {
            // Keep both arms' caches independent during alternating cold/cached C9 trials.
            directory = root.appending(path: "LiteRTLM-C9").appending(path: manifest.fileName)
        }
#endif
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    func postInstallDestinationURL() throws -> URL {
        guard let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw LiteRTModelStoreError.modelMissing
        }
        let directory = root.appending(path: ModelPlatformPolicy.current.storagePath("Models"))
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appending(path: manifest.fileName)
    }

    func validateModel(at url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            throw LiteRTModelStoreError.modelMissing
        }
        let size = try url.resourceValues(
            forKeys: [.fileSizeKey]
        ).fileSize.map(Int64.init) ?? 0
        guard size == manifest.byteCount else {
            throw LiteRTModelStoreError.invalidModelSize(
                expected: manifest.byteCount,
                actual: size
            )
        }
    }

    func verificationReceiptURL(for modelURL: URL) -> URL {
        modelURL.appendingPathExtension("verified.json")
    }

    private func applicationSupportModelURL(
        fileManager: FileManager
    ) -> URL? {
        if let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            return applicationSupport
                .appending(path: ModelPlatformPolicy.current.storagePath("Models"))
                .appending(path: manifest.fileName)
        }
        return nil
    }

    private func bundledModelURL() -> URL? {
        if let bundled = Bundle.main.url(
            forResource: manifest.fileName.deletingPathExtension,
            withExtension: manifest.fileName.pathExtension,
            subdirectory: "LocalModels"
        ) ?? Bundle.main.url(
            forResource: manifest.fileName.deletingPathExtension,
            withExtension: manifest.fileName.pathExtension
        ) {
            return bundled
        }
        return nil
    }
}

nonisolated struct LiteRTModelVerificationReceipt: Codable, Sendable, Equatable {
    let byteCount: Int64
    let sha256: String
}

private extension String {
    nonisolated var deletingPathExtension: String {
        (self as NSString).deletingPathExtension
    }

    nonisolated var pathExtension: String {
        (self as NSString).pathExtension
    }
}
