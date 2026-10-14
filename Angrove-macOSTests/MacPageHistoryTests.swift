import AppKit
import Testing
@testable import AngroveMac

@MainActor
struct MacPageHistoryTests {
    private let tree = MacWorkspacePage(destination: .insights)
    private let home = MacWorkspacePage(destination: .home)
    private let topics = MacWorkspacePage(destination: .studyTopics)

    @Test func backAndForwardTraverseWithoutChangingRecencyAndStopAtTheEnds() {
        var history = MacPageHistory()
        #expect(history.back() == nil && history.forward() == nil)
        let conversation = MacWorkspacePage(destination: .conversations, conversationID: UUID())
        for page in [conversation, tree, home] { history.visit(page) }
        let original = history.pages
        #expect(history.back() == tree)
        #expect(history.back() == conversation)
        #expect(history.back() == nil)
        #expect(history.forward() == tree)
        #expect(history.forward() == home)
        #expect(history.forward() == nil)
        #expect(history.pages == original)
    }

    @Test func actingOnThirdMostRecentPageMovesItFirstAndKeepsTheOtherPages() {
        var history = MacPageHistory()
        for page in [tree, home, topics] { history.visit(page) }
        #expect(history.back() == home)
        #expect(history.back() == tree)
        history.visit(tree)
        #expect(history.pages == [home, topics, tree])
        #expect(!history.canGoForward)
        #expect(history.back() == topics)
        #expect(history.back() == home)
        history.visit(home)
        #expect(history.pages == [topics, tree, home])
        history.visit(home)
        #expect(history.pages.count == 3)
    }

    @Test func newNavigationFromAnOlderPageKeepsForwardPagesAndOnlyFiveDistinctPages() {
        var history = MacPageHistory()
        let conversations = (0..<4).map { _ in MacWorkspacePage(destination: .conversations, conversationID: UUID()) }
        for page in [home, tree, topics] + conversations.prefix(2) { history.visit(page) }
        #expect(history.back() == conversations[0])
        history.visit(conversations[2])
        #expect(history.pages == [tree, topics, conversations[0], conversations[1], conversations[2]])
        history.visit(conversations[3])
        #expect(history.pages.count == 5)
        #expect(history.pages.first == topics)
        history.visit(conversations[0])
        #expect(history.pages.last == conversations[0])
        #expect(history.pages.count == 5)
    }

    @Test func deletedConversationIsRemovedWithoutBreakingTraversal() throws {
        var history = MacPageHistory()
        let id = UUID()
        let conversation = MacWorkspacePage(destination: .conversations, conversationID: id)
        for page in [home, conversation, tree] { history.visit(page) }
        history.removeConversation(id)
        #expect(history.current == tree)
        #expect(history.back() == home)
        #expect(history.forward() == tree)
        history.removeConversation(UUID())
        #expect(history.current == tree)
        history.removeConversation(id)
        #expect(history.pages == [home, tree])
    }

    @Test func nativeInputPromotesOnlyPageClicksAndTypingWithoutSwallowingHistoryKeys() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let observer = MacPageActivityObserver.ActivityView(onActivity: {})
        observer.frame = NSRect(x: 280, y: 0, width: 480, height: 540)
        window.contentView?.addSubview(observer)
        let editor = NSTextView(frame: NSRect(x: 400, y: 100, width: 200, height: 60))
        window.contentView?.addSubview(editor)
        window.makeFirstResponder(editor)
        defer { observer.stopMonitoring(); window.close() }
        func click(at point: NSPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        #expect(observer.isPageActivity(try click(at: NSPoint(x: 400, y: 200))))
        #expect(!observer.isPageActivity(try click(at: NSPoint(x: 100, y: 200))))
        for (flags, expected) in [(NSEvent.ModifierFlags(), true), (.command, false), ([.command, .shift], false)] {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "r",
                charactersIgnoringModifiers: "r", isARepeat: false, keyCode: 15))
            #expect(observer.isPageActivity(event) == expected)
        }
    }
}
