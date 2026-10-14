import Testing
@testable import AngroveMac

struct MacSidebarLayoutTests {
    @Test func expandedSidebarStopsAt280UntilTheFull84PointOvershoot() {
        let origin = MacSidebarLayout()
        var sidebar = origin
        sidebar.drag(from: origin, translation: -83, windowWidth: 1440)
        #expect(sidebar.width(in: 1440) == 280)
        #expect(!sidebar.isCompact)
        sidebar.drag(from: origin, translation: -84, windowWidth: 1440)
        #expect(sidebar.isCompact)
        #expect(sidebar.width(in: 1440) == 92)
    }

    @Test func widerSidebarMustReachTheMinimumBeforeOvershooting() {
        var origin = MacSidebarLayout()
        origin.drag(from: origin, translation: 150, windowWidth: 1440)
        var sidebar = origin
        sidebar.drag(from: origin, translation: -233, windowWidth: 1440)
        #expect(!sidebar.isCompact)
        sidebar.drag(from: origin, translation: -234, windowWidth: 1440)
        #expect(sidebar.isCompact)
    }

    @Test func reversingTheSameDragReversesCollapse() {
        let origin = MacSidebarLayout()
        var sidebar = origin
        sidebar.drag(from: origin, translation: -100, windowWidth: 1440)
        #expect(sidebar.isCompact)
        sidebar.drag(from: origin, translation: -20, windowWidth: 1440)
        #expect(!sidebar.isCompact)
        #expect(sidebar.width(in: 1440) == 280)
    }

    @Test func compactSidebarReopensWithAnOutwardDrag() {
        var origin = MacSidebarLayout()
        origin.toggleCompact()
        var sidebar = origin
        sidebar.drag(from: origin, translation: 83, windowWidth: 1440)
        #expect(sidebar.isCompact)
        sidebar.drag(from: origin, translation: 84, windowWidth: 1440)
        #expect(!sidebar.isCompact)
        #expect(sidebar.width(in: 1440) == 280)
        sidebar.drag(from: origin, translation: 184, windowWidth: 1440)
        #expect(sidebar.width(in: 1440) == 380)
    }

    @Test func resizeLeavesSpaceForThePageAndRemembersWidthAcrossWindowChanges() {
        var sidebar = MacSidebarLayout()
        sidebar.drag(from: sidebar, translation: 200, windowWidth: 1440)
        #expect(sidebar.width(in: 1440) == 480)
        #expect(sidebar.width(in: 760) == 410)
        #expect(sidebar.width(in: 1440) == 480)
        sidebar.drag(from: sidebar, translation: 2000, windowWidth: 760)
        #expect(sidebar.width(in: 760) == 410)
        #expect(!sidebar.isCompact)
    }
}
