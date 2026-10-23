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

    @Test func collapsingPreservesNotificationsAndDoesNotOpenThem() {
        let center = ModelCompletionNotificationCenter()
        var opens = 0
        for index in 0..<5 {
            center.post(title: "Question \(index)", postsSystemNotification: false) { opens += 1 }
        }
        center.expandStack()
        let ids = center.notifications.map(\.id)
        center.collapseStack()
        #expect(!center.isStackExpanded)
        #expect(center.notifications.map(\.id) == ids)
        #expect(opens == 0)
        center.expandStack()
        #expect(center.isStackExpanded)
    }

    @Test func updateReturnAndInsightCompletionsShareOneStack() throws {
        let center = ModelCompletionNotificationCenter()
        var updated = 0
        var declined = 0
        center.post(title: "Prudence", kind: .insightDefinition, postsSystemNotification: false) {}
        center.post(title: "Return?", kind: .pageReturn, postsSystemNotification: false) {}
        center.setTreeUpdatePrompt(title: "Update?", onConfirm: { updated += 1 }, onDecline: { declined += 1 })
        let promptID = try #require(center.notifications.first).id
        #expect(center.notifications.map(\.kind) == [.treeUpdate, .pageReturn, .insightDefinition])
        center.expandStack()
        #expect(center.isStackExpanded)
        center.setTreeUpdatePrompt(title: "Update?", onConfirm: { updated += 1 }, onDecline: { declined += 1 })
        #expect(center.notifications.count == 3)
        #expect(center.notifications.first?.id == promptID)
        center.open(id: promptID)
        #expect(updated == 1)
        #expect(declined == 0)
        #expect(center.notifications.count == 2)
        center.setTreeUpdatePrompt(title: "Update?", onDecline: { declined += 1 })
        center.decline(id: try #require(center.notifications.first).id)
        #expect(declined == 1)
        center.setTreeUpdatePrompt(title: "Update?", onDecline: { declined += 1 })
        center.setTreeUpdatePrompt(title: nil)
        #expect(declined == 1)
        #expect(center.notifications.count == 2)
    }

    @Test func completedInsightOpensInPlaceWithoutInvokingNavigation() throws {
        let center = ModelCompletionNotificationCenter()
        let source = UUID()
        let concept = ConceptDefinition(word: "Prudence", partOfSpeech: "noun", pronunciation: "",
                                        meaning: "Practical wisdom.", example: "")
        var quoted = false
        center.onQuoteInsight = { _ in quoted = true }
        center.postInsightDefinition(concept, conversationID: source, postsSystemNotification: false)
        #expect(center.presentedInsight == nil)
        center.open(id: try #require(center.notifications.first).id)
        #expect(center.presentedInsight?.concept == concept)
        #expect(center.presentedInsight?.conversationID == source)
        #expect(!quoted)
        #expect(center.notifications.isEmpty)
        center.closeInsight()
        #expect(center.presentedInsight == nil)
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
    @Test func clickingOutsideCollapsesButClickingBetweenCardsDoesNot() async throws {
        let center = ModelCompletionNotificationCenter()
        for index in 1...3 { center.post(title: "Question \(index)", postsSystemNotification: false) {} }
        center.expandStack()
        let probe = NotificationTapProbe()
        let view = ZStack(alignment: .bottom) {
            Text("Insight")
                .font(AngroveTheme.Typography.uiLabel)
                .frame(width: 100, height: 44)
                .contentShape(Rectangle())
                .onTapGesture { probe.hovers += 1 }
                .position(x: 50, y: 70)
            ModelCompletionNotificationList(width: 175)
                .padding(16)
        }
            .frame(width: 320, height: 320, alignment: .bottom)
            .environment(\.modelCompletionNotifications, center)
            .modifier(NotificationStackDismissal(center: center))
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 320),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(500))
        host.layoutSubtreeIfNeeded()
        func click(_ point: NSPoint) throws {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(NSEvent.mouseEvent(with: type, location: point,
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                    clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
                NSApp.sendEvent(event)
            }
        }
        // The expanded rows occupy y=16...198; y=140 is the gap between two rows.
        try click(NSPoint(x: 160, y: 140))
        try await Task.sleep(for: .milliseconds(100))
        #expect(center.isStackExpanded)
        try click(NSPoint(x: 20, y: 250))
        try await Task.sleep(for: .milliseconds(100))
        #expect(!center.isStackExpanded)
        #expect(probe.hovers == 1)
        #expect(center.notifications.count == 3)
    }

    @Test func mixedStackAndInsightReaderRenderInCurrentDock() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let center = ModelCompletionNotificationCenter()
            let concept = ConceptDefinition(word: "Prudence", partOfSpeech: "noun", pronunciation: "",
                                            meaning: "Practical wisdom that guides sound judgment.", example: "")
            let sourceID = UUID()
            center.postInsightDefinition(concept, conversationID: sourceID, postsSystemNotification: false)
            let insightID = try #require(center.notifications.first).id
            center.post(title: "Return to Conversation", kind: .pageReturn, returnPage: .conversation,
                        postsSystemNotification: false) {}
            let view = ModelControlsStack(confirmationTitle: "Update?") {
                Text("Idle").font(AngroveTheme.Typography.uiLabel)
            }
                .padding(.bottom, 24)
                .frame(width: 760, height: 500, alignment: .bottom)
                .background(AngroveTheme.Colors.canvas)
                .environment(\.colorScheme, scheme)
                .environment(\.modelCompletionNotifications, center)
                .modifier(NotificationStackDismissal(center: center))
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 500),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.contentView = nil; window.close() }
            try await Task.sleep(for: .milliseconds(300))
            #expect(center.notifications.count == 3)
            #expect(center.notifications.filter { $0.kind == .treeUpdate }.count == 1)
            center.expandStack()
            for state in ["mixed", "reader"] {
                if state == "reader" { center.open(id: insightID) }
                try await Task.sleep(for: .milliseconds(500))
                host.layoutSubtreeIfNeeded()
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                let name = "angrove-notifications-\(state)-\(scheme == .light ? "light" : "dark").png"
                Attachment.record(png, named: name)
                try png.write(to: FileManager.default.temporaryDirectory.appending(path: name))
            }
            #expect(center.presentedInsight?.conversationID == sourceID)
            #expect(center.notifications.count == 2)
        }
    }

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
                .modifier(NotificationStackDismissal(center: center))
                let host = NSHostingView(rootView: view)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 320),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                defer { window.contentView = nil; window.close() }
                try await Task.sleep(for: .milliseconds(500))
                host.layoutSubtreeIfNeeded()
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                let name = "angrove-stack-\(state)-\(scheme == .light ? "light" : "dark").png"
                Attachment.record(png, named: name)
                try png.write(to: FileManager.default.temporaryDirectory.appending(path: name))
            }
        }
    }
}

@MainActor
struct NotificationArrivalRenderTests {
    @Test func arrivalsSettleWithoutMovingCardsBeyondTheVisibleThree() async throws {
        let center = ModelCompletionNotificationCenter()
        for index in 1...3 { center.post(title: "Question \(index)", postsSystemNotification: false) {} }
        let view = ModelCompletionNotificationList(width: 175)
            .padding(32)
            .frame(width: 320, height: 180)
            .background(AngroveTheme.Colors.canvas)
            .environment(\.modelCompletionNotifications, center)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(500))
        for index in 4...5 {
            center.post(title: "Question \(index)", postsSystemNotification: false) {}
            for (phase, delay) in [("arrival", 40), ("settled", 500)] {
                try await Task.sleep(for: .milliseconds(delay))
                host.layoutSubtreeIfNeeded()
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                let name = "angrove-stack-\(index)-\(phase).png"
                Attachment.record(png, named: name)
                try png.write(to: FileManager.default.temporaryDirectory.appending(path: name))
            }
        }
        #expect(center.notifications.count == 5)
    }
}

@MainActor private final class NotificationTapProbe { var hovers = 0 }
