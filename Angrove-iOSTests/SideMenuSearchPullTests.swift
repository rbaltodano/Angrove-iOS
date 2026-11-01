import SwiftUI
import Testing
@testable import Angrove_iOS

@Suite("Sidebar pull to search")
struct SideMenuSearchPullTests {
    @Test("Open sidebar requires a live pull past Home's refresh distance")
    func openSidebarPull() {
        var pull = SideMenuSearchPull()
        let activation1 = pull.update(revealedDistance: 100, isInteracting: false)
        #expect(!activation1)
        let activation2 = pull.update(revealedDistance: 83, isInteracting: true)
        #expect(!activation2)
        let activation3 = pull.update(revealedDistance: 84, isInteracting: true)
        #expect(activation3)
        let activation4 = pull.update(revealedDistance: 120, isInteracting: true)
        #expect(!activation4)
    }

    @Test("A partially opened sidebar can turn down and open search before release")
    func lShapedOpening() {
        var drag = SideMenuOpeningDrag()
        let activation5 = drag.update(translation: CGSize(width: 24, height: 2), canBegin: true, isMenuAtTop: true)
        #expect(!activation5)
        #expect(drag.isActive)
        let activation6 = drag.update(translation: CGSize(width: 30, height: 160), canBegin: false, isMenuAtTop: true)
        #expect(activation6)
        #expect(drag.offset == 30)
        let activation7 = drag.update(translation: CGSize(width: 30, height: 200), canBegin: true, isMenuAtTop: true)
        #expect(!activation7)
    }

    @Test("A diagonal opening can activate search in one swipe")
    func diagonalOpening() {
        var drag = SideMenuOpeningDrag()
        let activation8 = drag.update(translation: CGSize(width: 12, height: 12), canBegin: true, isMenuAtTop: true)
        #expect(!activation8)
        let activation9 = drag.update(translation: CGSize(width: 160, height: 160), canBegin: true, isMenuAtTop: true)
        #expect(activation9)
    }

    @Test("Vertical page scrolling and blocked origins do not grab the sidebar")
    func rejectedOpening() {
        var drag = SideMenuOpeningDrag()
        let activation10 = drag.update(translation: CGSize(width: 10, height: 160), canBegin: true, isMenuAtTop: true)
        #expect(!activation10)
        #expect(!drag.isActive)
        let activation11 = drag.update(translation: CGSize(width: 180, height: 160), canBegin: false, isMenuAtTop: true)
        #expect(!activation11)
        #expect(!drag.isActive)
    }

    @Test("A sidebar scrolled away from the top only opens normally")
    func scrolledSidebar() {
        var drag = SideMenuOpeningDrag()
        let activation12 = drag.update(translation: CGSize(width: 20, height: 0), canBegin: true, isMenuAtTop: false)
        #expect(!activation12)
        let activation13 = drag.update(translation: CGSize(width: 50, height: 200), canBegin: true, isMenuAtTop: true)
        #expect(!activation13)
        #expect(drag.isActive)
        #expect(!drag.didOpenSearch)
    }
}
