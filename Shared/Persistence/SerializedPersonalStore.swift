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
    private var preferenceStores: [ObjectIdentifier: UserDefaults] = [:]
    /// Writes refused while the phone was locked. The cache keeps their values; unlocking retries.
    private var deferredWrites: [String: () -> Void] = [:]
    // Confined to queue. Unlock/foreground retries remain immediate; disk-space and other
    // transient failures also retry without requiring a protected-data notification.
    private var retryTask: DispatchWorkItem?
    private var retryDelay: TimeInterval = 1

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
           let value = try? store.attachmentStore.decoder().decode(type, from: data) {
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

    func save<Value: Codable>(_ value: Value, key: String, store: InsightTreeLocalStateFileStore, retrying revision: UUID? = nil) {
        let id = cacheKey(key, store: store)
        let path = store.url(for: key).path
        enqueueWrite(
            id: id,
            replacingRevision: revision,
            publish: { [self] in values[id] = value },
            write: { [self] in
                try PerformanceTrace.measure("Tree State Save") { try store.save(value, key: key) }
                _ = lock.withLock { warmedFiles.removeValue(forKey: path) }
            },
            discardUnreadable: { [self] isNewest in
                if isNewest { values.removeValue(forKey: id) }
                warmedFiles.removeValue(forKey: path)
            },
            retry: { [self] marker in save(value, key: key, store: store, retrying: marker) }
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
        replacingRevision: UUID?,
        publish: @escaping () -> Void,
        write: @escaping () throws -> Void,
        discardUnreadable: @escaping (_ isNewest: Bool) -> Void,
        retry: @escaping (UUID) -> Void
    ) {
        let marker = UUID()
        let accepted = lock.withLock {
            // A retry extracted before a newer save or reset must never publish its old value.
            if let replacingRevision, revisions[id] != replacingRevision { return false }
            publish()
            pending[id] = marker
            revisions[id] = marker
            deferredWrites.removeValue(forKey: id)
            return true
        }
        guard accepted else { return }
        queue.async { [self] in
            guard lock.withLock({ pending[id] == marker }) else { return }
            do {
                try write()
            } catch where !PersonalDataProtection.isIntegrityFailure(error) {
                lock.withLock { if revisions[id] == marker { deferredWrites[id] = { retry(marker) } } }
                scheduleRetry()
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

    private func scheduleRetry() {
        guard retryTask == nil else { return }
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            retryTask = nil
            if lock.withLock({ self.deferredWrites.isEmpty }) { retryDelay = 1; return }
            retryDeferredWrites()
        }
        retryTask = task
        queue.asyncAfter(deadline: .now() + retryDelay, execute: task)
        retryDelay = min(retryDelay * 2, 60)
    }

    /// Preferences retain their existing encrypted representation while serialization and
    /// cryptography run on the same ordered worker as other personal saves.
    func loadPreference<Value: Codable>(_ type: Value.Type, key: String, preferences: PrivatePreferences = .standard) -> Value? {
        guard !PersonalDataProtection.isBlocked else { return nil }
        let id = "codable-preference:\(ObjectIdentifier(preferences.defaults)):\(key)"
        lock.withLock { preferenceStores[ObjectIdentifier(preferences.defaults)] = preferences.defaults }
        if let cached = lock.withLock({ values[id] as? Value }) { return cached }
        let generation = lock.withLock { (epoch, revisions[id]) }
        let loaded: Value? = queue.sync {
            do {
                guard let data = try preferences.read(key) as? Data else { return nil }
                return try preferences.decoder(for: key).decode(type, from: data)
            } catch { PersonalDataProtection.report(error); return nil }
        }
        return lock.withLock {
            guard epoch == generation.0, revisions[id] == generation.1 else { return values[id] as? Value }
            if let loaded { values[id] = loaded }
            return loaded
        }
    }

    func savePreference<Value: Codable>(_ value: Value, key: String, preferences: PrivatePreferences = .standard, retrying revision: UUID? = nil) {
        guard !PersonalDataProtection.isBlocked else { return }
        let id = "codable-preference:\(ObjectIdentifier(preferences.defaults)):\(key)"
        lock.withLock { preferenceStores[ObjectIdentifier(preferences.defaults)] = preferences.defaults }
        enqueueWrite(id: id, replacingRevision: revision,
            publish: { [self] in values[id] = value },
            write: { try preferences.writeEncoded(value, key: key) },
            discardUnreadable: { [self] isNewest in if isNewest { values.removeValue(forKey: id) } },
            retry: { [self] marker in savePreference(value, key: key, preferences: preferences, retrying: marker) })
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

    func saveSeeds(_ seeds: [String: [LocalInsightTreeSeed]], store: LocalInsightTreeSeedFileStore, retrying revision: UUID? = nil) {
        let id = seedsCacheKey(store)
        enqueueWrite(
            id: id,
            replacingRevision: revision,
            publish: { [self] in values[id] = seeds },
            write: { try PerformanceTrace.measure("Conversation Seed Save") { try store.save(seeds) } },
            discardUnreadable: { [self] isNewest in if isNewest { values.removeValue(forKey: id) } },
            retry: { [self] marker in saveSeeds(seeds, store: store, retrying: marker) }
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

    func setString(_ value: String, for key: String, retrying revision: UUID? = nil) {
        enqueueWrite(
            id: "preference:\(key)",
            replacingRevision: revision,
            publish: { [self] in preferenceValues[key] = value },
            write: {
                try PrivatePreferences.standard.write(value, key: key)
            },
            discardUnreadable: { _ in },
            retry: { [self] marker in setString(value, for: key, retrying: marker) }
        )
    }

    /// A barrier used before reset/recovery so previous writes cannot recreate removed stores.
    func invalidate() {
        queue.sync {
            retryTask?.cancel()
            retryTask = nil
            retryDelay = 1
            lock.withLock { epoch &+= 1; values.removeAll(); warmedFiles.removeAll(); preferenceValues.removeAll(); preferenceStores.removeAll(); pending.removeAll(); revisions.removeAll(); deferredWrites.removeAll() }
        }
    }

    func flush() async {
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }
}
