import Foundation
import Observation

/// A new topic is a real detail page immediately. Only an untouched, unused blank is discarded.
@MainActor @Observable final class MacStudyTopicsState {
    private(set) var topics: [StudyTopic]
    private(set) var selectedTopicID: UUID?
    private(set) var titleFocusRequest = 0
    @ObservationIgnored private var discardableTopicID: UUID?
    @ObservationIgnored private let save: ([StudyTopic]) -> Void

    init(topics: [StudyTopic], selectedTopicID: UUID? = nil, save: @escaping ([StudyTopic]) -> Void) {
        self.topics = topics
        self.selectedTopicID = selectedTopicID
        self.save = save
    }

    func create() {
        discardUntouchedDraft()
        let topic = StudyTopic()
        topics.insert(topic, at: 0)
        selectedTopicID = topic.id
        discardableTopicID = topic.id
        titleFocusRequest = 1
        save(topics)
    }

    func open(_ id: UUID, focusTitle: Bool = false) {
        guard topics.contains(where: { $0.id == id }) else { return }
        if selectedTopicID != id {
            discardUntouchedDraft()
            selectedTopicID = id
            titleFocusRequest = 0
        }
        if focusTitle { titleFocusRequest += 1 }
    }

    func close(conversationTopicIDs: Set<UUID>) {
        discardUntouchedDraft(conversationTopicIDs: conversationTopicIDs)
        selectedTopicID = nil
        titleFocusRequest = 0
    }

    func retain(_ id: UUID) {
        if discardableTopicID == id { discardableTopicID = nil }
    }

    func update(_ id: UUID, _ edit: (inout StudyTopic) -> Void) {
        guard let index = topics.firstIndex(where: { $0.id == id }) else { return }
        let previous = topics[index]
        edit(&topics[index])
        guard previous != topics[index] else { return }
        retain(id)
        save(topics)
    }

    func remove(_ id: UUID) {
        topics.removeAll { $0.id == id }
        retain(id)
        if selectedTopicID == id { selectedTopicID = nil }
        save(topics)
    }

    func reload(_ topics: [StudyTopic]) {
        self.topics = topics
        if let id = selectedTopicID, !topics.contains(where: { $0.id == id }) {
            selectedTopicID = nil
            retain(id)
        }
    }

    func discardUntouchedDraft(conversationTopicIDs: Set<UUID> = []) {
        guard let id = discardableTopicID, let topic = topics.first(where: { $0.id == id }) else { return }
        discardableTopicID = nil
        guard topic.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              topic.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              topic.files.isEmpty, !conversationTopicIDs.contains(id) else { return }
        topics.removeAll { $0.id == id }
        if selectedTopicID == id { selectedTopicID = nil }
        save(topics)
    }
}
