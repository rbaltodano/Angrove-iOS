//
//  OrnamentRule.swift
//  Aquinas-iOS
//

import SwiftUI

/// A hairline broken by the Jerusalem cross, echoing the side menu's footer divider.
struct OrnamentRule: View {
    var body: some View {
        HStack(spacing: 16) {
            Rectangle().fill(AquinasTheme.Colors.controlBorder).frame(height: 1)
            Image("cross-1")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(AquinasTheme.Colors.lightGreen)
            Rectangle().fill(AquinasTheme.Colors.controlBorder).frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}
