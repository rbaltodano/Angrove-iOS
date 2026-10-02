//
//  OrnamentRule.swift
//  Angrove-iOS
//

import SwiftUI

/// A hairline broken by the app icon image, echoing the side menu's footer divider.
struct OrnamentRule: View {
    var body: some View {
        HStack(spacing: 16) {
            Rectangle().fill(AngroveTheme.Colors.controlBorder).frame(height: 1)
            AppIconImage(size: 16)
            Rectangle().fill(AngroveTheme.Colors.controlBorder).frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}
