import Foundation

public nonisolated struct LibraryPassage: Decodable, Identifiable, Sendable {
    public let text: String
    public let title: String
    public let sourceId: String
    public let chunkIndex: Int
    public var id: String { "\(sourceId)-\(chunkIndex)" }

    public init(text: String, title: String, sourceId: String, chunkIndex: Int) {
        self.text = text
        self.title = title
        self.sourceId = sourceId
        self.chunkIndex = chunkIndex
    }
}


extension Notification.Name {
    public static let openGroundingSourceInLibrary = Notification.Name("openGroundingSourceInLibrary")
}
