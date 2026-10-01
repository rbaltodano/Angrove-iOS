import Testing
import UIKit
import SwiftUI
@testable import Angrove_iOS

@Suite("Slash commands")
struct SlashCommandTests {
    @Test("Command color settles to green without changing the draft or selection")
    @MainActor
    func commandColorWave() async throws {
        let editor = CommandHighlightTextView(frame: CGRect(x: 0, y: 0, width: 220, height: 80))
        editor.text = "/rename Reading Notes"
        editor.selectedRange = NSRange(location: 12, length: 3)
        let selection = editor.selectedRange
        editor.updateCommandHighlight(baseColor: .angrovePrimaryReadable)
        try await Task.sleep(for: .milliseconds(1100))
        editor.layoutSubviews()
        let green = UIColor(AngroveTheme.Colors.accentGreen).resolvedColor(with: editor.traitCollection)
        #expect(editor.text == "/rename Reading Notes")
        #expect(editor.selectedRange == selection)
        #expect((editor.textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor) == green)
        #expect((editor.textStorage.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? UIColor) == .angrovePrimaryReadable)

        editor.text = "/renameNext"
        editor.updateCommandHighlight(baseColor: .angrovePrimaryReadable)
        #expect((editor.textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor) == .angrovePrimaryReadable)
        editor.stopCommandWave()
    }

    @Test("Rename accepts a prompt or a name while preserving the name's case")
    func renameInvocation() {
        #expect(SlashCommand.invocation(for: " /rename ") == .rename(nil))
        #expect(SlashCommand.invocation(for: "/ReNaMe  My Reading Notes  ") == .rename("My Reading Notes"))
        #expect(SlashCommand.invocation(for: "/renameNext") == nil)
    }

    @Test("Commands without arguments keep their existing behavior")
    func existingInvocations() {
        #expect(SlashCommand.invocation(for: "/compact") == .compact)
        #expect(SlashCommand.invocation(for: " /clear ") == .clear)
        #expect(SlashCommand.invocation(for: "/clear extra") == nil)
    }

    @Test("Navigation commands take no arguments")
    func navigationInvocations() {
        #expect(SlashCommand.invocation(for: "/new") == .newConversation)
        #expect(SlashCommand.invocation(for: " /Tree ") == .tree)
        #expect(SlashCommand.invocation(for: "/topic") == .topic)
        #expect(SlashCommand.invocation(for: "/insights") == .insights)
        #expect(SlashCommand.invocation(for: "/new idea about grace") == nil)
        #expect(SlashCommand.invocation(for: "/treehouse") == nil)
    }

    @Test("Every listed command is executable on its own")
    func listedCommandsAreExecutable() {
        for command in SlashCommand.all {
            #expect(SlashCommand.invocation(for: command.name) != nil)
        }
    }
}
