import SwiftUI

struct MacGlobalInsightWorkspace: View {
    @State private var session = MacConversationState()
    @State private var controls = MacTreeControls()
    @State private var offersUpdate = false
    @State private var showsConnectionComposer = false
    @State private var connectionQuestion = ""
    @State private var askConcept: ConceptDefinition?
    @State private var showsConversationPicker = false
    private let runtime = MacApplicationRuntime.shared
    var queuePopup: ModelTasksPopupState? = nil
    var onActivity: () -> Void = {}
    var onAsk: (ConceptDefinition, UUID?) -> Void

    var body: some View {
        MacInsightTreePane(session: session, controls: controls, runtime: runtime, isVisible: true, isGlobal: true, onActivity: onActivity)
            .compositingGroup()
            .background {
                MacConversationDock(session: session, tree: controls, runtime: runtime, isCanvasMode: true,
                    hasQuestion: false, onOpenTree: {}, onCloseTree: { controls.dismissHoverRequest += 1; controls.studyExitRequest += 1 }, isGlobal: true, onSend: {},
                    isAsking: askConcept != nil, onAsk: { askConcept = controls.hoveredConcept },
                    onAskNew: { if let concept = askConcept { onAsk(concept, nil) } },
                    onAskExisting: { showsConversationPicker = true },
                    onCancelAsk: { askConcept = nil }, queuePopup: queuePopup, onActivity: onActivity)
            }
            .overlayPreferenceValue(ModelControlsPreferenceKey.self, alignment: .bottom) { configuration in
                ModelControlsHost(configuration: configuration).zIndex(2)
            }
            .task {
                session.configure(preview: false, global: true)
                session.promotedIDs = GlobalInsightPromotedIDsStore.load()
                let ids = Set(InsightLibraryStore.load().map(\.id))
                offersUpdate = GlobalInsightTreeUpdatePrompt.shouldOffer(libraryIDs: ids,
                    acknowledgedLibraryIDs: GlobalInsightTreeUpdatePrompt.loadAcknowledgedLibraryIDs(),
                    treeNeedsUpdate: ids != Set(session.concepts.map(\.id)))
            }
            .alert("Update Insight Tree?", isPresented: $offersUpdate) {
                Button("Keep Current Tree", role: .cancel) { acknowledge() }
                Button("Update") {
                    let existing = session.concepts
                    let incoming = InsightLibraryStore.load()
                    Task {
                        let reconciled = await Task.detached(priority: .userInitiated) {
                            GlobalInsightReconciliation.reconcile(existing: existing, incoming: incoming)
                        }.value
                        guard let accepted = GlobalInsightTreeUpdateResolution.accept(existingTree: existing,
                            currentTree: session.concepts, incomingLibrary: incoming, currentLibrary: InsightLibraryStore.load(), reconciledTree: reconciled) else { return }
                        session.concepts = accepted.insights
                        GlobalInsightTreeStore.save(accepted.insights)
                        GlobalInsightTreeUpdatePrompt.saveAcknowledgedLibraryIDs(accepted.acknowledgedLibraryIDs)
                    }
                }
            } message: { Text("Include the Insights you’ve bookmarked since the last update?") }
            .onChange(of: session.connectionConcepts) { _, concepts in
                if concepts.count >= 2 { showsConnectionComposer = true }
            }
            .sheet(isPresented: $showsConnectionComposer) {
                VStack(spacing: 0) {
                    HStack { Text("Inquire Connection").font(AngroveTheme.Typography.uiHeading); Spacer(); Button("Done") { showsConnectionComposer = false } }.padding(24)
                    MacConversationView(showsFixture: false, session: session, onSend: {
                        if session.send(connectionQuestion, runtime: runtime) { connectionQuestion = "" }
                    }, question: $connectionQuestion)
                }
                .frame(width: 600, height: 650)
                .background(AngroveTheme.Colors.canvas)
                .environment(\.speechSource, SpeechSource(title: "Inquire Connection", conversationID: session.id, page: .conversation))
            }
            .sheet(isPresented: $showsConversationPicker) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Ask in Existing Conversation").font(AngroveTheme.Typography.uiHeading)
                    let conversations = CurrentConversationsStore.load()?.conversations ?? []
                    if conversations.isEmpty {
                        Text("No conversations yet.").paragraphFont()
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(conversations) { conversation in
                                Button(conversation.title.isEmpty ? "New Conversation" : conversation.title) {
                                    guard let concept = askConcept else { return }
                                    showsConversationPicker = false
                                    onAsk(concept, conversation.id)
                                }
                                .font(AngroveTheme.Typography.body)
                            }
                        }
                    }
                    Button("Cancel", role: .cancel) { showsConversationPicker = false }
                }
                .padding(28)
                .frame(width: 380, height: 420)
                .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                .background(AngroveTheme.Colors.canvas)
            }
            .onChange(of: session.quoteRequest) { _, _ in
                askConcept = session.quote
                session.quote = nil
            }
            .onChange(of: session.concepts) { _, values in GlobalInsightTreeStore.save(values) }
            .onExitCommand { askConcept = nil; controls.dismissHoverRequest += 1; controls.studyExitRequest += 1 }
            .alert("Angrove", isPresented: Bindable(session).showsError) { Button("OK", role: .cancel) {} }
                message: { Text(session.errorMessage ?? "") }
    }
    private func acknowledge() { GlobalInsightTreeUpdatePrompt.saveAcknowledgedLibraryIDs(Set(InsightLibraryStore.load().map(\.id))) }
}
