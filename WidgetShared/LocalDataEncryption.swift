import CryptoKit
import Foundation
import Security

nonisolated enum LocalDataEncryptionError: LocalizedError {
    case keychain(OSStatus)
    case missingKey
    case invalidKey
    case invalidEnvelope
    /// Writes are paused after an integrity failure until startup validation succeeds again.
    case storageClosed

    var errorDescription: String? {
        switch self {
        case .missingKey: "The encryption key is missing. Restore the app together with its Keychain from an encrypted device backup. Your saved files have been preserved."
        case .keychain: "Your encrypted data is temporarily unavailable. Unlock your iPhone and try again."
        case .invalidKey, .invalidEnvelope: "Your encrypted data could not be verified. Your saved files have been preserved."
        case .storageClosed: "Saving is paused until your encrypted data can be verified. Your saved files have been preserved."
        }
    }
}

/// Versioned authenticated encryption. The context prevents swapping ciphertext between stores.
/// Keys are never stored beside the data, synchronized, logged, or embedded in the app binary.
nonisolated struct LocalDataCipher {
    static let family = Data("ANGROVE-ENC\u{0}".utf8)
    static let header = Data("ANGROVE-ENC\u{0}1\u{0}".utf8)
    static let personalService = "com.angrove.personal-data.v1"
    static let personal = LocalDataCipher { create in
        try LocalDataKeychain.key(service: personalService, create: create)
    }
    static let widget = LocalDataCipher { create in
        try LocalDataKeychain.key(
            service: "com.angrove.widget-data.v1",
            accessGroup: "group.com.ryanbaltodano.Aquinas-iOS",
            accessible: kSecAttrAccessibleAfterFirstUnlock,
            create: create
        )
    }

    let keyProvider: (_ create: Bool) throws -> SymmetricKey

    static func isEncrypted(_ data: Data) -> Bool { data.starts(with: family) }

    func seal(_ data: Data, context: String) throws -> Data {
        let box = try AES.GCM.seal(data, using: keyProvider(true), authenticating: Data(context.utf8))
        guard let combined = box.combined else { throw LocalDataEncryptionError.invalidEnvelope }
        return Self.header + combined
    }

    func open(_ data: Data, context: String) throws -> Data {
        guard data.starts(with: Self.header) else { throw LocalDataEncryptionError.invalidEnvelope }
        let box = try AES.GCM.SealedBox(combined: data.dropFirst(Self.header.count))
        return try AES.GCM.open(box, using: keyProvider(false), authenticating: Data(context.utf8))
    }
}

nonisolated enum LocalDataKeychain {
    // Serializes creation within a process; errSecDuplicateItem handles app/extension races.
    private static let lock = NSLock()

    static func key(
        service: String,
        accessGroup: String? = nil,
        accessible: CFString = kSecAttrAccessibleWhenUnlocked,
        create: Bool
    ) throws -> SymmetricKey {
        try lock.withLock {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "encryption-key",
                kSecAttrSynchronizable as String: false,
            ]
            if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
            var lookup = query
            lookup[kSecReturnData as String] = true
            lookup[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(lookup as CFDictionary, &result)
            if status == errSecSuccess {
                guard let bytes = result as? Data, bytes.count == 32 else {
                    throw LocalDataEncryptionError.invalidKey
                }
                return SymmetricKey(data: bytes)
            }
            guard status == errSecItemNotFound else { throw LocalDataEncryptionError.keychain(status) }
            guard create else { throw LocalDataEncryptionError.missingKey }
            let newKey = SymmetricKey(size: .bits256)
            query[kSecValueData as String] = newKey.withUnsafeBytes { Data($0) }
            query[kSecAttrAccessible as String] = accessible
            let added = SecItemAdd(query as CFDictionary, nil)
            if added == errSecDuplicateItem {
                let retry = SecItemCopyMatching(lookup as CFDictionary, &result)
                guard retry == errSecSuccess, let bytes = result as? Data, bytes.count == 32 else {
                    throw LocalDataEncryptionError.keychain(retry)
                }
                return SymmetricKey(data: bytes)
            }
            guard added == errSecSuccess else { throw LocalDataEncryptionError.keychain(added) }
            return newKey
        }
    }

    /// Deletes an unusable key so a fresh start can create a new one. Only called after the
    /// person chooses to set their unreadable data aside.
    static func remove(service: String, accessGroup: String? = nil) throws {
        try lock.withLock {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "encryption-key",
                kSecAttrSynchronizable as String: false,
            ]
            if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw LocalDataEncryptionError.keychain(status)
            }
        }
    }
}
