//
//  LiteRTModelInstaller.swift
//  Angrove-iOS
//

import CryptoKit
import Foundation

nonisolated enum LiteRTModelInstallerError: LocalizedError, Sendable {
    case invalidServerResponse

    var errorDescription: String? {
        switch self {
        case .invalidServerResponse:
            "The Angrove model server returned an invalid response."
        }
    }
}

/// Installs an externally hosted model after download. Angrove verifies both size and SHA-256
/// before atomically promoting the temporary file into Application Support.
actor LiteRTModelInstaller {
    private let store: LiteRTModelStore
    private let session: URLSession

    init(
        store: LiteRTModelStore = LiteRTModelStore(),
        session: URLSession = .shared
    ) {
        self.store = store
        self.session = session
    }

    @discardableResult
    func install(from sourceURL: URL) async throws -> URL {
        let (temporaryURL, response) = try await session.download(
            from: sourceURL
        )
        guard let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode else {
            throw LiteRTModelInstallerError.invalidServerResponse
        }

        try store.validateModel(at: temporaryURL)
        let digest = try Self.sha256(of: temporaryURL)
        guard digest == store.manifest.sha256 else {
            throw LiteRTModelStoreError.invalidModelDigest
        }

        let destination = try store.postInstallDestinationURL()
        let fileManager = FileManager.default
        let staged = destination.appendingPathExtension("\(UUID().uuidString).installing")
        defer { try? fileManager.removeItem(at: staged) }
        try fileManager.moveItem(at: temporaryURL, to: staged)
        try Task.checkCancellation()
        try Self.promote(staged: staged, to: destination)

        let receipt = LiteRTModelVerificationReceipt(
            byteCount: store.manifest.byteCount,
            sha256: digest
        )
        let receiptData = try JSONEncoder().encode(receipt)
        try receiptData.write(
            to: store.verificationReceiptURL(for: destination),
            options: .atomic
        )
        return destination
    }

    /// Keep the installed model intact until its verified replacement can land. Both URLs
    /// live in the destination directory, so replacement does not cross filesystem volumes.
    nonisolated static func promote(staged: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staged)
        } else {
            try fileManager.moveItem(at: staged, to: destination)
        }
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            // FileHandle's bridged buffers may remain autoreleased for the whole task.
            // Bound their lifetime: otherwise DEBUG identity logging can retain the entire
            // multi-gigabyte model while inference is also resident (C9 device diagnostics).
            let hasMore = try autoreleasepool {
                guard let data = try handle.read(upToCount: 8 * 1_024 * 1_024),
                      !data.isEmpty else { return false }
                hasher.update(data: data)
                return true
            }
            if !hasMore { break }
        }
        return hasher.finalize().map {
            String(format: "%02x", $0)
        }
        .joined()
    }
}
