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
        let marker = UUID()
        lock.withLock { values[id] = value; pending[id] = marker; revisions[id] = marker }
        queue.async { [self] in
            guard lock.withLock({ pending[id] == marker }) else { return }
            do {
                try PerformanceTrace.measure("Tree State Save") { try store.save(value, key: key) }
                _ = lock.withLock { warmedFiles.removeValue(forKey: store.url(for: key).path) }
            } catch where !PersonalDataProtection.isIntegrityFailure(error) {
                deferWrite(id: id, marker: marker) { [self] in save(value, key: key, store: store) }
                PersonalDataProtection.report(error, duringWrite: true)
            } catch {
                lock.withLock {
                    if revisions[id] == marker { values.removeValue(forKey: id) }
                    warmedFiles.removeValue(forKey: store.url(for: key).path)
                }
                PersonalDataProtection.report(error, duringWrite: true)
            }
            lock.withLock { if pending[id] == marker { pending.removeValue(forKey: id) } }
        }
    }

    /// Keeps the newest unsaved value readable and queues it for `retryDeferredWrites()`.
    private func deferWrite(id: String, marker: UUID, retry: @escaping () -> Void) {
        lock.withLock { if revisions[id] == marker { deferredWrites[id] = retry } }
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
        let id = "seeds:\(store.fileURL.path):\(ObjectIdentifier(store.defaults))"
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
        let id = "seeds:\(store.fileURL.path):\(ObjectIdentifier(store.defaults))"
        let marker = UUID()
        lock.withLock { values[id] = seeds; pending[id] = marker; revisions[id] = marker }
        queue.async { [self] in
            guard lock.withLock({ pending[id] == marker }) else { return }
            do { try PerformanceTrace.measure("Conversation Seed Save") { try store.save(seeds) } }
            catch where !PersonalDataProtection.isIntegrityFailure(error) {
                deferWrite(id: id, marker: marker) { [self] in saveSeeds(seeds, store: store) }
                PersonalDataProtection.report(error, duringWrite: true)
            } catch {
                lock.withLock { if revisions[id] == marker { values.removeValue(forKey: id) } }
                PersonalDataProtection.report(error, duringWrite: true)
            }
            lock.withLock { if pending[id] == marker { pending.removeValue(forKey: id) } }
        }
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
        let id = "preference:\(key)"
        let marker = UUID()
        lock.withLock { preferenceValues[key] = value; pending[id] = marker; revisions[id] = marker }
        queue.async { [self] in
            guard lock.withLock({ pending[id] == marker }) else { return }
            if !PersonalDataProtection.isBlocked {
                do { try PrivatePreferences.standard.write(value, key: key) }
                catch {
                    if !PersonalDataProtection.isIntegrityFailure(error) {
                        deferWrite(id: id, marker: marker) { [self] in setString(value, for: key) }
                    }
                    PersonalDataProtection.report(error, duringWrite: true)
                }
            }
            lock.withLock { if pending[id] == marker { pending.removeValue(forKey: id) } }
        }
    }

    /// A barrier used before reset/recovery so previous writes cannot recreate removed stores.
    func invalidate() {
        queue.sync { lock.withLock { epoch &+= 1; values.removeAll(); warmedFiles.removeAll(); preferenceValues.removeAll(); pending.removeAll(); revisions.removeAll(); deferredWrites.removeAll() } }
    }

    func flush() async {
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }
}
