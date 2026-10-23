import AppKit
import SwiftUI

/// Keep transcript observation narrow without nesting a second hosting controller. The outer
/// canvas host owns both drawing and input transforms, so Insight buttons remain clickable
/// at every zoom level. Inactive conversations still use the scene's cached surfaces.
struct WorktreeConversationSurface: View, Equatable {
    let card: WorktreeQuestionCard

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.card == rhs.card }

    var body: some View {
        MacContextMenuContainer { card.equatable() }
            .fixedSize()
    }
}

/// Non-observed per-card activity: scrolling keeps its native renderer attached until settled.
@MainActor final class WorktreeConversationScrollActivity {
    var onScroll: (() -> Void)?
}

extension EnvironmentValues {
    @Entry var worktreeConversationScrollActivity: WorktreeConversationScrollActivity? = nil
}
