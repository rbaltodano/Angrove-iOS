import SwiftUI

/// Settings › Your Data: export and import conversations, and the iPhone's clearing controls.
struct MacDataSettings: View {
    private enum Confirmation: String, Identifiable {
        case clearTree, deleteConversations, deletePassages, deleteEverything
        var id: String { rawValue }
    }

    private struct PendingImport { let data: Data; let message: String }

    @State private var confirming: Confirmation?
    @State private var export: MacConversationExport?
    @State private var showsExporter = false
    @State private var showsImporter = false
    @State private var pendingImport: PendingImport?
    @State private var errorMessage: String?
    @State private var finishedReset = false

    var body: some View {
        MacSettingsSection(title: "Your Data", description: "Your saved data is encrypted on this Mac. Exports are readable JSON files; anyone with an exported file can read it.") {
            MacSettingsRow(title: "Conversations", description: "Save a copy of your conversations, or replace them with an export.") {
                HStack {
                    Button("Export…", action: exportConversations)
                    Button("Import…") { showsImporter = true }
                }
            }
            Divider()
            MacSettingsRow(title: "Clear Insight Tree", description: "Removes every saved Insight and the whole tree. Conversations are kept.") {
                Button("Clear…", role: .destructive) { confirming = .clearTree }
            }
            Divider()
            MacSettingsRow(title: "Delete all conversations", description: "Saved Insights, Clipped Passages and Study Topics remain.") {
                Button("Delete…", role: .destructive) { confirming = .deleteConversations }
            }
            Divider()
            MacSettingsRow(title: "Delete all Clipped Passages", description: "Conversations and saved Insights remain.") {
                Button("Delete…", role: .destructive) { confirming = .deletePassages }
            }
            Divider()
            MacSettingsRow(title: "Delete all app data", description: finishedReset
                ? "App data deleted. Quit and reopen Angrove to finish resetting it."
                : "Everything Angrove stores on this Mac except the on-device model.") {
                Button("Delete…", role: .destructive) { confirming = .deleteEverything }.disabled(finishedReset)
            }
        }
        .confirmationDialog(title(confirming), isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible, presenting: confirming) { action in
            Button(title(action), role: .destructive) { perform(action) }
            Button("Cancel", role: .cancel) {}
        } message: { action in Text(message(action)) }
        .confirmationDialog("Replace Your Conversations?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
                            titleVisibility: .visible) {
            Button("Replace Conversations", role: .destructive) {
                guard let data = pendingImport?.data else { return }
                pendingImport = nil
                Task { do { try await MacAppData.importConversations(data) } catch { errorMessage = error.localizedDescription } }
            }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: { Text(pendingImport?.message ?? "") }
        .fileExporter(isPresented: $showsExporter, document: export, contentType: .json, defaultFilename: "Angrove Conversations") { result in
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
            export = nil
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.json]) { result in
            Task {
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    pendingImport = PendingImport(data: data, message: try await MacAppData.importSummary(data))
                } catch { errorMessage = error.localizedDescription }
            }
        }
        .alert("Couldn’t Manage Data", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "Please try again.") }
    }

    private func exportConversations() {
        Task {
            do {
                export = MacConversationExport(data: try await InquiryPersistenceStore.exportDataAsync())
                showsExporter = true
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func perform(_ action: Confirmation) {
        do {
            switch action {
            case .clearTree: MacAppData.clearInsightTree()
            case .deleteConversations: try MacAppData.deleteAllConversations()
            case .deletePassages: MacAppData.deleteAllClippedPassages()
            case .deleteEverything:
                try MacAppData.deleteAllAppData()
                finishedReset = true
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func title(_ action: Confirmation?) -> String {
        switch action {
        case .clearTree: "Clear Insight Tree"
        case .deleteConversations: "Delete All Conversations"
        case .deletePassages: "Delete All Clipped Passages"
        case .deleteEverything: "Delete All App Data"
        case nil: ""
        }
    }

    private func message(_ action: Confirmation) -> String {
        switch action {
        case .clearTree: "This removes every saved Insight and the whole tree on this Mac. Conversations are kept. This can’t be undone."
        case .deleteConversations: "This permanently removes all conversations and their history from this Mac. Saved Insights, Clipped Passages, and Study Topics remain. This can’t be undone."
        case .deletePassages: "This permanently removes every saved passage on this Mac. This can’t be undone."
        case .deleteEverything: "This permanently removes all conversations, saved Insights, Clipped Passages, Study Topics, reading progress and settings from this Mac. The on-device model is kept, and your other files are not affected. This can’t be undone."
        }
    }
}
