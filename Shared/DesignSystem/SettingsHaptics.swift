import Foundation

@MainActor enum SettingsHaptics {
    static var isEnabled: Bool {
        let defaults = PrivatePreferences.standard
        guard defaults.object(forKey: SettingsStorageKey.hapticFeedback) != nil else {
            return true
        }
        return defaults.bool(forKey: SettingsStorageKey.hapticFeedback)
    }

    static func playSelection() {
        guard isEnabled else { return }
        CanvasImpactFeedback(style: .light).impactOccurred()
    }

    static func playDoubleSelection() async {
        guard isEnabled else { return }
        let feedback = CanvasImpactFeedback(style: .light)
        feedback.prepare()
        feedback.impactOccurred()
        do {
            try await Task.sleep(for: .milliseconds(100))
        } catch {
            return
        }
        guard isEnabled else { return }
        feedback.impactOccurred()
    }
}
