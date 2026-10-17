import Foundation
import Testing
@testable import AngroveMac

@Suite("Shared saved-data compatibility")
struct SavedDataCompatibilityTests {
    @Test("Legacy conversations and branches decode the same defaults on both platforms")
    func legacyConversation() throws {
        let id = UUID(), branchID = UUID()
        let json = "{\"id\":\"\(id)\",\"branches\":[{\"id\":\"\(branchID)\"}]}"
        let value = try JSONDecoder().decode(InquiryConversation.self, from: Data(json.utf8))
        #expect(value.id == id)
        #expect(value.branches.first?.id == branchID)
        #expect(value.branches.first?.topQuestionText == "")
        #expect(value.branches.first?.activeChatBlocks.isEmpty == true)
        #expect(!value.isPinned)
        #expect(value.promotedInsightIDs.isEmpty)
    }

    @Test("Legacy topic dates have a stable fallback and populated topics round trip")
    @MainActor func legacyTopic() throws {
        let id = UUID()
        let json = "{\"id\":\"\(id)\",\"title\":\"Virtue\",\"description\":\"Habits\",\"files\":[]}"
        let topic = try JSONDecoder().decode(StudyTopic.self, from: Data(json.utf8))
        #expect(topic.id == id)
        #expect(topic.createdAt == .distantPast)
        let dated = StudyTopic(title: "Ethics", description: "Actions", createdAt: Date(timeIntervalSince1970: 1234))
        #expect(try JSONDecoder().decode(StudyTopic.self, from: JSONEncoder().encode(dated)) == dated)
    }

    @Test("Dots fade monotonically and disappear before minimum canvas zoom")
    @MainActor func zoomFade() {
        #expect(AnimatedDotGridBackground.zoomOpacity(at: 0.28) == 0)
        #expect(AnimatedDotGridBackground.zoomOpacity(at: 0.4) == 0)
        #expect(abs(AnimatedDotGridBackground.zoomOpacity(at: 0.5) - 0.5) < 0.00001)
        #expect(abs(AnimatedDotGridBackground.zoomOpacity(at: 0.6) - 1) < 0.00001)
        #expect(AnimatedDotGridBackground.zoomOpacity(at: 1) == 1)
        let values = stride(from: 0.28, through: 1.0, by: 0.01).map { AnimatedDotGridBackground.zoomOpacity(at: $0) }
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
    }
}
