import Testing
import UIKit
@testable import Angrove_iOS

@Suite("Question input sizing")
@MainActor
struct QuestionInputSizingTests {
    private let font = UIFont(name: "Figtree-Regular", size: 14) ?? .systemFont(ofSize: 14)
    private let maximumWidth: CGFloat = 249

    private var placeholderWidth: CGFloat {
        ceil(("Ask a question" as NSString).size(withAttributes: [.font: font]).width)
    }

    private func width(_ text: String, availableWidth: CGFloat? = nil) -> CGFloat {
        ListAwareTextField.contentWidth(
            for: NSAttributedString(string: text, attributes: [.font: font]),
            availableWidth: availableWidth ?? maximumWidth,
            minimumWidth: placeholderWidth,
            caretWidth: 2
        )
    }

    @Test("Empty drafts fit the placeholder; the first character immediately hugs its text")
    func draftGrowth() {
        #expect(width("") == placeholderWidth)
        #expect(width("i") < placeholderWidth)
        #expect(width("W") > width("i"))
        #expect(width("Why?") < placeholderWidth)
        let longer = width("Why does this matter to us?")
        #expect(longer > placeholderWidth)
        #expect(longer < maximumWidth)
        #expect(width("Why?") < longer)
    }

    @Test("Long drafts reach the width cap and wrap in the editor")
    func wrapping() {
        let question = String(repeating: "What does it mean to live well? ", count: 8)
        #expect(width(question) == maximumWidth)
        let editor = UITextView()
        editor.font = font
        editor.isScrollEnabled = false
        editor.textContainerInset = .zero
        editor.textContainer.lineFragmentPadding = 0
        editor.text = question
        let height = editor.sizeThatFits(CGSize(width: width(question), height: .greatestFiniteMagnitude)).height
        #expect(height > font.lineHeight * 3)
    }

    @Test("Placeholder width never exceeds the space available on a narrow layout")
    func narrowLayout() {
        #expect(width("", availableWidth: 40) == 40)
        #expect(width("A longer question", availableWidth: 40) == 40)
    }

    @Test("Explicit line breaks size to the longest line")
    func explicitLines() {
        #expect(width("A longer question about meaning\nWhy?") == width("A longer question about meaning"))
    }
}
