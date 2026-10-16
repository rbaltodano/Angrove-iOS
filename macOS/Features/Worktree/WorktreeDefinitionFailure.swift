import SwiftUI

/// Reveal the failure where the definition would have appeared, then dismiss after reading time.
struct WorktreeDefinitionFailure: View {
    let term: String
    let onDismiss: () -> Void
    @State private var hasRevealed = false

    var body: some View {
        WorktreeSummaryReveal(text: String(localized: "Could not define \(term)"),
                              onComplete: { hasRevealed = true })
            .environment(\.completedResponseTextColor, AngroveTheme.Colors.accentRed)
            .task(id: hasRevealed) {
                guard hasRevealed else { return }
                do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
                guard !Task.isCancelled else { return }
                onDismiss()
            }
    }
}
