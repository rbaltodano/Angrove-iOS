//
//  InquiryPersistence.swift
//  Angrove-iOS
//

import Foundation

nonisolated extension InquiryPersistenceSnapshot {
    func preservingCompletedResponses(from stored: InquiryPersistenceSnapshot?) -> InquiryPersistenceSnapshot {
        var snapshot = self
        if let stored {
            for conversationIndex in snapshot.conversations.indices {
                guard let savedConversation = stored.conversations.first(where: {
                    $0.id == snapshot.conversations[conversationIndex].id
                }) else { continue }
                for branchIndex in snapshot.conversations[conversationIndex].branches.indices {
                    var branch = snapshot.conversations[conversationIndex].branches[branchIndex]
                    guard let savedBranch = savedConversation.branches.first(where: { $0.id == branch.id }),
                          branch.topQuestionText == savedBranch.topQuestionText else { continue }
                    // Preserve a title produced after this page's snapshot was captured.
                    // Explicit renames set a branch title; clear replaces the branch identity.
                    if branch.parentBranchID == nil, branch.generatedBranchTitle == nil,
                       let title = savedBranch.generatedBranchTitle {
                        branch.generatedBranchTitle = title
                        if snapshot.conversations[conversationIndex].title == "New Conversation" {
                            snapshot.conversations[conversationIndex].title = savedConversation.title
                        }
                    }
                    for index in branch.activeChatBlocks.indices {
                        guard branch.activeChatBlocks[index] == .text(""),
                              savedBranch.activeChatBlocks.indices.contains(index),
                              case .text(let answer) = savedBranch.activeChatBlocks[index],
                              !answer.isEmpty,
                              branch.activeChatBlocks.prefix(index) == savedBranch.activeChatBlocks.prefix(index)
                        else { continue }
                        branch.activeChatBlocks[index] = .text(answer)
                        if let presentation = savedBranch.responsePresentation(at: index) {
                            branch.setResponsePresentation(presentation)
                        }
                        if index == branch.activeChatBlocks.count - 1 {
                            branch.showBottomInput = true
                        }
                    }
                    snapshot.conversations[conversationIndex].branches[branchIndex] = branch
                }
            }
        }
        return snapshot
    }
}

// MARK: - Inquiry Persistence

/// The full piece of local state needed to restore the user's conversation canvases.
nonisolated struct InquiryPersistenceSnapshot: Codable, Equatable, Sendable {
    var conversations: [InquiryConversation]
    var activeConversationID: UUID?
}

nonisolated enum InquiryPersistenceError: LocalizedError {
    case applicationSupportUnavailable
    case invalidImport

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            "Angrove could not open its local data directory."
        case .invalidImport:
            "That file is not a valid Angrove conversation export."
        }
    }
}

/// File-backed conversation storage with atomic replacement, rotating backups, and migration from
/// both prototype `UserDefaults` keys. The snapshot shape deliberately remains Codable so stable
/// conversation, branch, response, and Insight identifiers survive the storage migration.
nonisolated struct InquirySnapshotFileStore {
    static let currentLegacyKey = "aquinas.current.conversations.v1"
    static let originalLegacyKey = "aquinas.inquiry.persistence.snapshot.v1"

    private let rootDirectory: URL
    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let now: () -> Date

    private let snapshotFileName = "conversations-v1.json"
    private let backupDirectoryName = "Backups"
    private let maximumBackupCount = 5
    private let minimumBackupInterval: TimeInterval = 6 * 60 * 60

    init(
        rootDirectory: URL,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.rootDirectory = rootDirectory
        self.defaults = defaults
        self.fileManager = fileManager
        self.now = now
    }

    func load() -> InquiryPersistenceSnapshot? {
        if let snapshot = decodeSnapshot(at: snapshotURL) {
            return snapshot
        }

        for backupURL in backupURLsNewestFirst() {
            if let snapshot = decodeSnapshot(at: backupURL) {
                // Restore the last known-good snapshot to the live location. Failure here should
                // not hide the recovered in-memory value from the user.
                try? write(snapshot, createsBackup: false)
                return snapshot
            }
        }

        return migrateLegacySnapshotIfAvailable()
    }

    func save(_ snapshot: InquiryPersistenceSnapshot) throws {
        try write(snapshot, createsBackup: true)
    }

    /// A mounted page can save a snapshot captured before an offscreen job finished. Keep
    /// completed slots when that stale snapshot still contains the identical pending question.
    /// Imports use `write` directly; clear/delete change the branch or remove its blocks.
    func savePreservingCompletedResponses(_ snapshot: InquiryPersistenceSnapshot) throws {
        try save(snapshot.preservingCompletedResponses(from: load()))
    }

    /// Replaces only the branch whose model response just completed. This narrow write is used by
    /// shell-owned model work after its originating SwiftUI screen has been removed, so a stale
    /// view snapshot cannot turn the completed answer back into an empty response placeholder.
    func saveCompletedBranch(
        _ completedBranch: ChatBranch,
        conversationID: UUID
    ) throws {
        guard var snapshot = load(),
              let conversationIndex = snapshot.conversations.firstIndex(where: {
                  $0.id == conversationID
              }),
              let branchIndex = snapshot.conversations[conversationIndex].branches.firstIndex(where: {
                  $0.id == completedBranch.id
              }) else {
            return
        }
        snapshot.conversations[conversationIndex].branches[branchIndex] = completedBranch
        try write(snapshot, createsBackup: true)
    }

    /// Read and update one existing response slot. Navigation must not determine its destination,
    /// and a late result must never recreate a cleared/deleted branch or missing question.
    func completeDetachedResponse(
        branchID: UUID,
        conversationID: UUID,
        responseIndex: Int,
        annotatedText: String,
        presentation: ResponsePresentationMetadata
    ) throws {
        guard let snapshot = load(),
              var branch = snapshot.conversations.first(where: { $0.id == conversationID })?
                .branches.first(where: { $0.id == branchID }),
              branch.activeChatBlocks.indices.contains(responseIndex) else { return }
        branch.activeChatBlocks[responseIndex] = .text(annotatedText)
        branch.setResponsePresentation(presentation)
        branch.showBottomInput = true
        try saveCompletedBranch(branch, conversationID: conversationID)
    }

    func exportData() throws -> Data {
        guard let snapshot = load() else {
            return try Self.encoder.encode(
                InquiryPersistenceSnapshot(conversations: [], activeConversationID: nil)
            )
        }
        return try Self.encoder.encode(snapshot)
    }

    @discardableResult
    func importData(_ data: Data) throws -> InquiryPersistenceSnapshot {
        guard let snapshot = try? Self.decoder.decode(
            InquiryPersistenceSnapshot.self,
            from: data
        ) else {
            throw InquiryPersistenceError.invalidImport
        }
        try write(snapshot, createsBackup: true)
        return snapshot
    }

    private var snapshotURL: URL {
        rootDirectory.appending(path: snapshotFileName)
    }

    private var backupDirectoryURL: URL {
        rootDirectory.appending(path: backupDirectoryName, directoryHint: .isDirectory)
    }

    private func write(
        _ snapshot: InquiryPersistenceSnapshot,
        createsBackup: Bool
    ) throws {
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        if createsBackup {
            try createBackupIfNeeded()
        }
        let data = try Self.encoder.encode(snapshot)
        try EncryptedPersonalFile.write(data, to: snapshotURL)
    }

    private func createBackupIfNeeded() throws {
        guard fileManager.fileExists(atPath: snapshotURL.path) else { return }
        try fileManager.createDirectory(
            at: backupDirectoryURL,
            withIntermediateDirectories: true
        )

        if let newest = backupURLsNewestFirst().first,
           let values = try? newest.resourceValues(forKeys: [.contentModificationDateKey]),
           let modificationDate = values.contentModificationDate,
           now().timeIntervalSince(modificationDate) < minimumBackupInterval {
            return
        }

        let backupURL = backupDirectoryURL.appending(
            path: "conversations-\(Self.backupTimestamp.string(from: now())).json"
        )
        try fileManager.copyItem(at: snapshotURL, to: backupURL)
        try pruneBackups()
    }

    private func pruneBackups() throws {
        for oldBackup in backupURLsNewestFirst().dropFirst(maximumBackupCount) {
            try fileManager.removeItem(at: oldBackup)
        }
    }

    private func backupURLsNewestFirst() -> [URL] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: backupDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls
            .filter { $0.pathExtension == "json" }
            .sorted { left, right in
                let leftDate = try? left.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                let rightDate = try? right.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                return (leftDate ?? .distantPast) > (rightDate ?? .distantPast)
            }
    }

    private func decodeSnapshot(at url: URL) -> InquiryPersistenceSnapshot? {
        guard let data = try? EncryptedPersonalFile.read(url) else { return nil }
        return try? Self.decoder.decode(InquiryPersistenceSnapshot.self, from: data)
    }

    private func migrateLegacySnapshotIfAvailable() -> InquiryPersistenceSnapshot? {
        for key in [Self.currentLegacyKey, Self.originalLegacyKey] {
            guard let data = PrivatePreferences(defaults: defaults).data(forKey: key),
                  let snapshot = try? Self.decoder.decode(
                    InquiryPersistenceSnapshot.self,
                    from: data
                  ) else {
                continue
            }
            do {
                try write(snapshot, createsBackup: false)
                PrivatePreferences(defaults: defaults).removeObject(forKey: Self.currentLegacyKey)
                PrivatePreferences(defaults: defaults).removeObject(forKey: Self.originalLegacyKey)
            } catch {
                // Keep the legacy copy until a verified file write succeeds.
            }
            return snapshot
        }
        return nil
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    private static let backupTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

/// Canonical process-facing conversation repository. All app features use this boundary; the
/// concrete file store can later be replaced by normalized SwiftData records without another view
/// rewrite.
nonisolated enum InquiryPersistenceStore {
    nonisolated private static let shared = SerializedInquiryStore(makeStore: liveStore)

    static func load() -> InquiryPersistenceSnapshot? {
        shared.readCached()
    }

    static func preload() { _ = shared.load() }

    static func invalidate() { shared.invalidate() }

    static func flushAsync() async { await shared.flushAsync() }

    static func retryDeferredSave() { shared.retryDeferredSave() }

    static func save(_ snapshot: InquiryPersistenceSnapshot) {
        shared.save(snapshot)
    }

    static func saveCompletedBranch(
        _ completedBranch: ChatBranch,
        conversationID: UUID
    ) {
        shared.saveCompletedBranch(completedBranch, conversationID: conversationID)
    }

    /// Completes a response for a conversation that is no longer displayed, addressing the
    /// persisted branch by ID rather than through any view binding.
    static func completeDetachedResponse(
        branchID: UUID,
        conversationID: UUID,
        responseIndex: Int,
        annotatedText: String,
        presentation: ResponsePresentationMetadata
    ) {
        shared.completeDetachedResponse(
            branchID: branchID,
            conversationID: conversationID,
            responseIndex: responseIndex,
            annotatedText: annotatedText,
            presentation: presentation
        )
    }

    static func exportData() throws -> Data {
        try shared.exportData()
    }

    static func exportDataAsync() async throws -> Data {
        try await Task.detached(priority: .utility) { try shared.exportData() }.value
    }

    static func importDataAsync(_ data: Data) async throws -> InquiryPersistenceSnapshot {
        try await Task.detached(priority: .utility) { try shared.importData(data) }.value
    }

    @discardableResult
    static func importData(_ data: Data) throws -> InquiryPersistenceSnapshot {
        try shared.importData(data)
    }

    /// Blocks until every queued write has reached disk. Call before the app is suspended.
    static func flush() {
        shared.flush()
    }

    nonisolated private static func liveStore() -> InquirySnapshotFileStore? {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return InquirySnapshotFileStore(
            rootDirectory: applicationSupport.appending(
                path: "Aquinas/ConversationStore",
                directoryHint: .isDirectory
            )
        )
    }
}

/// Runs every snapshot operation on one serial background queue so JSON encoding and file I/O stay
/// off the main thread. Writes are enqueued and return immediately; reads and imports wait behind
/// queued writes, so a load never observes a stale file and writes never interleave.
nonisolated final class SerializedInquiryStore: @unchecked Sendable {
    private let makeStore: () -> InquirySnapshotFileStore?
    private let cacheLock = NSLock()
    private var cached: InquiryPersistenceSnapshot?
    private var didLoad = false
    private var cacheRevision = 0
    private let queue = DispatchQueue(label: "com.aquinas.inquiry-persistence", qos: .utility)

    init(makeStore: @escaping () -> InquirySnapshotFileStore?) {
        self.makeStore = makeStore
    }

    func load() -> InquiryPersistenceSnapshot? {
        let revision = cacheLock.withLock { cacheRevision }
        return queue.sync {
            let value = makeStore()?.load()
            cacheLock.withLock {
                if cacheRevision == revision { cached = value; didLoad = true; cacheRevision += 1 }
            }
            return value
        }
    }

    func readCached() -> InquiryPersistenceSnapshot? {
        guard !PersonalDataProtection.isBlocked else { return nil }
        let state = cacheLock.withLock { (didLoad, cached) }
        return state.0 ? state.1 : load()
    }

    func flushAsync() async {
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }

    private func updateCached(_ operation: (inout InquiryPersistenceSnapshot) -> Void) {
        cacheLock.withLock {
            if var value = cached { operation(&value); cached = value; cacheRevision += 1 }
        }
    }

    /// A whole-snapshot save that has been queued but not yet started. Views save after most
    /// edits, and each write re-reads, re-encodes and rewrites the full file, so a burst of saves
    /// collapses into one write of the newest snapshot. Any other queued operation closes the
    /// slot, so coalescing never reorders a save around a branch completion.
    private final class PendingSave: @unchecked Sendable {
        var snapshot: InquiryPersistenceSnapshot
        init(_ snapshot: InquiryPersistenceSnapshot) { self.snapshot = snapshot }
    }

    private let pendingLock = NSLock()
    private var openSave: PendingSave?

    func save(_ snapshot: InquiryPersistenceSnapshot) {
        cacheLock.withLock { cached = snapshot.preservingCompletedResponses(from: cached); didLoad = true; cacheRevision += 1 }
        let pending: PendingSave? = pendingLock.withLock {
            if let openSave {
                openSave.snapshot = snapshot
                return nil
            }
            let pending = PendingSave(snapshot)
            openSave = pending
            return pending
        }
        guard let pending else { return }
        queue.async { [self] in
            let latest = pendingLock.withLock {
                if openSave === pending { openSave = nil }
                return pending.snapshot
            }
            do {
                try requireStore().savePreservingCompletedResponses(latest)
            } catch {
                handleWriteFailure(error)
            }
        }
    }

    /// A locked phone makes the key unavailable. The cache already holds the newest snapshot,
    /// so keep it and write it once protected data returns instead of closing storage.
    private var needsDeferredSave = false

    private func handleWriteFailure(_ error: Error) {
        guard !PersonalDataProtection.isIntegrityFailure(error),
              !(error is InquiryPersistenceError) else {
            PersonalDataProtection.report(error)
            return
        }
        cacheLock.withLock { needsDeferredSave = true }
        PersonalDataProtection.report(error, duringWrite: true)
    }

    func retryDeferredSave() {
        let snapshot: InquiryPersistenceSnapshot? = cacheLock.withLock {
            guard needsDeferredSave else { return nil }
            needsDeferredSave = false
            return cached
        }
        guard let snapshot else { return }
        save(snapshot)
    }

    private func closePendingSave() {
        pendingLock.withLock { openSave = nil }
    }

    func saveCompletedBranch(_ completedBranch: ChatBranch, conversationID: UUID) {
        updateCached { snapshot in
            guard let i = snapshot.conversations.firstIndex(where: { $0.id == conversationID }),
                  let j = snapshot.conversations[i].branches.firstIndex(where: { $0.id == completedBranch.id }) else { return }
            snapshot.conversations[i].branches[j] = completedBranch
        }
        enqueue("Unable to save completed response") {
            try $0.saveCompletedBranch(completedBranch, conversationID: conversationID)
        }
    }

    func completeDetachedResponse(
        branchID: UUID,
        conversationID: UUID,
        responseIndex: Int,
        annotatedText: String,
        presentation: ResponsePresentationMetadata
    ) {
        updateCached { snapshot in
            guard let i = snapshot.conversations.firstIndex(where: { $0.id == conversationID }),
                  let j = snapshot.conversations[i].branches.firstIndex(where: { $0.id == branchID }),
                  snapshot.conversations[i].branches[j].activeChatBlocks.indices.contains(responseIndex) else { return }
            snapshot.conversations[i].branches[j].activeChatBlocks[responseIndex] = .text(annotatedText)
            snapshot.conversations[i].branches[j].setResponsePresentation(presentation)
            snapshot.conversations[i].branches[j].showBottomInput = true
        }
        enqueue("Unable to save detached response") {
            try $0.completeDetachedResponse(
                branchID: branchID,
                conversationID: conversationID,
                responseIndex: responseIndex,
                annotatedText: annotatedText,
                presentation: presentation
            )
        }
    }

    func exportData() throws -> Data {
        try queue.sync { try requireStore().exportData() }
    }

    func importData(_ data: Data) throws -> InquiryPersistenceSnapshot {
        closePendingSave()
        return try queue.sync {
            let value = try requireStore().importData(data)
            cacheLock.withLock { cached = value; didLoad = true; cacheRevision += 1 }
            return value
        }
    }

    func flush() {
        queue.sync {}
    }

    func invalidate() {
        closePendingSave()
        queue.sync { cacheLock.withLock { cached = nil; didLoad = false; cacheRevision += 1; needsDeferredSave = false } }
    }

    private func enqueue(
        _ failureMessage: String,
        _ operation: @escaping (InquirySnapshotFileStore) throws -> Void
    ) {
        closePendingSave()
        queue.async { [self] in
            do {
                try operation(requireStore())
            } catch {
                handleWriteFailure(error)
            }
        }
    }

    private func requireStore() throws -> InquirySnapshotFileStore {
        guard let store = makeStore() else {
            throw InquiryPersistenceError.applicationSupportUnavailable
        }
        return store
    }
}

// MARK: - Compatibility Alias

/// Compatibility name retained while call sites move onto `InquiryPersistenceStore` directly.
/// Both names now address the same canonical Application Support snapshot.
enum CurrentConversationsStore {
    static func load() -> InquiryPersistenceSnapshot? {
        InquiryPersistenceStore.load()
    }

    static func save(_ snapshot: InquiryPersistenceSnapshot) {
        InquiryPersistenceStore.save(snapshot)
    }
}
