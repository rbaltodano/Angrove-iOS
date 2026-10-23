import SwiftUI

/// A completed Insight reads in the current dock; its source is metadata, not navigation.
struct NotificationInsightCard: View {
    let presentation: NotificationInsightPresentation
    let center: ModelCompletionNotificationCenter

    var body: some View {
        InsightLibraryCard(insight: presentation.concept,
            isSaved: center.savedInsightIDs.contains(presentation.concept.id),
            onQuote: { center.onQuoteInsight(presentation.concept) },
            onFork: {},
            onToggleSaved: { center.onToggleInsightSaved(presentation.concept, presentation.conversationID) },
            onClose: { center.closeInsight() })
            #if os(macOS)
            .modifier(MacInsightDragSource(concept: presentation.concept, presentationID: presentation.id))
            #endif
            .padding(.horizontal, 24)
            .environment(\.speechSource, SpeechSource(title: presentation.concept.word,
                conversationID: presentation.conversationID, page: .conversation))
    }
}
