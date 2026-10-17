import CryptoKit
import Foundation
import Security

public nonisolated enum LocalDataEncryptionError: LocalizedError {
    case keychain(OSStatus)
    case missingKey
    case invalidKey
    case invalidEnvelope
    /// Writes are paused after an integrity failure until startup validation succeeds again.
    case storageClosed

    public var errorDescription: String? {
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
public nonisolated struct LocalDataCipher {
    public static let family = Data("ANGROVE-ENC\u{0}".utf8)
    public static let header = Data("ANGROVE-ENC\u{0}1\u{0}".utf8)
    #if os(macOS)
    public static let personalService = "com.angrove.mac-personal-data.v1"
    #else
    public static let personalService = "com.angrove.personal-data.v1"
    #endif
    /// Every personal read and write opens or seals with this key, so it is held in memory while
    /// protected data is available rather than fetched from the Keychain each time. The app purges
    /// it when the device locks (`LocalDataKeychain.purgeCachedKeys()`), so lookups then fail
    /// exactly as an uncached `kSecAttrAccessibleWhenUnlocked` lookup would.
    public static let personal = LocalDataCipher { create in
        try LocalDataKeychain.cachedKey(service: personalService, create: create)
    }
    public static let widget = LocalDataCipher { create in
        try LocalDataKeychain.key(
            service: "com.angrove.widget-data.v1",
            accessGroup: AngroveAppGroup.identifier,
            accessible: kSecAttrAccessibleAfterFirstUnlock,
            create: create
        )
    }

    public let keyProvider: (_ create: Bool) throws -> SymmetricKey

    public init(keyProvider: @escaping (_ create: Bool) throws -> SymmetricKey) {
        self.keyProvider = keyProvider
    }

    public static func isEncrypted(_ data: Data) -> Bool { data.starts(with: family) }

    public func seal(_ data: Data, context: String) throws -> Data {
        let box = try AES.GCM.seal(data, using: keyProvider(true), authenticating: Data(context.utf8))
        guard let combined = box.combined else { throw LocalDataEncryptionError.invalidEnvelope }
        return Self.header + combined
    }

    public func open(_ data: Data, context: String) throws -> Data {
        guard data.starts(with: Self.header) else { throw LocalDataEncryptionError.invalidEnvelope }
        let box = try AES.GCM.SealedBox(combined: data.dropFirst(Self.header.count))
        return try AES.GCM.open(box, using: keyProvider(false), authenticating: Data(context.utf8))
    }
}

public nonisolated enum LocalDataKeychain {
    // Serializes creation within a process; errSecDuplicateItem handles app/extension races.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedKeys: [String: SymmetricKey] = [:]
    /// Advanced by each purge, so a lookup that raced the purge is not cached after it.
    nonisolated(unsafe) private static var cacheGeneration = 0

    /// `key(service:create:)` for the default access group and accessibility, remembered after
    /// the first successful lookup until `purgeCachedKeys()` or `remove(service:)`.
    public static func cachedKey(service: String, create: Bool) throws -> SymmetricKey {
        let (cached, generation) = lock.withLock { (cachedKeys[service], cacheGeneration) }
        if let cached { return cached }
        let key = try key(service: service, create: create)
        lock.withLock { if cacheGeneration == generation { cachedKeys[service] = key } }
        return key
    }

    /// Forgets every cached key. Called when protected data is about to become unavailable.
    public static func purgeCachedKeys() {
        lock.withLock { cachedKeys.removeAll(); cacheGeneration &+= 1 }
    }

    public static func key(
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
            if let accessGroup { query.merge(sharedGroupAttributes(accessGroup)) { $1 } }
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

    /// A Mac app and its widget can only share an item in the data protection keychain; the
    /// file-based login keychain ignores access groups and would ask the widget for permission.
    private static func sharedGroupAttributes(_ accessGroup: String) -> [String: Any] {
        var attributes: [String: Any] = [kSecAttrAccessGroup as String: accessGroup]
        #if os(macOS)
        attributes[kSecUseDataProtectionKeychain as String] = true
        #endif
        return attributes
    }

    /// Deletes an unusable key so a fresh start can create a new one. Only called after the
    /// person chooses to set their unreadable data aside.
    public static func remove(service: String, accessGroup: String? = nil) throws {
        try lock.withLock {
            cachedKeys.removeValue(forKey: service)
            cacheGeneration &+= 1
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "encryption-key",
                kSecAttrSynchronizable as String: false,
            ]
            if let accessGroup { query.merge(sharedGroupAttributes(accessGroup)) { $1 } }
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw LocalDataEncryptionError.keychain(status)
            }
        }
    }
}
