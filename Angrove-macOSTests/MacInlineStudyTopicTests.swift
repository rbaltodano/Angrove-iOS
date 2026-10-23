import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor @Suite(.serialized)
struct MacInlineStudyTopicTests {
    @Test func newTopicIsImmediatelySelectedAndEditsSaveWithoutAFormSubmission() throws {
        var saved: [StudyTopic] = []
        let state = MacStudyTopicsState(topics: []) { saved = $0 }
        let newTopic = try #require(MacStudyTopicPageActions.make(state: state,
            onNewConversation: { _ in }, onAddConversation: {}).first)
        #expect(newTopic.title == "New Study Topic")
        newTopic.action()
        let id = try #require(state.selectedTopicID)
        #expect(saved.first?.id == id)
        #expect(saved.first?.title == "")
        #expect(saved.first?.description == "")
        let createdAt = try #require(saved.first?.createdAt)
        state.update(id) { $0.title = "The Desert Fathers" }
        #expect(saved.first?.title == "The Desert Fathers")
        state.update(id) { $0.description = "Explore prayer and the early monastic tradition." }
        #expect(saved.first?.description == "Explore prayer and the early monastic tradition.")
        #expect(saved.first?.createdAt == createdAt)
        state.close(conversationTopicIDs: [])
        #expect(saved.count == 1)
        state.open(id)
        #expect(state.topics.first?.title == "The Desert Fathers")
    }

    @Test func leavingAnUntouchedBlankDiscardsOnlyThatDraft() throws {
        let existing = StudyTopic(title: "Existing")
        var saved: [StudyTopic] = []
        let state = MacStudyTopicsState(topics: [existing]) { saved = $0 }
        state.create()
        state.close(conversationTopicIDs: [])
        #expect(state.selectedTopicID == nil)
        #expect(saved == [existing])
        state.create()
        state.discardUntouchedDraft()
        #expect(saved == [existing])
        #expect(state.selectedTopicID == nil)
    }

    @Test func conversationActionsAndExternalAssignmentsRetainAnUntitledTopic() throws {
        for actionIndex in [-1, 0, 1] {
            var saved: [StudyTopic] = []
            let state = MacStudyTopicsState(topics: []) { saved = $0 }
            state.create()
            let id = try #require(state.selectedTopicID)
            if actionIndex >= 0 {
                MacStudyTopicPageActions.make(state: state, onNewConversation: { _ in }, onAddConversation: {})[actionIndex].action()
            }
            state.close(conversationTopicIDs: actionIndex >= 0 ? [] : [id])
            #expect(saved.first?.id == id)
        }
    }

    @Test func editsAndFilesKeepADraftAndStaleFieldWritesCannotRecreateDeletedTopics() throws {
        var saved: [StudyTopic] = []
        let state = MacStudyTopicsState(topics: []) { saved = $0 }
        state.create()
        let id = try #require(state.selectedTopicID)
        let file = UploadedFile(name: "Reference", imageData: nil, rotationDegrees: 0)
        state.update(id) { $0.files = [file]; $0.description = "A reference" }
        state.update(id) { $0.title = "Patristics" }
        #expect(saved.first?.files == [file])
        state.close(conversationTopicIDs: [])
        #expect(saved.count == 1)
        state.remove(id)
        state.update(id) { $0.title = "Delayed edit" }
        #expect(saved.isEmpty)
    }

    @Test func inlinePageRendersPlaceholdersAndImmediatelyOffersBothConversationActions() async throws {
        for (name, scheme, width) in [("light", ColorScheme.light, 1000.0), ("dark", .dark, 1000.0), ("narrow", .light, 560.0)] {
            let state = MacStudyTopicsState(topics: []) { _ in }
            state.create()
            let topicID = try #require(state.selectedTopicID)
            let runtime = MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue())
            let popup = ModelTasksPopupState()
            var newConversationTopicID: UUID?
            let host = NSHostingView(rootView: MacStudyTopicsView(conversations: [], onOpenConversation: { _ in },
                onNewConversation: { newConversationTopicID = $0 }, onTopicsChanged: {}, queuePopup: popup,
                topics: [], state: state, runtime: runtime)
                .overlayPreferenceValue(MacGlobalModelControlsKey.self) { published in
                    MacGlobalModelControlsDock(published: published, modelTasks: runtime.modelTasks, queuePopup: popup)
                }
                .environment(\.colorScheme, scheme))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 850),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            defer { window.contentView = nil; window.close() }
            try await Task.sleep(for: .milliseconds(800))
            host.layoutSubtreeIfNeeded()
            #expect(window.attachedSheet == nil)
            #expect(state.selectedTopicID == topicID)
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(filePath: "/tmp/angrove-inline-topic-\(name).png"))
            let titleEditor = try #require(window.firstResponder as? NSTextView)
            titleEditor.insertText("Patristics", replacementRange: NSRange(location: 0, length: 0))
            try await Task.sleep(for: .milliseconds(50))
            #expect(state.topics.first?.title == "Patristics")
            window.selectNextKeyView(nil)
            try await Task.sleep(for: .milliseconds(100))
            let fields = editableFields(in: host)
            if let descriptionField = fields.first(where: { ($0.font?.pointSize ?? 0) < 20 }) {
                descriptionField.selectText(nil)
            }
            let descriptionEditor = try #require(window.firstResponder as? NSTextView)
            descriptionEditor.insertText("Read the early Church Fathers.", replacementRange: NSRange(location: 0, length: 0))
            try await Task.sleep(for: .milliseconds(50))
            #expect(state.topics.first?.description == "Read the early Church Fathers.")
            host.layoutSubtreeIfNeeded()
            let editedBitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: editedBitmap)
            try #require(editedBitmap.representation(using: .png, properties: [:]))
                .write(to: URL(filePath: "/tmp/angrove-inline-topic-typed-\(name).png"))
            var didOpenPicker = false
            let actions = MacStudyTopicPageActions.make(state: state,
                onNewConversation: { newConversationTopicID = $0 }, onAddConversation: { didOpenPicker = true })
            #expect(actions.map(\.title) == ["New Conversation", "Add Existing Conversation"])
            actions[1].action()
            #expect(didOpenPicker)
            actions[0].action()
            #expect(newConversationTopicID == topicID)
            state.discardUntouchedDraft()
            #expect(state.topics.first?.id == topicID)
        }
    }

    private func editableFields(in view: NSView) -> [NSTextField] {
        let own = (view as? NSTextField).map { $0.isEditable ? [$0] : [] } ?? []
        return own + view.subviews.flatMap { editableFields(in: $0) }
    }
}
