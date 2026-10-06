//
//  StudyBranchDockControls.swift
//  Angrove-iOS
//

import SwiftUI
import UIKit

/// The persistent dock content shown while Branch is the active Study tool.
struct StudyBranchDockControls: View {
    private enum Layout {
        /// Matches the normal dock: 16 pt controls with 24 pt above and below.
        static let controlHeight: CGFloat = 64
        static let countPillWidth: CGFloat = 230
        static let placePillWidth: CGFloat = 118
        static let interPillSpacing: CGFloat = 8
    }

    let count: Int
    let onCountChange: (Int) -> Void
    /// Set when Study is closing, so Place tucks away before the dock changes back.
    var isLeaving: Bool = false
    var isBusy: Bool = false
    var onConfirm: () -> Void = {}

    @State private var showsPlaceAction = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            controls(compact: false)
            controls(compact: true)
        }
        .animation(.springStandard, value: showsPlaceAction)
        .onAppear {
            showsPlaceAction = false
            withAnimation(.springStandard.delay(0.18)) { showsPlaceAction = true }
        }
        .onChange(of: isLeaving) { _, leaving in
            withAnimation(.springQuick) { showsPlaceAction = !leaving }
        }
    }

    private func controls(compact: Bool) -> some View {
        let countWidth: CGFloat = compact ? 180 : Layout.countPillWidth
        let actionWidth: CGFloat = compact ? 88 : Layout.placePillWidth
        let fontSize: CGFloat = compact ? 13 : 14
        return HStack(spacing: Layout.interPillSpacing) {
            HStack(spacing: compact ? 10 : 14) {
                Button(action: increment) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 14, height: 24)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle().inset(by: -15))
                .disabled(isBusy || count >= 6)
                .opacity(count >= 6 ? 0.4 : 1)
                .accessibilityLabel("Add an Insight")

                Text("\(count)", comment: "Number of Insights to create.")
                    .font(.custom("Figtree-Bold", size: fontSize, relativeTo: .subheadline))
                Text("New Insights")
                    .font(.custom("Figtree-SemiBold", size: fontSize, relativeTo: .subheadline))

                Button(action: decrement) {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 14, height: 24)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle().inset(by: -15))
                .disabled(isBusy || count <= 2)
                .opacity(count <= 2 ? 0.4 : 1)
                .accessibilityLabel("Remove an Insight")
            }
            .foregroundStyle(AngroveTheme.Colors.paragraphText.opacity(0.75))
            .padding(.horizontal, compact ? 14 : 32)
            .frame(
                width: showsPlaceAction
                    ? countWidth
                    : countWidth + actionWidth + Layout.interPillSpacing,
                height: Layout.controlHeight
            )
            .background(AngroveTheme.Colors.canvasSecondary, in: Capsule())
            .overlay {
                Capsule().stroke(AngroveTheme.Colors.paragraphText.opacity(0.04), lineWidth: 1)
            }

            Button(action: place) {
                Label(isBusy ? "Loading" : "Branch", systemImage: "arrow.triangle.branch")
                    .font(.custom("Figtree-Bold", size: fontSize, relativeTo: .subheadline))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AngroveTheme.Colors.lightGreen)
            .frame(width: actionWidth, height: Layout.controlHeight)
            .background(AngroveTheme.Colors.canvasSecondary, in: Capsule())
            .overlay {
                Capsule().stroke(AngroveTheme.Colors.paragraphText.opacity(0.04), lineWidth: 1)
            }
            .frame(width: showsPlaceAction ? actionWidth : 0)
            .clipped()
            .opacity(showsPlaceAction ? 1 : 0)
            .blur(radius: showsPlaceAction ? 0 : 8)
            .scaleEffect(showsPlaceAction ? 1 : 1.05)
            .allowsHitTesting(showsPlaceAction && !isBusy)
            .disabled(isBusy)
            .accessibilityLabel("Branch into \(count) new Insights")
        }
    }

    private func increment() {
        guard count < 6 else { return }
        onCountChange(count + 1)
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.62)
    }

    private func decrement() {
        guard count > 2 else { return }
        onCountChange(count - 1)
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.62)
    }

    private func place() {
        guard !isBusy else { return }
        onConfirm()
    }
}
