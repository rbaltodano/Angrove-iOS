import SwiftUI

/// Shared with Home refresh so both activate at the same visible overscroll.
enum PullDownActivation {
    static let revealedDistance: CGFloat = 84

    // The opening gesture has no scroll view to apply resistance. Approximate the
    // finger travel needed to reveal 84 points in a rubber-banding scroll view.
    static let unresistedDistance = revealedDistance / 0.55
}

struct SideMenuAtTopKey: PreferenceKey {
    static let defaultValue = true

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value && nextValue()
    }
}

struct SideMenuSearchPull {
    private(set) var didOpenSearch = false

    mutating func update(revealedDistance: CGFloat, isInteracting: Bool) -> Bool {
        guard isInteracting, !didOpenSearch,
              revealedDistance >= PullDownActivation.revealedDistance else { return false }
        didOpenSearch = true
        return true
    }
}

struct SideMenuOpeningDrag {
    private(set) var isActive = false
    private(set) var didOpenSearch = false
    var offset: CGFloat = 0
    private var canPullToSearch = false

    /// Returns true once, as soon as a grabbed sidebar is pulled down far enough.
    mutating func update(translation: CGSize, canBegin: Bool, isMenuAtTop: Bool) -> Bool {
        guard !didOpenSearch else { return false }
        if !isActive {
            guard canBegin, translation.width > 0,
                  translation.width >= abs(translation.height) else { return false }
            isActive = true
            canPullToSearch = isMenuAtTop
        }
        offset = min(345, max(0, translation.width))
        guard canPullToSearch,
              translation.height >= PullDownActivation.unresistedDistance else { return false }
        didOpenSearch = true
        return true
    }
}
