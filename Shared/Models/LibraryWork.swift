import Foundation

nonisolated struct LibraryWork: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let passageCount: Int
}
