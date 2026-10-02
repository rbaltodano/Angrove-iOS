import Foundation
import Testing
@testable import Angrove_iOS

struct ResponseThinkingDurationTests {
    @Test func formatsRecordedTime() {
        #expect(ResponseThinkingDuration.label(seconds: 83.9) == "Thought for 1m 23s")
        #expect(ResponseThinkingDuration.label(seconds: 59.9) == "Thought for 59s")
        #expect(ResponseThinkingDuration.label(seconds: 60) == "Thought for 1m 0s")
        #expect(ResponseThinkingDuration.label(seconds: 0) == "Thought for 0s")
        #expect(ResponseThinkingDuration.label(seconds: -3) == "Thought for 0s")
        #expect(ResponseThinkingDuration.label(seconds: nil) == "Thought")
    }

    @Test func oldPresentationDecodesWithoutDuration() throws {
        let data = Data(#"{"responseIndex":1,"showsThinking":true,"thinkingSummary":["Preparing"]}"#.utf8)
        let old = try JSONDecoder().decode(ResponsePresentationMetadata.self, from: data)
        #expect(old.thinkingDurationSeconds == nil)
        var recorded = old
        recorded.thinkingDurationSeconds = 83.9
        let restored = try JSONDecoder().decode(ResponsePresentationMetadata.self, from: JSONEncoder().encode(recorded))
        #expect(restored.thinkingDurationSeconds == 83.9)
    }
}
