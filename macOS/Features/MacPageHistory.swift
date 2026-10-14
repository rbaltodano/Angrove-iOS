import Foundation

/// Each conversation has its own identity; its embedded tree shares that page.
struct MacWorkspacePage: Equatable, Hashable {
    let destination: MacDestination
    var conversationID: UUID? = nil
    var isFixture = false
}

/// Five distinct recent pages, ordered oldest to newest. Traversal never changes recency.
struct MacPageHistory: Equatable {
    static let capacity = 5
    private(set) var pages: [MacWorkspacePage] = []
    private(set) var index = 0

    var current: MacWorkspacePage? { pages.indices.contains(index) ? pages[index] : nil }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index + 1 < pages.count }

    mutating func visit(_ page: MacWorkspacePage) {
        guard current != page || index != pages.count - 1 else { return }
        pages.removeAll { $0 == page }
        pages.append(page)
        if pages.count > Self.capacity { pages.removeFirst(pages.count - Self.capacity) }
        index = pages.count - 1
    }

    mutating func back() -> MacWorkspacePage? {
        guard canGoBack else { return nil }
        index -= 1
        return current
    }

    mutating func forward() -> MacWorkspacePage? {
        guard canGoForward else { return nil }
        index += 1
        return current
    }

    mutating func removeConversation(_ id: UUID) {
        let active = current
        pages.removeAll { $0.conversationID == id }
        index = active.flatMap { pages.firstIndex(of: $0) } ?? min(index, max(0, pages.count - 1))
    }
}
