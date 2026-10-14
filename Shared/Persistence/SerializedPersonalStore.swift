import Foundation

/// The process cache is populated after key validation. Pending replacements are visible to
/// readers immediately; encryption and atomic writes are serialized outside the main actor.
nonisolated final class SerializedPersonalStore: @unchecked Sendable {
    static let shared = SerializedPersonalStore()
    private let queue = DispatchQueue(label: "com.angrove.personal-persistence", qos: .utility)
    private let lock = NSLock()
    private var epoch = 0
    private var values: [String: Any] = [:]
    private var warmedFiles: [String: Data] = [:]
    private var revisions: [String: UUID] = [:]
    private var pending: [String: UUID] = [:]
    private var preferenceValues: [String: String] = [:]
    /// Writes refused while the phone was locked. The cache keeps their values; unlocking retries.
    private var deferredWrites: [String: () -> Void] = [:]

    private func cacheKey(_ key: String, store: InsightTreeLocalStateFileStore) -> String {
        "\(store.rootDirectory.path):\(ObjectIdentifier(store.defaults)):\(key)"
    }

    func load<Value: Codable>(_ type: Value.Type, key: String, store: InsightTreeLocalStateFileStore) -> Value? {
        guard !PersonalDataProtection.isBlocked else { return nil }
        let id = cacheKey(key, store: store)
        if let cached = lock.withLock({ values[id] as? Value }) { return cached }
        let url = store.url(for: key)
        let generation = lock.withLock { (epoch, revisions[id]) }
        if let data = lock.withLock({ warmedFiles[url.path] }),
           let value = try? JSONDecoder().decode(type, from: data) {
            return lock.withLock {
                if epoch != generation.0 || revisions[id] != generation.1 { return values[id] as? Value }
                values[id] = value
                warmedFiles.removeValue(forKey: url.path)
                return value
            }
        }
        // Compatibility for first use outside the startup gate (including isolated tests).
        let value = queue.sync { store.load(type, key: key) }
        return lock.withLock {
            if epoch != generation.0 || revisions[id] != generation.1 { return values[id] as? Value }
            if let value { values[id] = value }
            return value
        }
    }

    func save<Value: Codable>(_ value: Value, key: String, store: InsightTreeLocalStateFileStore) {
        let id = cacheKey(key, store: store)
        let path = store.url(for: key).path
        enqueueWrite(
            id: id,
            publish: { [self] in values[id] = value },
            write: { [self] in
                try PerformanceTrace.measure("Tree State Save") { try store.save(value, key: key) }
                _ = lock.withLock { warmedFiles.removeValue(forKey: path) }
            },
            discardUnreadable: { [self] isNewest in
                if isNewest { values.removeValue(forKey: id) }
                warmedFiles.removeValue(forKey: path)
            },
            retry: { [self] in save(value, key: key, store: store) }
        )
    }

    /// Publishes a value to readers immediately, then writes it on `queue` unless a newer write
    /// for `id` supersedes it first. `publish` and `discardUnreadable` run under `lock`;
    /// `discardUnreadable` receives whether this was still the newest value.
    ///
    /// A write the locked phone refused stays readable and is retried by
    /// `retryDeferredWrites()`. An integrity failure closes storage.
    private func enqueueWrite(
        id: String,
        publish: @escaping () -> Void,
        write: @escaping () throws -> Void,
        discardUnreadable: @escaping (_ isNewest: Bool) -> Void,
        retry: @escaping () -> Void
    ) {
        let marker = UUID()
        lock.withLock { publish(); pending[id] = marker; revisions[id] = marker }
        queue.async { [self] in
            guard lock.withLock({ pending[id] == marker }) else { return }
            do {
                try write()
            } catch where !PersonalDataProtection.isIntegrityFailure(error) {
                lock.withLock { if revisions[id] == marker { deferredWrites[id] = retry } }
                PersonalDataProtection.report(error, duringWrite: true)
            } catch {
                lock.withLock { discardUnreadable(revisions[id] == marker) }
                PersonalDataProtection.report(error, duringWrite: true)
            }
            lock.withLock { if pending[id] == marker { pending.removeValue(forKey: id) } }
        }
    }

    /// Called when protected data becomes available again.
    func retryDeferredWrites() {
        let retries = lock.withLock {
            let retries = Array(deferredWrites.values)
            deferredWrites.removeAll()
            return retries
        }
        retries.forEach { $0() }
    }

    func loadSeeds(store: LocalInsightTreeSeedFileStore) -> [String: [LocalInsightTreeSeed]] {
        guard !PersonalDataProtection.isBlocked else { return [:] }
        let id = seedsCacheKey(store)
        if let cached = lock.withLock({ values[id] as? [String: [LocalInsightTreeSeed]] }) { return cached }
        let generation = lock.withLock { (epoch, revisions[id]) }
        let loaded = queue.sync { store.load() }
        return lock.withLock {
            if epoch != generation.0 || revisions[id] != generation.1 {
                return values[id] as? [String: [LocalInsightTreeSeed]] ?? [:]
            }
            values[id] = loaded
            return loaded
        }
    }

    func saveSeeds(_ seeds: [String: [LocalInsightTreeSeed]], store: LocalInsightTreeSeedFileStore) {
        let id = seedsCacheKey(store)
        enqueueWrite(
            id: id,
            publish: { [self] in values[id] = seeds },
            write: { try PerformanceTrace.measure("Conversation Seed Save") { try store.save(seeds) } },
            discardUnreadable: { [self] isNewest in if isNewest { values.removeValue(forKey: id) } },
            retry: { [self] in saveSeeds(seeds, store: store) }
        )
    }

    private func seedsCacheKey(_ store: LocalInsightTreeSeedFileStore) -> String {
        "seeds:\(store.fileURL.path):\(ObjectIdentifier(store.defaults))"
    }

    func preload(root: URL) {
        queue.sync {
            var files: [String: Data] = [:]
            if let paths = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) {
                for case let url as URL in paths where url.pathExtension == "json" {
                    if let data = try? EncryptedPersonalFile.read(url) { files[url.path] = data }
                }
            }
            lock.withLock { epoch &+= 1; values.removeAll(); warmedFiles = files }
        }
    }

    func preloadPreferences() {
        queue.sync {
            var strings: [String: String] = [:]
            for key in PrivatePreferences.standard.defaults.dictionaryRepresentation().keys where PrivatePreferences.protects(key) {
                if let value = PrivatePreferences.standard.string(forKey: key) { strings[key] = value }
            }
            lock.withLock { preferenceValues = strings }
        }
    }

    func string(for key: String, defaultValue: String) -> String {
        if let value = lock.withLock({ preferenceValues[key] }) { return value }
        return PrivatePreferences.standard.string(forKey: key) ?? defaultValue
    }

    func setString(_ value: String, for key: String) {
        enqueueWrite(
            id: "preference:\(key)",
            publish: { [self] in preferenceValues[key] = value },
            write: {
                guard !PersonalDataProtection.isBlocked else { return }
                try PrivatePreferences.standard.write(value, key: key)
            },
            discardUnreadable: { _ in },
            retry: { [self] in setString(value, for: key) }
        )
    }

    /// A barrier used before reset/recovery so previous writes cannot recreate removed stores.
    func invalidate() {
        queue.sync { lock.withLock { epoch &+= 1; values.removeAll(); warmedFiles.removeAll(); preferenceValues.removeAll(); pending.removeAll(); revisions.removeAll(); deferredWrites.removeAll() } }
    }

    func flush() async {
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }
}
