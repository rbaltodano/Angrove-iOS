//
//  LiteRTModelOverride.swift
//  Angrove-iOS
//

import Foundation

nonisolated enum LiteRTModelOverrideError: LocalizedError, Sendable, Equatable {
    case conflictingFlags
    case missingValue(flag: String)
    case relativePath(String)
    case invalidDocumentName(String)
    case documentsUnavailable
    case fileMissing(String)

    var errorDescription: String? {
        switch self {
        case .conflictingFlags:
            "Pass either --litert-model-path or --litert-model-document, not both."
        case let .missingValue(flag):
            "\(flag) needs a value."
        case let .relativePath(path):
            "--litert-model-path must be an absolute path: \(path)"
        case let .invalidDocumentName(name):
            "A Documents file name cannot contain a path: \(name)"
        case .documentsUnavailable:
            "The app's Documents directory is unavailable."
        case let .fileMissing(path):
            "No file exists at \(path)."
        }
    }
}

/// The one resolver behind the diagnostic model override, shared by the device probe and the
/// DEBUG app runtime so both load exactly the same file for the same launch arguments. It only
/// resolves and validates the location; `developmentStore(for:)` builds the store the runtime
/// consumes. The E4B migration plan (C3) requires this to be a single code path.
nonisolated enum LiteRTModelOverride {
    static let pathFlag = "--litert-model-path"
    static let documentFlag = "--litert-model-document"
    static let developmentSHA256 = "development-override"

    /// Returns `nil` when neither override flag is present.
    static func resolvedModelURL(
        arguments: [String],
        documentsDirectory: URL?
    ) throws -> URL? {
        let path = try value(after: pathFlag, in: arguments)
        let document = try value(after: documentFlag, in: arguments)
        switch (path, document) {
        case (nil, nil):
            return nil
        case (.some, .some):
            throw LiteRTModelOverrideError.conflictingFlags
        case let (.some(path), nil):
            guard path.hasPrefix("/") else {
                throw LiteRTModelOverrideError.relativePath(path)
            }
            return try existingFile(URL(filePath: path))
        case let (nil, .some(name)):
            return try documentFile(named: name, in: documentsDirectory)
        }
    }

    /// Resolves a probe input (such as a fixture) given either an absolute path or a plain
    /// file name in Documents, with the same validation as the model override.
    static func resolvedInputURL(
        _ value: String,
        documentsDirectory: URL?
    ) throws -> URL {
        if value.hasPrefix("/") {
            return try existingFile(URL(filePath: value))
        }
        return try documentFile(named: value, in: documentsDirectory)
    }

    /// A store pinned to the override file. Its manifest is derived from the file itself, so
    /// the size check always passes; the placeholder digest marks it as unverified.
    static func developmentStore(for url: URL) throws -> LiteRTModelStore {
        let byteCount = try url.resourceValues(
            forKeys: [.fileSizeKey]
        ).fileSize.map(Int64.init) ?? 0
        return LiteRTModelStore(
            manifest: LiteRTModelManifest(
                fileName: url.lastPathComponent,
                byteCount: byteCount,
                sha256: developmentSHA256
            ),
            developmentModelURL: url
        )
    }

    private static func value(
        after flag: String,
        in arguments: [String]
    ) throws -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        guard arguments.indices.contains(index + 1) else {
            throw LiteRTModelOverrideError.missingValue(flag: flag)
        }
        let value = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("--") else {
            throw LiteRTModelOverrideError.missingValue(flag: flag)
        }
        return value
    }

    private static func documentFile(
        named name: String,
        in documentsDirectory: URL?
    ) throws -> URL {
        guard !name.contains("/"), name != ".", name != ".." else {
            throw LiteRTModelOverrideError.invalidDocumentName(name)
        }
        guard let documentsDirectory else {
            throw LiteRTModelOverrideError.documentsUnavailable
        }
        return try existingFile(documentsDirectory.appending(path: name))
    }

    private static func existingFile(_ url: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw LiteRTModelOverrideError.fileMissing(url.path)
        }
        return url
    }
}
