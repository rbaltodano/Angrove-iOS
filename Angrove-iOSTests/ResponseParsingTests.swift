import Foundation
import Testing
@testable import Angrove_iOS

@MainActor
@Suite("Response formatting boundaries")
struct ResponseParsingTests {
    @Test("Completed Markdown keeps paragraph boundaries and global reveal offsets")
    func completedMarkdownBoundaries() {
        let segments = ResponseParser.parseSegments(from: """
        # Heading

        First paragraph.

        Second paragraph.

        1. First item
        2. Second item

        - Last item
        """)
        #expect(segments.map(\.id) == [0, 1, 2, 3, 4])
        #expect(segments.map(\.wordStart) == [0, 1, 3, 5, 9])
        #expect(segments.map(\.wordCount) == [1, 2, 2, 4, 2])
        guard segments.count == 5 else { return }
        if case .heading(level: 1) = segments[0].kind {} else { Issue.record("Heading lost") }
        #expect(segments[1].isParagraph && segments[2].isParagraph)
        if case .orderedList(let items) = segments[3].kind {
            #expect(items == ["First item", "Second item"])
            #expect(segments[3].itemWordOffsets == [0, 2])
        } else { Issue.record("Ordered list lost") }
        if case .unorderedList(let items) = segments[4].kind {
            #expect(items == ["Last item"])
        } else { Issue.record("Unordered list lost") }
    }

    @Test("Multiword Insight links retain reveal identity and punctuation")
    func multiwordInsightIdentity() {
        let source = "One ([natural law](aq://natural-law)), tail"
        let tokens = LiveResponseToken.parse(source, annotationSequenceStart: 4)
        #expect(tokens.map(\.id) == [0, 1, 2, 3])
        #expect(tokens.map(\.source) == ["One", "natural", "law", "tail"])
        let annotations = tokens.compactMap(\.annotation)
        #expect(annotations.map(\.sequence) == [4, 4])
        #expect(annotations.first?.leadingPunctuation == "(")
        #expect(annotations.last?.trailingPunctuation == "),")
        let segments = ResponseParser.parseSegments(from: source)
        #expect(ResponseParser.insightLinkSequenceByWordStart(in: segments) == [1: 0])
    }

    @Test("Incremental Markdown keeps annotation order across headings and lists")
    func liveBlockAnnotationOrder() {
        let blocks = LiveResponseBlock.parse("""
        Before [prudence](aq://prudence).

        ## Heading

        1. [justice](aq://justice)
        2. mercy
        """)
        #expect(blocks.map(\.id) == [0, 1, 2])
        #expect(blocks.map(\.annotationSequenceStart) == [0, 1, 1])
        guard blocks.count == 3 else { return }
        if case .heading(level: 2, text: "Heading") = blocks[1].kind {} else {
            Issue.record("Live heading changed")
        }
        if case .orderedList(let items) = blocks[2].kind {
            #expect(items == ["[justice](aq://justice)", "mercy"])
        } else { Issue.record("Live ordered list changed") }
    }

    @Test("Preview and definition context keep their distinct emphasis policies")
    func markupPolicies() {
        let answer = "Consider **[natural law](aq://natural-law)**."
        #expect(String(ConversationCardAnswerFormatting.attributedText(from: answer).characters) == "Consider natural law.")
        #expect(ResponseTextFormatting.definitionContext(from: answer) == "Consider **natural law**.")
        #expect(ResponseTextFormatting.definitionContext(from: "{{[prudence](aq://prudence)}}") == "{{prudence}}")
        let legacy = "Consider {{prudence}}."
        #expect(String(ConversationCardAnswerFormatting.attributedText(from: legacy).characters) == "Consider prudence.")
    }
}
