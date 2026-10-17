import SwiftUI

#if ANGROVE_WIDGET
enum AngroveTheme {}
#endif

extension AngroveTheme {
    enum WidgetTypography {
        #if os(macOS)
        /// Desktop and Notification Center widgets have room for the whole question.
        static let heading: Font = .system(.subheadline, design: .default, weight: .bold)
        static let question: Font = .system(.title3, design: .serif)
        static let questionLines = 5
        static let alignment: Alignment = .topLeading
        #else
        /// Accessory widgets inherit the Lock Screen's foreground treatment.
        static let heading: Font = .system(.caption, design: .default, weight: .bold)
        static let question: Font = .system(.caption, design: .default)
        static let questionLines = 2
        static let alignment: Alignment = .leading
        #endif
    }
}
