import SwiftUI

/// A page publishes controls and their slot; the workspace owns their persistent host.
struct MacGlobalModelControls {
    var configuration: ModelControlsConfiguration
    var bounds: Anchor<CGRect>?
}

struct MacGlobalModelControlsKey: PreferenceKey {
    static var defaultValue: MacGlobalModelControls? { nil }
    static func reduce(value: inout MacGlobalModelControls?, nextValue: () -> MacGlobalModelControls?) {
        if let next = nextValue() { value = next }
    }
}

struct MacGlobalModelControlsDock: View {
    let published: MacGlobalModelControls?
    let modelTasks: ModelTaskQueue
    let queuePopup: ModelTasksPopupState

    var body: some View {
        GeometryReader { geometry in
            let bounds = published?.bounds.map { geometry[$0] } ?? CGRect(origin: .zero, size: geometry.size)
            ModelControlsHost(configuration: published?.configuration
                ?? MacPageControls.configuration(actions: [], modelTasks: modelTasks, queuePopup: queuePopup))
                .frame(width: bounds.width, height: bounds.height, alignment: .bottom)
                .position(x: bounds.midX, y: bounds.midY)
        }
    }
}

struct MacDockedDefinitionCard: View {
    let session: MacConversationState
    let concept: ConceptDefinition

    var body: some View {
        InsightLibraryCard(insight: concept, isSaved: session.savedIDs.contains(concept.id),
            onQuote: { session.attachQuote(concept) },
            onFork: { session.fork(concept) },
            onToggleSaved: { session.toggleBookmark(concept) },
            onClose: dismiss)
            .padding(.horizontal, 24)
            .environment(\.speechSource, SpeechSource(title: concept.word, conversationID: session.id, page: .conversation))
    }

    private func dismiss() {
        withAnimation(.springStandard) { session.selectedDefinition = nil }
    }
}
