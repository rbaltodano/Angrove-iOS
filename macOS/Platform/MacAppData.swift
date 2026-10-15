import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

/// The iPhone's Privacy & Data controls for the Mac. Every removal stays inside Angrove's own
/// folders: the Mac app is not sandboxed, so the user's Documents and Caches are never cleared.
@MainActor enum MacAppData {
    static var supportRoot: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "Angrove-macOS", directoryHint: .isDirectory)
    }

    static var cacheRoot: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "Angrove-macOS", directoryHint: .isDirectory)
    }

    /// Conversations and their per-conversation records; Insights, passages and topics remain.
    static func deleteAllConversations() throws {
        let ids = (CurrentConversationsStore.load()?.conversations ?? []).map(\.id)
        MacApplicationRuntime.shared.modelTasks.cancelTasks { $0.conversationID != nil }
        try InquiryPersistenceStore.deleteAllConversations()
        for id in ids {
            ConversationInsightMembershipStore.removeConversation(id)
            LocalInsightTreeSeedStore.removeConversation(id)
            GlossedTermStore.removeConversation(id)
            FlaggedQuoteStore.removeConversation(id)
            NotificationCenter.default.post(name: .macConversationDeleted, object: id)
        }
        NotificationCenter.default.post(name: .macConversationSaved, object: nil)
    }

    static func clearInsightTree() {
        MacApplicationRuntime.shared.modelTasks.cancelTasks { $0.kind == .updateInsightTree }
        InsightTreeReset.clearPersistedData()
        NotificationCenter.default.post(name: .macConversationSaved, object: nil)
    }

    static func deleteAllClippedPassages() {
        ClippedPassageStore.save([])
    }

    /// Everything Angrove keeps on this Mac except the installed model, which cannot yet be
    /// downloaded again on the Mac. The person must quit and reopen Angrove afterward.
    static func deleteAllAppData() throws {
        let runtime = MacApplicationRuntime.shared
        runtime.modelTasks.cancelTasks { _ in true }
        runtime.modelTasks.clearCompletedTasks()
        ResponseSpeechPlayer.shared.stop()
        LibraryListeningStore.shared.clear()
        StudyTopicStore.clearCache()
        SerializedPersonalStore.shared.invalidate()
        try InquiryPersistenceStore.eraseAll()

        let fileManager = FileManager.default
        if let supportRoot, let items = try? fileManager.contentsOfDirectory(at: supportRoot, includingPropertiesForKeys: nil) {
            for item in items where item.lastPathComponent != "Models" { try fileManager.removeItem(at: item) }
        }
        if let cache = cacheRoot?.appending(path: "LiteRTLM", directoryHint: .isDirectory),
           fileManager.fileExists(atPath: cache.path) {
            try fileManager.removeItem(at: cache)
        }
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        try LocalDataKeychain.remove(service: LocalDataCipher.personalService)
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    static func importConversations(_ data: Data) async throws {
        _ = try await InquiryPersistenceStore.importDataAsync(data)
        NotificationCenter.default.post(name: .macConversationSaved, object: nil)
    }

    static func importSummary(_ data: Data) async throws -> String {
        let incoming = try await Task.detached(priority: .utility) {
            try InquirySnapshotFileStore.decodeImport(data).conversations.count
        }.value
        let current = InquiryPersistenceStore.load()?.conversations.count ?? 0
        func count(_ n: Int) -> String { n == 1 ? "1 conversation" : "\(n) conversations" }
        return "Your \(count(current)) will be replaced by the \(count(incoming)) in this file. A backup of your current conversations is kept on this Mac."
    }
}

struct MacConversationExport: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw InquiryPersistenceError.invalidImport }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
