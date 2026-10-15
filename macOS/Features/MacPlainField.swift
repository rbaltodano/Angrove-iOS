import SwiftUI

extension View {
    /// A bare text field: no border, no focus ring, no highlight; only the typing cursor.
    func macPlainField() -> some View {
        self
            .textFieldStyle(.plain)
            .focusEffectDisabled()
            .tint(AngroveTheme.Colors.lightGreen)
    }
}
