//
//  ContextUsageCard.swift
//  Angrove-iOS
//

import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Full shared input-and-output KV-cache of the deployed Gemma 4 E4B LiteRT checkpoint.
let angroveContextWindowLimit = AngroveContextBudget.totalTokenLimit

/// Shared open/animation state for the Context row in the model-controls stack.
@Observable
final class ContextCardState {
    var isOpen = false
    var isCompacting = false
    var isCompactionComplete = false
    var dragY: CGFloat = 0
    var compactTask: Task<Void, Never>?

    func beginAutomaticCompaction() {
        withAnimation(.springStandard) {
            isOpen = true
            isCompacting = true
            isCompactionComplete = false
            dragY = 0
        }
    }

    func finishAutomaticCompaction(succeeded: Bool) {
        guard isCompacting else { return }
        guard succeeded else {
            withAnimation(.springStandard) { isCompacting = false }
            return
        }
        withAnimation(.easeInOut(duration: 0.18)) { isCompactionComplete = true }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self else { return }
            withAnimation(.springStandard) { self.isOpen = false }
            try? await Task.sleep(for: .milliseconds(450))
            self.isCompacting = false
            self.isCompactionComplete = false
        }
    }

    func reset() {
        compactTask?.cancel()
        isOpen = false
        isCompacting = false
        isCompactionComplete = false
        dragY = 0
    }
}

/// The Context card as a real row in the bottom model-controls stack.
struct ContextControlsStackCard: View {
    let contextCard: ContextCardState
    let wordCount: Int
    var wordLimit: Int = angroveContextWindowLimit
    var canCompact: Bool = false
    var onCompactContext: () async -> Bool = { false }
    var onClearConversation: () -> Void = {}

    var body: some View {
        ContextUsageCard(
            wordCount: wordCount,
            wordLimit: wordLimit,
            canCompact: canCompact,
            isCompacting: contextCard.isCompacting,
            isCompactionComplete: contextCard.isCompactionComplete,
            onCompact: beginContextCompaction,
            onClear: clearConversation,
            onArrowAppear: contextArrowDidAppear
        )
        .offset(y: contextCard.dragY)
        .gesture(contextCardDismissGesture)
        .transition(.bottomDockCard)
    }

    private var contextCardDismissGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !contextCard.isCompacting else { return }
                contextCard.dragY = max(0, value.translation.height)
            }
            .onEnded { value in
                guard !contextCard.isCompacting else { return }
                let height = value.translation.height
                let predicted = value.predictedEndTranslation.height
                if height > 100 || predicted > 180 {
                    withAnimation(.springStandard) {
                        contextCard.isOpen = false
                        contextCard.dragY = 0
                    }
                } else {
                    withAnimation(.springLively) {
                        contextCard.dragY = 0
                    }
                }
            }
    }

    private func beginContextCompaction() {
        guard canCompact, !contextCard.isCompacting else { return }
        CanvasImpactFeedback(style: .light).impactOccurred(intensity: 0.65)
        withAnimation(.springStandard) {
            contextCard.isCompacting = true
            contextCard.isCompactionComplete = false
        }
        contextCard.compactTask?.cancel()
        contextCard.compactTask = Task {
            let didCompact = await onCompactContext()
            guard !Task.isCancelled else { return }
            guard didCompact else {
                await MainActor.run {
                    withAnimation(.springStandard) {
                        contextCard.isCompacting = false
                    }
                }
                return
            }
            await MainActor.run {
                playContextCompactedHaptics()
                withAnimation(.easeInOut(duration: 0.18)) {
                    contextCard.isCompactionComplete = true
                }
            }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            await MainActor.run {
                withAnimation(.springStandard) {
                    contextCard.isOpen = false
                }
            }
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            await MainActor.run {
                contextCard.isCompacting = false
                contextCard.isCompactionComplete = false
            }
        }
    }

    private func contextArrowDidAppear() {
        guard contextCard.isCompacting, !contextCard.isCompactionComplete else { return }
        CanvasImpactFeedback(style: .light).impactOccurred(intensity: 0.55)
    }

    private func playContextCompactedHaptics() {
        let generator = CanvasImpactFeedback(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.75)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            generator.prepare()
            generator.impactOccurred(intensity: 0.75)
        }
    }

    private func clearConversation() {
        contextCard.compactTask?.cancel()
        CanvasImpactFeedback(style: .medium).impactOccurred(intensity: 0.75)
        onClearConversation()
        withAnimation(.springStandard) {
            contextCard.isOpen = false
            contextCard.isCompacting = false
            contextCard.isCompactionComplete = false
        }
    }
}

private struct ContextUsageCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let wordCount: Int
    let wordLimit: Int
    let canCompact: Bool
    let isCompacting: Bool
    let isCompactionComplete: Bool
    var onCompact: () -> Void
    var onClear: () -> Void
    var onArrowAppear: () -> Void

    @State private var hasAppeared = false
    @State private var showClearConfirmation = false

    private var progress: CGFloat {
        guard wordLimit > 0 else { return 0 }
        return min(max(CGFloat(wordCount) / CGFloat(wordLimit), 0), 1)
    }

    private var progressTrackColor: Color {
        AngroveTheme.Colors.gaugeTrack
    }

    private var progressTrackBorderColor: Color {
        AngroveTheme.Colors.gaugeTrackBorder
    }

    private var progressFillColor: Color {
        AngroveTheme.Colors.gaugeFill
    }

    var body: some View {
        // A ZStack, not a Group: Group hands its modifiers and transition to each child,
        // so the children's opacity transitions replaced the stack's scale-down removal.
        ZStack {
            if isCompacting {
                if isCompactionComplete {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .angroveIcon(.medium)
                            .foregroundColor(AngroveTheme.Colors.paragraphText.opacity(0.75))
                            .sfSymbolDrawOn()
                        Text("Compacted")
                            .font(BrandTypography.font("Figtree-SemiBold", size: 14))
                            .foregroundColor(AngroveTheme.Colors.paragraphText.opacity(0.75))
                    }
                    .transition(.opacity)
                } else {
                    HStack(spacing: 8) {
                        ContextCompactingIcon(onAppearCycle: onArrowAppear)
                        Text("Compacting")
                            .font(BrandTypography.font("Figtree-SemiBold", size: 14))
                            .foregroundColor(AngroveTheme.Colors.paragraphText.opacity(0.75))
                    }
                    .transition(.opacity)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            #if os(macOS)
                            MacPageHeading(title: "Context")
                            #else
                            Text("Context")
                                .font(BrandTypography.font("Figtree-Bold", size: 18))
                                .foregroundColor(AngroveTheme.Colors.headingText)
                            #endif
                            Spacer()
                            Text("\(formatted(wordCount)) / \(formatted(wordLimit)) tokens")
                                .font(BrandTypography.font("Figtree-Bold", size: 14))
                                .monospacedDigit()
                        }
                        .foregroundColor(AngroveTheme.Colors.paragraphText.opacity(0.75))

                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(progressTrackColor)
                                    .overlay(Capsule().stroke(progressTrackBorderColor, lineWidth: 1))
                                Capsule()
                                    .fill(progressFillColor)
                                    .frame(width: progress > 0 ? max(geometry.size.width * progress, 8) : 0)
                                    .animation(.easeInOut(duration: 0.65), value: progress)
                            }
                        }
                        .frame(height: 2)
                    }

                    HStack {
                        Button("Compact", action: onCompact)
                            .disabled(!canCompact)
                            .opacity(canCompact ? 1 : 0.35)
                        Spacer()
                        Button("Clear") { showClearConfirmation = true }
                    }
                    .font(BrandTypography.font("Figtree-Bold", size: 14))
                    .foregroundColor(AngroveTheme.Colors.paragraphText.opacity(0.75))
                    .buttonStyle(.plain)
                }
                .transition(.opacity)
            }
        }
        .padding(isCompacting ? 14 : 32)
        .frame(width: isCompacting ? 126 : 355, height: isCompacting ? 44 : nil)
        .background(AngroveTheme.Colors.canvasSecondary)
        .clipShape(RoundedRectangle(cornerRadius: isCompacting ? 22 : 36, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: isCompacting ? 22 : 36, style: .continuous)
                .stroke(AngroveTheme.Colors.popupBorder, lineWidth: 1)
        )
        .scaleEffect(hasAppeared ? 1 : 0.35, anchor: .bottom)
        .opacity(hasAppeared ? 1 : 0)
        .animation(.springStandard, value: isCompacting)
        .onAppear {
            hasAppeared = false
            DispatchQueue.main.async {
                withAnimation(.springStandard) {
                    hasAppeared = true
                }
            }
        }
        .alert("Clear conversation context?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive, action: onClear)
        } message: {
            Text("This removes every question and response in this conversation and starts it fresh, so the model no longer has any of the earlier context to build on. Insights you've saved are kept. This can't be undone.")
        }
    }

    private func formatted(_ count: Int) -> String {
        if count >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

private struct ContextCompactingIcon: View {
    var onAppearCycle: () -> Void

    @State private var rotation = Double([0, 45, 90, 135, 180, 225, 270].randomElement() ?? 0)
    @State private var iconOpacity: Double = 0
    @State private var iconScale: CGFloat = 0.86
    @State private var iconBlur: CGFloat = 4

    var body: some View {
        Image(systemName: "line.diagonal.trianglehead.up.right")
            .angroveIcon(.medium)
            .foregroundColor(AngroveTheme.Colors.paragraphText.opacity(0.75))
            .rotationEffect(.degrees(rotation))
            .opacity(iconOpacity)
            .scaleEffect(iconScale)
            .blur(radius: iconBlur)
            .frame(width: 16, height: 16)
            .task {
                while !Task.isCancelled {
                    onAppearCycle()
                    withAnimation(.easeOut(duration: 0.15)) {
                        iconOpacity = 1
                        iconScale = 1
                        iconBlur = 0
                    }
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeIn(duration: 0.15)) {
                        iconOpacity = 0
                        iconScale = 0.86
                        iconBlur = 4
                    }
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    let directions = [0, 45, 90, 135, 180, 225, 270].map(Double.init)
                    rotation = directions.filter { $0 != rotation }.randomElement() ?? 0
                }
            }
    }
}
