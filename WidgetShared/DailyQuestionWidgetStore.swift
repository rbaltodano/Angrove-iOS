import Foundation

/// Only question text is shared. Its separate Keychain key gives the extension no access to
/// conversations or Insights. After-first-unlock accessibility supports the Lock Screen widget.
nonisolated enum DailyQuestionWidgetStore {
    static let appGroup = "group.com.ryanbaltodano.Aquinas-iOS"
    static let kind = "AngroveQuestionOfTheDay"
    private static let key = "angrove.widget.latestQuestion.v1"

    static func migrate(defaults: UserDefaults? = UserDefaults(suiteName: appGroup), cipher: LocalDataCipher = .widget) throws {
        guard let defaults else { return }
        if let data = defaults.data(forKey: key) {
            _ = try cipher.open(data, context: key)
        } else if let text = defaults.string(forKey: key) {
            let data = try cipher.seal(Data(text.utf8), context: key)
            _ = try cipher.open(data, context: key)
            defaults.set(data, forKey: key)
        }
    }

    static func load(defaults: UserDefaults? = UserDefaults(suiteName: appGroup), cipher: LocalDataCipher = .widget) -> String? {
        do {
            try migrate(defaults: defaults, cipher: cipher)
            guard let data = defaults?.data(forKey: key),
                  let text = String(data: try cipher.open(data, context: key), encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return text
        } catch { return nil } // Unavailable before first unlock; preserve the stored ciphertext.
    }

    /// Drops an unreadable shared question. The app writes a new one with the next daily question.
    static func discard(defaults: UserDefaults? = UserDefaults(suiteName: appGroup)) {
        defaults?.removeObject(forKey: key)
    }

    @discardableResult
    static func save(_ text: String, defaults: UserDefaults? = UserDefaults(suiteName: appGroup), cipher: LocalDataCipher = .widget) -> Bool {
        guard let defaults, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        do {
            try migrate(defaults: defaults, cipher: cipher)
            guard load(defaults: defaults, cipher: cipher) != text else { return false }
            let encrypted = try cipher.seal(Data(text.utf8), context: key)
            _ = try cipher.open(encrypted, context: key)
            defaults.set(encrypted, forKey: key)
            return true
        } catch { return false }
    }
}
