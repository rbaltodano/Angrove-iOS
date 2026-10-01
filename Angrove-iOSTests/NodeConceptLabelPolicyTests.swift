import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Broader Node Concept labels")
struct NodeConceptLabelPolicyTests {
    @Test("Duplicate titles cannot escape through superficial formatting", arguments: [
        "Prudence", "THE PRUDENCE!", "Prúdence", "Study of Prudence", "About Prudence", "Exploring Prudence"
    ])
    func repeatedTitle(_ label: String) {
        #expect(!NodeConceptLabelPolicy.isValid(label, insightTitles: ["Prudence"]))
    }

    @Test("Labels are compared to whole titles, not arbitrary colon-separated descriptions")
    func completeTitles() {
        #expect(!NodeConceptLabelPolicy.isValid("Virtue Ethics", insightTitles: ["Virtue: Ethics"]))
        #expect(NodeConceptLabelPolicy.isValid("Moral Virtues", insightTitles: ["Prudence", "Courage"]))
        #expect(NodeConceptLabelPolicy.isValid("Political Philosophy", insightTitles: ["Justice"]))
        #expect(!NodeConceptLabelPolicy.isValid("Philosophy", insightTitles: ["Justice"]))
        #expect(!NodeConceptLabelPolicy.isValid("No insights provided", insightTitles: ["Justice"]))
        #expect(!NodeConceptLabelPolicy.isValid(": ", insightTitles: []))
    }

    @Test("A duplicate label gets exactly one corrective attempt")
    func repair() async throws {
        var prompts: [String] = []
        let label = try await NodeConceptLabelPolicy.generate(
            descriptions: ["Prudence: Practical judgment."], insightTitles: ["Prudence"]
        ) { prompt in
            prompts.append(prompt)
            return prompts.count == 1 ? "Prudence" : "Moral Virtues"
        }
        #expect(label == "Moral Virtues")
        #expect(prompts.count == 2)
        #expect(prompts[1].contains("previous label did not satisfy"))
    }

    @Test("Two unacceptable labels fail without invented fallback content")
    func boundedFailure() async {
        var attempts = 0
        do {
            _ = try await NodeConceptLabelPolicy.generate(descriptions: ["Prudence"], insightTitles: ["Prudence"]) { _ in
                attempts += 1
                return "Prudence"
            }
            Issue.record("Expected duplicate rejection")
        } catch {
            #expect(error as? AngroveModelActionError == .invalidResponse)
        }
        #expect(attempts == 2)
    }

    @Test("Cancellation after a bad label stops the corrective attempt")
    func cancellation() async {
        let task = Task {
            try await NodeConceptLabelPolicy.generate(descriptions: ["Prudence"], insightTitles: ["Prudence"]) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return "Prudence"
            }
        }
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch {
            #expect(error is CancellationError)
        }
    }
}
