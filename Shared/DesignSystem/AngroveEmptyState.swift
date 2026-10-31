//
//  AngroveEmptyState.swift
//  Angrove-iOS
//

import SwiftUI

/// Shared empty-state treatment: icon, heading, and supporting copy, centered.
/// Mirrors the Insight Tree's empty state so list screens read as one system.
struct AngroveEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            // No sfSymbolDrawOn() here: that modifier hides the icon and reveals it on its own
            // independent, delayed timer, so it doesn't move with whatever transition the
            // container uses to bring the rest of the empty state in — it just pops in afterward
            // at its resting spot while the text visibly slides. A plain image participates in
            // the container's transition like every other view here, so it all animates together.
            Image(systemName: systemImage)
                .angroveIcon(.hero)
                .foregroundColor(AngroveTheme.Colors.lightGreen)

            #if os(macOS)
            MacPageHeading(title: title, font: .baskervilleHeading1, color: AngroveTheme.Colors.primaryReadable)
            #else
            Text(title)
                .font(.baskervilleHeading1)
                .foregroundColor(AngroveTheme.Colors.primaryReadable)
            #endif

            Text(message)
                .paragraphFont()
                .lineSpacing(6)
                .multilineTextAlignment(.center)
                .foregroundColor(AngroveTheme.Colors.paragraphText)
                .frame(maxWidth: 280)
                #if os(macOS)
                .settingsTextReveal()
                #endif
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
