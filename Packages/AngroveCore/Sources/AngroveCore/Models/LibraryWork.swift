import Foundation

public nonisolated struct LibraryWork: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let passageCount: Int

    public init(id: String, title: String, passageCount: Int) {
        self.id = id
        self.title = title
        self.passageCount = passageCount
    }
}
