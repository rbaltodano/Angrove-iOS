import SwiftUI

struct WorktreeDefinitionRequest {
    let boardID: UUID
    let sessionID: UUID
    let concept: ConceptDefinition
}

struct WorktreeDockedDefinition: Identifiable {
    let id = UUID()
    let session: MacConversationState
    let concept: ConceptDefinition
}

extension Notification.Name {
    static let macOpenBoardDefinition = Notification.Name("angrove.mac.open-board-definition")
}

extension WorktreeBoard {
    func postDefinition(_ concept: ConceptDefinition, from session: MacConversationState,
                        to center: ModelCompletionNotificationCenter) {
        center.postInsightDefinition(concept, conversationID: session.id, postsSystemNotification: false)
    }

    @discardableResult
    func presentDefinition(_ request: WorktreeDefinitionRequest) -> Bool {
        guard request.boardID == documentID,
              let session = items.compactMap(\.session).first(where: { $0.id == request.sessionID }) else { return false }
        withAnimation(.springStandard) {
            dockedDefinition = WorktreeDockedDefinition(session: session, concept: request.concept)
            session.selectedDefinition = request.concept
        }
        return true
    }
}

extension WorktreeLibrary {
    func openDefinition(_ request: WorktreeDefinitionRequest) {
        guard documents.contains(where: { $0.id == request.boardID }) else { return }
        if openBoard?.documentID != request.boardID {
            close()
            open(request.boardID)
        }
        openBoard?.presentDefinition(request)
    }
}
