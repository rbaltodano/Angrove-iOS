//
//  OrnamentRule.swift
//  Angrove-iOS
//

import SwiftUI

/// A hairline broken by the Jerusalem cross, echoing the side menu's footer divider.
struct OrnamentRule: View {
    var body: some View {
        HStack(spacing: 16) {
            Rectangle().fill(AngroveTheme.Colors.controlBorder).frame(height: 1)
            Image("cross-1")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(AngroveTheme.Colors.lightGreen)
            Rectangle().fill(AngroveTheme.Colors.controlBorder).frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}
