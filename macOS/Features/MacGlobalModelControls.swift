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
    let isVisible: Bool
    let modelTasks: ModelTaskQueue
    let queuePopup: ModelTasksPopupState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let bounds = published?.bounds.map { geometry[$0] } ?? CGRect(origin: .zero, size: geometry.size)
            ModelControlsHost(configuration: published?.configuration ?? standardConfiguration)
                .frame(width: bounds.width, height: bounds.height, alignment: .bottom)
                .scaleEffect(isVisible || reduceMotion ? 1 : 0.35, anchor: .bottom)
                .offset(y: isVisible || reduceMotion ? 0 : 24)
                .blur(radius: isVisible || reduceMotion ? 0 : 8)
                .opacity(isVisible ? 1 : 0)
                .allowsHitTesting(isVisible)
                .accessibilityHidden(!isVisible)
                .position(x: bounds.midX, y: bounds.midY)
                .animation(reduceMotion ? .easeInOut(duration: 0.2)
                           : (isVisible ? .springStandard : .easeIn(duration: 0.26)), value: isVisible)
        }
    }

    private var standardConfiguration: ModelControlsConfiguration {
        var configuration = ModelControlsConfiguration(id: "mac-global")
        configuration.modelTasks = modelTasks
        configuration.modelTasksPopupState = queuePopup
        configuration.buttons = AnyView(MacGlobalModelStatus(modelTasks: modelTasks, queuePopup: queuePopup))
        return configuration
    }
}

private struct MacGlobalModelStatus: View {
    let modelTasks: ModelTaskQueue
    let queuePopup: ModelTasksPopupState
    @State private var isPressed = false

    var body: some View {
        ModelStatusButton(modelTasks: modelTasks, action: {
            withAnimation(.springStandard) { queuePopup.isOpen.toggle() }
        }, controlIsPressed: $isPressed)
        .buttonStyle(FloatingControlButtonStyle(isPressed: $isPressed))
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
