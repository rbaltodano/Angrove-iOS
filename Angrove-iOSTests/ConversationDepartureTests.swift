import Testing
import UIKit
@testable import Angrove_iOS

@Suite("Conversation departure presentation")
@MainActor
struct ConversationDepartureTests {
    private final class EditObserver: NSObject, NSTextStorageDelegate {
        var edits = 0
        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorage.EditActions, range editedRange: NSRange, changeInLength delta: Int) {
            edits += 1
        }
    }

    @Test("A departing question does not rewrite its text storage during layout")
    func departureKeepsTextLayoutStable() {
        let editor = CommandHighlightTextView()
        editor.text = "Why does this matter?"
        editor.updateCommandHighlight(baseColor: .angrovePrimaryReadable)
        let observer = EditObserver()
        editor.textStorage.delegate = observer
        editor.isPresentationSuspended = true
        for _ in 0..<8 { editor.layoutSubviews() }
        #expect(observer.edits == 0)
        #expect(editor.text == "Why does this matter?")
    }

    @Test("Text styling resumes when the conversation is active again")
    func stylingResumesAfterDeparture() {
        let editor = CommandHighlightTextView()
        editor.text = "A submitted question"
        editor.isPresentationSuspended = true
        let observer = EditObserver()
        editor.textStorage.delegate = observer
        editor.updateCommandHighlight(baseColor: .angrovePrimaryReadable)
        #expect(observer.edits == 0)
        editor.isPresentationSuspended = false
        editor.updateCommandHighlight(baseColor: .angrovePrimaryReadable)
        #expect(observer.edits > 0)
        #expect(editor.text == "A submitted question")
    }
}
