import Foundation

nonisolated struct LibraryPassage: Decodable, Identifiable, Sendable {
    let text: String
    let title: String
    let sourceId: String
    let chunkIndex: Int
    var id: String { "\(sourceId)-\(chunkIndex)" }
}


extension Notification.Name {
    static let openGroundingSourceInLibrary = Notification.Name("openGroundingSourceInLibrary")
}
