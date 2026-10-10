import Foundation

enum NewUserCardEligibility {
    static let firstUseKey = "angrove.first-use-date"
    static let lifetime: TimeInterval = 7 * 24 * 60 * 60

    static func registerFirstUse(defaults: UserDefaults = .standard, now: Date = Date()) {
        guard defaults.double(forKey: firstUseKey) <= 0 else { return }
        // Existing installations predate this preference. Their Documents directory belongs
        // to the preserved data container, so updating the app does not restart the week.
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let created = documents.flatMap { try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate }
        defaults.set(min(created ?? now, now).timeIntervalSince1970, forKey: firstUseKey)
    }

    static func shouldShow(firstUse: Date?, now: Date, visited: Set<String>, topics: Set<String>) -> Bool {
        guard let firstUse, now.timeIntervalSince(firstUse) < lifetime else { return false }
        return !visited.isSuperset(of: topics)
    }
}
