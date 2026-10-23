import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@MainActor
struct MacConversationActionWiringTests {
    @Test func feedbackUsesOnlyTheLatestTurnAndItsPrecedingQuestion() throws {
        let session = MacConversationState()
        session.configure(preview: true)
        session.branches[0].topQuestionSubmitted = true
        session.branches[0].topQuestionText = "Initial question"
        session.branches[0].activeChatBlocks = [.text("First answer")]
        let initial = try #require(session.feedbackReport(transcriptIndex: 1))
        #expect(initial.question == "Initial question")
        #expect(initial.response == "First answer")

        session.branches[0].activeChatBlocks += [.user("Follow-up question", nil, []), .text("Second answer")]
        #expect(session.feedbackReport(transcriptIndex: 1) == nil)
        let followUp = try #require(session.feedbackReport(transcriptIndex: 3))
        #expect(followUp.question == "Follow-up question")
        #expect(followUp.response == "Second answer")
        session.branches[0].activeChatBlocks[2] = .text(questionCanceledResponseText)
        #expect(session.feedbackReport(transcriptIndex: 3) == nil)
        session.branches[0].activeChatBlocks[2] = .text("")
        #expect(session.feedbackReport(transcriptIndex: 3) == nil)
    }

    @Test func feedbackIncludesTurnOnlyWithExplicitOptIn() {
        let report = ResponseFeedbackReport(question: "Private question", response: "Private answer")
        let without = MacResponseFeedbackSubmission.fields(note: "  Unhelpful  ", report: report, includesResponse: false)
        #expect(without["description"] == "Unhelpful")
        #expect(!without.values.contains(report.question))
        #expect(!without.values.contains(report.response))
        let included = MacResponseFeedbackSubmission.fields(note: "Unhelpful", report: report, includesResponse: true)
        #expect(included["flagged_question"] == report.question)
        #expect(included["flagged_response"] == report.response)
        #expect(included["operating_system"]?.hasPrefix("macOS ") == true)
    }

    @Test func connectionConversationAcceptsTopicAndKeepsItsTranscript() {
        let session = MacConversationState()
        session.configure(preview: true, global: true)
        session.branches[0].topQuestionSubmitted = true
        session.branches[0].topQuestionText = "How are these connected?"
        session.branches[0].activeChatBlocks = [.text("An answer")]
        let transcript = session.transcript
        let topicID = UUID()
        session.assignTopic(topicID)
        #expect(session.studyTopicID == topicID)
        #expect(session.transcript == transcript)
        session.assignTopic(nil)
        #expect(session.studyTopicID == nil)
        #expect(session.transcript == transcript)
    }

    @Test func jumpToBottomScrollsOnlyItsOwnPane() async throws {
        let first = MacConversationScrollState()
        let second = MacConversationScrollState()
        let host = NSHostingView(rootView: HStack {
            ScrollProbe(state: first)
            ScrollProbe(state: second)
        })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 540),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        let scrolls = scrollViews(in: host)
        #expect(scrolls.count == 2)
        #expect(!first.isAtBottom)
        #expect(!second.isAtBottom)
        first.bottomRequest += 1
        try await Task.sleep(for: .milliseconds(900))
        host.layoutSubtreeIfNeeded()
        #expect(first.isAtBottom)
        #expect(!second.isAtBottom)
        #expect(scrolls[0].contentView.bounds.origin.y > 0)
        #expect(scrolls[1].contentView.bounds.origin.y == 0)
    }

    @Test func feedbackSheetRendersInBothAppearances() async throws {
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let host = NSHostingView(rootView: MacResponseFeedbackSheet(
                report: ResponseFeedbackReport(question: "What is prudence?", response: "Prudence guides practical judgment.")))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 580),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            defer { window.contentView = nil; window.close() }
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .seconds(1))
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(filePath: "/tmp/angrove-response-feedback-\(name).png"))
        }
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        if let scroll = view as? NSScrollView { return [scroll] }
        return view.subviews.flatMap { scrollViews(in: $0) }
    }

    private struct ScrollProbe: View {
        let state: MacConversationScrollState
        @State private var position = ScrollPosition()
        var body: some View {
            ScrollView {
                Text(Array(repeating: "Conversation text", count: 100).joined(separator: "\n"))
                    .frame(maxWidth: .infinity)
            }
            .scrollPosition($position)
            .modifier(MacConversationScrollTracking(state: state, position: $position))
        }
    }
}
