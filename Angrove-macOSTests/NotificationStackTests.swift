import AppKit
import SwiftUI
import Testing
@testable import AngroveMac

@Suite("Notification stack")
@MainActor
struct NotificationStackTests {
    @Test func defaultsToNewestCardAndExpansionDoesNotOpenContent() throws {
        let center = ModelCompletionNotificationCenter()
        var opens = 0
        center.post(title: "Older", postsSystemNotification: false) { opens += 1 }
        center.post(title: "Newest", kind: .insightDefinition, postsSystemNotification: false) { opens += 1 }
        #expect(center.notifications.map(\.title) == ["Newest", "Older"])
        #expect(!center.showsExpandedStack(presentingCard: false))
        center.expandStack()
        #expect(center.showsExpandedStack(presentingCard: false))
        #expect(opens == 0)
    }

    @Test func openingInsightTemporarilyFoldsTheRemainingNotifications() throws {
        let center = ModelCompletionNotificationCenter()
        var presentingCard = false
        center.post(title: "Question", postsSystemNotification: false) {}
        center.post(title: "Another Insight", kind: .insightDefinition, postsSystemNotification: false) {}
        center.post(title: "Prudence", kind: .insightDefinition, postsSystemNotification: false) { presentingCard = true }
        center.expandStack()
        let insight = try #require(center.notifications.first)
        center.open(id: insight.id)
        #expect(presentingCard)
        #expect(center.notifications.count == 2)
        #expect(!center.showsExpandedStack(presentingCard: presentingCard))
        // A new completion while the card is open joins the folded stack.
        center.post(title: "New completion", postsSystemNotification: false) {}
        #expect(!center.showsExpandedStack(presentingCard: presentingCard))
        presentingCard = false
        #expect(center.showsExpandedStack(presentingCard: presentingCard))
        #expect(!center.notifications.contains { $0.id == insight.id })
    }

    @Test func dismissingDoesNotOpenAndAnEmptiedStackResets() throws {
        let center = ModelCompletionNotificationCenter()
        var opened = false
        center.post(title: "Question", postsSystemNotification: false) { opened = true }
        center.post(title: "Return", kind: .pageReturn, postsSystemNotification: false) { opened = true }
        center.expandStack()
        center.dismissPageReturn()
        center.dismiss(id: try #require(center.notifications.first).id)
        #expect(!opened)
        #expect(!center.isStackExpanded)
        center.post(title: "Next", postsSystemNotification: false) {}
        center.post(title: "Next again", postsSystemNotification: false) {}
        #expect(!center.isStackExpanded)
    }

    @Test func oneNotificationOpensDirectlyAndCannotExpand() throws {
        let center = ModelCompletionNotificationCenter()
        var opened = false
        center.post(title: "Only", postsSystemNotification: false) { opened = true }
        center.expandStack()
        #expect(!center.isStackExpanded)
        center.open(id: try #require(center.notifications.first).id)
        #expect(opened)
        #expect(center.notifications.isEmpty)
    }
}

@MainActor
struct NotificationStackRenderTests {
    @Test func compactExpandedAndInsightPresentationAtSmallWidths() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let center = ModelCompletionNotificationCenter()
            center.post(title: "What is practical wisdom?", postsSystemNotification: false) {}
            center.post(title: "Temperance", kind: .insightDefinition, postsSystemNotification: false) {}
            center.post(title: "Prudence", kind: .insightDefinition, postsSystemNotification: false) {}
            for state in ["collapsed", "expanded", "insight"] {
                if state != "collapsed" { center.expandStack() }
                let view = VStack(spacing: 16) {
                    ModelCompletionNotificationList(width: 288, presentingCard: state == "insight")
                    if state == "insight" {
                        Text("Prudence").font(AngroveTheme.Typography.uiLabel)
                            .foregroundStyle(AngroveTheme.Colors.headingText)
                            .frame(width: 288, height: 120)
                            .background(AngroveTheme.Colors.canvasSecondary, in: RoundedRectangle(cornerRadius: 36))
                    }
                }
                .padding(16)
                .frame(width: 320, height: 320, alignment: .bottom)
                .background(AngroveTheme.Colors.canvas)
                .environment(\.modelCompletionNotifications, center)
                .environment(\.colorScheme, scheme)
                let host = NSHostingView(rootView: view)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 320),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                defer { window.contentView = nil; window.close() }
                try await Task.sleep(for: .milliseconds(100))
                host.layoutSubtreeIfNeeded()
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                Attachment.record(png, named: "angrove-stack-\(state)-\(scheme == .light ? "light" : "dark").png")
            }
        }
    }
}
