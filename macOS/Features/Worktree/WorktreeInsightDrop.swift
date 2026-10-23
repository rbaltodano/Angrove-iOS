import SwiftUI
import UniformTypeIdentifiers

/// A self-contained copy of a completed definition. No library bookmark or live session is
/// needed to place it, and a cancelled drag leaves the dock untouched.
struct WorktreeInsightDrop: Codable, Sendable {
    let concept: ConceptDefinition
    var notificationID: UUID?
    var presentationID: UUID?

    private static let prefix = "angrove-insight:"

    var payload: String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return Self.prefix + data.base64EncodedString()
    }

    static func decode(_ payload: String) -> Self? {
        guard payload.hasPrefix(prefix),
              let data = Data(base64Encoded: String(payload.dropFirst(prefix.count))) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

struct MacInsightDragSource: ViewModifier {
    let concept: ConceptDefinition
    var notificationID: UUID?
    var presentationID: UUID?

    func body(content: Content) -> some View {
        let drop = WorktreeInsightDrop(concept: concept, notificationID: notificationID,
                                       presentationID: presentationID)
        content.onDrag {
            drop.itemProvider
        } preview: {
            MacConversationChip(title: concept.word)
        }
    }
}

extension WorktreeBoard {
    func placeInsight(_ drop: WorktreeInsightDrop, at origin: CGPoint,
                      center: ModelCompletionNotificationCenter?) {
        addInsight(drop.concept, at: origin)
        drop.complete(in: center)
    }
}

extension WorktreeInsightDrop {
    @MainActor func complete(in center: ModelCompletionNotificationCenter?) {
        if let id = notificationID { center?.dismiss(id: id) }
        if let id = presentationID, center?.presentedInsight?.id == id { center?.closeInsight() }
    }
}

extension WorktreeInsightDrop {
    /// The payload's custom type keeps it out of text editors. Visibility must be `.all`: Mac drags
    /// travel through the system's drag pasteboard, which never receives `.ownProcess` data, so
    /// the app's own drop targets wouldn't see the Insight either.
    var itemProvider: NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.angroveInsight.identifier, visibility: .all) { completion in
            completion(try? JSONEncoder().encode(self), nil)
            return nil
        }
        return provider
    }
}
