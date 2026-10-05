import SwiftUI

#if ANGROVE_WIDGET
enum AngroveTheme {}
#endif

extension AngroveTheme {
    /// Accessory widgets inherit the Lock Screen's foreground treatment.
    enum WidgetTypography {
        static let heading: Font = .system(.caption, design: .default, weight: .bold)
        static let question: Font = .system(.caption, design: .default)
    }
}
