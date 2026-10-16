import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

struct MacWorktreeCommandTests {
    @Test func quotedQuestionThenLabelQueuesBoth() {
        let input = WorktreeCommandParser.parse(#""Who was St. Thomas Aquinas?" /rename"#, requiresQuotes: true)
        #expect(input == WorktreeInput(question: "Who was St. Thomas Aquinas?", commands: [.label(nil)]))
    }

    @Test func renameCarriesTheTypedLabelAndLabelIsGone() {
        #expect(WorktreeCommandParser.parse("/rename Early Church", requiresQuotes: true)
            == WorktreeInput(question: nil, commands: [.label("Early Church")]))
        #expect(WorktreeCommandParser.parse("/label Early Church", requiresQuotes: true).commands.isEmpty)
    }

    @Test func commandsRunInTypedOrder() {
        #expect(WorktreeCommandParser.parse("/rename First /rename", requiresQuotes: true).commands
            == [.label("First"), .label(nil)])
    }

    @Test func canvasTextNeedsQuotesButFollowUpsDoNot() {
        #expect(WorktreeCommandParser.parse("plain note /rename", requiresQuotes: true).question == nil)
        #expect(WorktreeCommandParser.parse("what came next? /rename", requiresQuotes: false)
            == WorktreeInput(question: "what came next?", commands: [.label(nil)]))
    }

    @Test func quotesInsideAQuestionSurvive() {
        #expect(WorktreeCommandParser.parse(#""What does "being" mean?""#, requiresQuotes: true).question
            == #"What does "being" mean?"#)
    }

    @Test func onlyStandaloneCommandWordsAreRecognised() {
        #expect(WorktreeCommandParser.commandRanges(in: "a/rename /renames /RENAME").count == 1)
        #expect(WorktreeCommandParser.parse("/renames", requiresQuotes: true).commands.isEmpty)
    }

    @Test func defineTakesItsTermAndMayBeEmpty() {
        #expect(WorktreeCommandParser.parse("/define the Didache /rename", requiresQuotes: true).commands
            == [.define("the Didache"), .label(nil)])
        #expect(WorktreeCommandParser.parse("/define", requiresQuotes: true).commands == [.define(nil)])
    }

    @Test func summarizeIsObjectDependentButLabelIsNot() {
        let commands = WorktreeCommandParser.parse("/summarize /rename", requiresQuotes: true).commands
        #expect(commands == [.summarize, .label(nil)])
        #expect(commands.map(\.isObjectDependent) == [true, false])
        #expect(!WorktreeCommand.define("grace").isObjectDependent)
        #expect(WorktreeCommand.define(nil).isObjectDependent)
    }

    @Test func headingTakesItsTextAndNeedsNoSelection() {
        let commands = WorktreeCommandParser.parse("/heading The Early Church", requiresQuotes: true).commands
        #expect(commands == [.heading("The Early Church")])
        #expect(!commands[0].isObjectDependent)
        #expect(WorktreeCommandParser.parse("/heading", requiresQuotes: true).commands == [.heading(nil)])
    }

    @Test func helpIsRetiredAndTheGuideStillParses() {
        #expect(WorktreeCommandParser.parse("/help", requiresQuotes: true).commands.isEmpty)
        for entry in WorktreeCommandGuide.entries {
            #expect(WorktreeCommandParser.commandRanges(in: entry.name).count == 1)
        }
    }

    @Test func shortFormsRunTheSameCommands() {
        #expect(WorktreeCommandParser.parse("/h The Early Church", requiresQuotes: true).commands == [.heading("The Early Church")])
        #expect(WorktreeCommandParser.parse("/r", requiresQuotes: true).commands == [.label(nil)])
        #expect(WorktreeCommandParser.parse("/s /D grace", requiresQuotes: true).commands == [.summarize, .define("grace")])
        #expect(WorktreeCommandParser.parse("/f", requiresQuotes: true).commands == [.file])
        #expect(WorktreeCommandParser.parse("/file", requiresQuotes: true).commands == [.file])
        // Only standing alone: "and/or" and "w/s" stay text.
        #expect(WorktreeCommandParser.commandRanges(in: "and/or w/s /sx").isEmpty)
    }

    @Test func everyToolCommandParsesAndShortcutsMatchTheCard() {
        for tool in WorktreeTool.allCases {
            guard let command = tool.command else { continue }
            #expect(WorktreeCommandParser.commandRanges(in: command.full).count == 1)
            #expect(WorktreeCommandParser.commandRanges(in: command.short).count == 1)
        }
        #expect(WorktreeTool.forShortcut(key: "H", shift: false) == .heading)
        // Shift-Command-H stays Home.
        #expect(WorktreeTool.forShortcut(key: "h", shift: true) == nil)
        #expect(WorktreeTool.forShortcut(key: "r", shift: false) == .rename)
        #expect(WorktreeTool.forShortcut(key: "s", shift: false) == .summarize)
        #expect(WorktreeTool.forShortcut(key: "s", shift: true) == nil)
        #expect(WorktreeTool.forShortcut(key: "d", shift: false) == .define)
        #expect(WorktreeTool.forShortcut(key: "k", shift: true) == .file)
    }

    @MainActor @Test func recognisedCommandsTurnGreen() {
        let editor = WorktreeTextEditor.Editor()
        editor.highlightsCommands = true
        editor.reduceMotion = true
        editor.baseColor = .black
        editor.string = "/rename Early Church"
        editor.refreshHighlight()
        let storage = editor.textStorage!
        #expect(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
            == NSColor(AngroveTheme.Colors.lightGreen))
        #expect(storage.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? NSColor == .black)
    }

    @MainActor @Test func summaryMaterialKeepsNewestTurnsBehindTheCompactedSummary() {
        let transcript: [ChatBlock] = [.user("old", nil, []), .text(String(repeating: "a", count: 50)),
                                       .user("new", nil, []), .text("short")]
        let fitted = WorktreeBoard.fitting(transcript, earlier: "earlier summary", budget: 40)
        #expect(fitted == [.text("earlier summary"), .user("new", nil, []), .text("short")])
        #expect(WorktreeBoard.fitting(transcript, earlier: nil, budget: 1000) == transcript)
    }
}
