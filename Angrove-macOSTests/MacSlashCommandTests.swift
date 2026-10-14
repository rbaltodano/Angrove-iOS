import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

struct MacSlashCommandTests {
    @Test func sharedCommandsParseWithoutInterceptingOrdinaryQuestions() {
        for command in SlashCommand.all {
            #expect(SlashCommand.invocation(for: command.name) != nil)
        }
        #expect(SlashCommand.invocation(for: " /TREE \n") == .tree)
        #expect(SlashCommand.invocation(for: "/ReNaMe Reading Notes") == .rename("Reading Notes"))
        #expect(SlashCommand.invocation(for: "/rename") == .rename(nil))
        #expect(SlashCommand.invocation(for: "/treehouse") == nil)
        #expect(SlashCommand.invocation(for: "/clear extra") == nil)
        #expect(SlashCommand.invocation(for: "/define prudence") == .define("prudence"))
        #expect(SlashCommand.invocation(for: "/define prudence")?.producesResponse == true)
        #expect(SlashCommand.invocation(for: "/define")?.producesResponse == false)
    }

    @MainActor @Test func manualNameAndTopicSurviveClear() {
        let session = MacConversationState()
        session.configure(preview: true)
        let conversationID = session.id
        let topicID = session.selectedBranch
        session.rename(to: "  Reading Notes  ")
        session.assignTopic(topicID)
        session.rename(to: "  ")
        #expect(session.title == "Reading Notes")
        session.clear(runtime: MacApplicationRuntime(testModel: UnavailableAngroveModel(), queue: ModelTaskQueue()))
        #expect(session.id == conversationID)
        #expect(session.title == "Reading Notes")
        #expect(session.studyTopicID == topicID)
        #expect(session.transcript.isEmpty)
    }
    @MainActor @Test func commandColorPreservesTextSelectionAndArgumentColor() {
        let editor = MacCommandEditor.Editor(frame: NSRect(x: 0, y: 0, width: 220, height: 80))
        editor.reduceMotion = true
        editor.string = "/ReNaMe Reading Notes"
        let selection = NSRange(location: 12, length: 3)
        editor.setSelectedRange(selection)
        editor.refreshHighlight()
        #expect(editor.string == "/ReNaMe Reading Notes")
        #expect(editor.selectedRange() == selection)
        #expect(editor.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == NSColor(AngroveTheme.Colors.lightGreen))
        #expect(editor.textStorage?.attribute(.foregroundColor, at: 9, effectiveRange: nil) as? NSColor == NSColor(AngroveTheme.Colors.primaryReadable))
        editor.string = "/treehouse"
        editor.refreshHighlight()
        #expect(editor.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == NSColor(AngroveTheme.Colors.primaryReadable))
        #expect(editor.timer == nil)
    }

    @MainActor @Test func editorReturnAndEscapeRouteToComposerActions() {
        var submitted = false
        var dismissed = false
        let parent = MacCommandEditor(text: .constant("/tree"), isFocused: .constant(true),
            reduceMotion: true, onSubmit: { submitted = true }, onEscape: { dismissed = true })
        let coordinator = parent.makeCoordinator()
        let editor = MacCommandEditor.Editor()
        #expect(coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(submitted)
        #expect(coordinator.textView(editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(dismissed)
    }
}
