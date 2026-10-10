import Foundation

enum UserGuideReadingHistory {
    static let key = "angrove.user-guide.visited-topic-ids"

    static func markVisited(_ id: String, defaults: UserDefaults = .standard) {
        let data = Data((defaults.string(forKey: key) ?? "[]").utf8)
        var visited = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        guard !visited.contains(id) else { return }
        visited.append(id)
        if let encoded = try? JSONEncoder().encode(visited),
           let json = String(data: encoded, encoding: .utf8) {
            defaults.set(json, forKey: key)
        }
    }
}
