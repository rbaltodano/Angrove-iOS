import AppKit
import Testing
@testable import AngroveMac

struct MacCanvasScrollGestureTests {
    @Test func canvasOwnsPanAcrossConversationAndViewportEdgesUntilRelease() {
        var route = CanvasScrollGestureRoute()
        var lookups = 0
        #expect(route.takesCanvas(phase: .began, momentum: [], timestamp: 1, inside: true) {
            lookups += 1
            return false
        })
        for time in [1.01, 1.5, 3.0] {
            #expect(route.takesCanvas(phase: .changed, momentum: [], timestamp: time, inside: false) {
                lookups += 1
                return true
            })
        }
        #expect(route.takesCanvas(phase: .ended, momentum: [], timestamp: 3.1, inside: true) { true })
        #expect(lookups == 1, "Crossing cards during a pan must not hit-test or activate their scroll views")
        #expect(!route.takesCanvas(phase: .began, momentum: [], timestamp: 3.2, inside: true) { true })
    }

    @Test func conversationOwnsItsScrollUntilTheNextGesture() {
        var route = CanvasScrollGestureRoute()
        #expect(!route.takesCanvas(phase: .began, momentum: [], timestamp: 1, inside: true) { true })
        #expect(!route.takesCanvas(phase: .changed, momentum: [], timestamp: 1.1, inside: true) { false })
        #expect(!route.takesCanvas(phase: .ended, momentum: [], timestamp: 1.2, inside: true) { false })
        #expect(route.takesCanvas(phase: .began, momentum: [], timestamp: 1.3, inside: true) { false })
    }

    @Test(arguments: [false, true]) func momentumRetainsTheOriginalSurface(startsOverConversation: Bool) {
        var route = CanvasScrollGestureRoute()
        let canvas = !startsOverConversation
        #expect(route.takesCanvas(phase: .began, momentum: [], timestamp: 1, inside: true) { startsOverConversation } == canvas)
        #expect(route.takesCanvas(phase: .ended, momentum: [], timestamp: 1.1, inside: true) { !startsOverConversation } == canvas)
        for (phase, time) in [(NSEvent.Phase.began, 1.11), (.changed, 1.3), (.ended, 2.0)] {
            #expect(route.takesCanvas(phase: [], momentum: phase, timestamp: time, inside: true) { !startsOverConversation } == canvas)
        }
        #expect(route.takesCanvas(phase: .began, momentum: [], timestamp: 2.1, inside: true) { false })
    }

    @Test func wheelBurstsLockTheirTargetAndResetAfterAPause() {
        var route = CanvasScrollGestureRoute()
        #expect(route.takesCanvas(phase: [], momentum: [], timestamp: 1, inside: true) { false })
        #expect(route.takesCanvas(phase: [], momentum: [], timestamp: 1.05, inside: true) { true })
        #expect(!route.takesCanvas(phase: [], momentum: [], timestamp: 1.4, inside: true) { true })
        #expect(!route.takesCanvas(phase: [], momentum: [], timestamp: 1.45, inside: true) { false })
        #expect(route.takesCanvas(phase: [], momentum: [], timestamp: 1.8, inside: true) { false })
    }

    @Test func cancellationAndTeardownReleaseOwnership() {
        var route = CanvasScrollGestureRoute()
        #expect(route.takesCanvas(phase: .began, momentum: [], timestamp: 1, inside: true) { false })
        #expect(route.takesCanvas(phase: .cancelled, momentum: [], timestamp: 1.1, inside: true) { true })
        #expect(!route.takesCanvas(phase: .began, momentum: [], timestamp: 1.2, inside: true) { true })
        route.reset()
        #expect(route.takesCanvas(phase: .changed, momentum: [], timestamp: 1.3, inside: true) { false })
    }

    @Test func gestureBeginningOutsideCanvasCannotTakeOverMidway() {
        var route = CanvasScrollGestureRoute()
        #expect(!route.takesCanvas(phase: .began, momentum: [], timestamp: 1, inside: false) { false })
        #expect(!route.takesCanvas(phase: .changed, momentum: [], timestamp: 1.1, inside: true) { false })
        #expect(route.takesCanvas(phase: .began, momentum: [], timestamp: 1.2, inside: true) { false })
    }
}
