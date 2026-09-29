//
//  ModelControlsHost.swift
//  Aquinas-iOS
//

import SwiftUI

private struct ModelControlsReservedHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var modelControlsReservedHeight: CGFloat {
        get { self[ModelControlsReservedHeightKey.self] }
        set { self[ModelControlsReservedHeightKey.self] = newValue }
    }
}

/// What the visible page wants the app's single Model Controls bar to show.
///
/// Pages never render their own bar. A page-specific controls view (`InquiryControlDock`,
/// `PageModelControls`, `LibraryModelControls`) stays mounted invisibly inside its page — so it
/// keeps owning its state — and publishes this description. `ModelControlsHost`, mounted once
/// by the app shell, renders it. Switching pages therefore swaps only the buttons inside one
/// persistent pill (blurring out and in, per DESIGN.md) instead of replacing the whole surface.
struct ModelControlsConfiguration {
    /// Identifies the publishing surface; a change crossfades the buttons inside the pill.
    var id: String
    /// Nested surfaces (a reader, a conversation, a Study Topic tree) outrank their page.
    var priority: Int = 0

    // Stack above the pill.
    var showsScrollToBottom = false
    var onScrollToBottom: () -> Void = {}
    var contextCard: ContextCardState? = nil
    var contextWordCount = 0
    var contextWordLimit = aquinasContextWindowLimit
    var canCompactContext = false
    var onCompactContext: () async -> Bool = { false }
    var onClearConversation: () -> Void = {}
    var modelTasksPopupState: ModelTasksPopupState? = nil
    var modelTasks: ModelTaskQueue? = nil
    var supplementalPopupIsOpen = false
    var supplementalPopup: AnyView? = nil
    var confirmationTitle: String? = nil
    var onConfirm: () -> Void = {}
    var onDecline: () -> Void = {}
    var controlsUpdateKey = ""

    // The pill. `buttons == nil` tucks the pill away.
    var buttons: AnyView? = nil
    var pillHorizontalPadding: CGFloat = 32
    var pillVerticalPadding: CGFloat = 24
    var showsPillChrome = true
    var isControlButtonPressed = false
    /// Replaces the pill in place (e.g. the expanded Insight search field).
    var pillReplacement: AnyView? = nil

    // Placement.
    var bottomPadding: CGFloat = 24
    var maxWidth: CGFloat? = nil
    var alignment: Alignment = .center
    var showsStandardFade = true
    /// An additional taller fade behind the controls: height and its bottom opacity.
    var extraFade: (height: CGFloat, opacity: Double)? = nil
}

struct ModelControlsPreferenceKey: PreferenceKey {
    static var defaultValue: ModelControlsConfiguration? = nil

    static func reduce(
        value: inout ModelControlsConfiguration?,
        nextValue: () -> ModelControlsConfiguration?
    ) {
        guard let next = nextValue() else { return }
        if let current = value, current.priority > next.priority { return }
        value = next
    }
}

extension View {
    /// Publishes this page's controls to the shell's single `ModelControlsHost`.
    func modelControls(_ configuration: ModelControlsConfiguration) -> some View {
        preference(key: ModelControlsPreferenceKey.self, value: configuration)
    }
}

/// The one Model Controls bar in the app. Mounted once by the shell; its stack and pill keep
/// their identity across every page while the published buttons change inside them.
struct ModelControlsHost: View {
    let configuration: ModelControlsConfiguration?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var measuredHeight: CGFloat?

    private static let empty = ModelControlsConfiguration(id: "none")

    var body: some View {
        let c = configuration ?? Self.empty
        ModelControlsStack(
            showsScrollToBottom: c.showsScrollToBottom,
            onScrollToBottom: c.onScrollToBottom,
            contextCard: c.contextCard,
            contextWordCount: c.contextWordCount,
            contextWordLimit: c.contextWordLimit,
            canCompactContext: c.canCompactContext,
            onCompactContext: c.onCompactContext,
            onClearConversation: c.onClearConversation,
            modelTasksPopupState: c.modelTasksPopupState,
            modelTasks: c.modelTasks,
            supplementalPopupIsOpen: c.supplementalPopupIsOpen,
            supplementalPopup: c.supplementalPopup,
            confirmationTitle: c.confirmationTitle,
            onConfirm: c.onConfirm,
            onDecline: c.onDecline,
            controlsUpdateKey: "\(c.id)|\(c.controlsUpdateKey)"
        ) {
            ZStack(alignment: .top) {
                if let buttons = c.buttons {
                    ZStack {
                        buttons
                            .id(c.id)
                            .transition(.blurFade)
                    }
                    .padding(.horizontal, c.pillHorizontalPadding)
                    .padding(.vertical, c.pillVerticalPadding)
                    .fixedSize(horizontal: true, vertical: true)
                    .background(AquinasTheme.Colors.canvasSecondary.opacity(c.showsPillChrome ? 1 : 0))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(
                            AquinasTheme.Colors.controlBorder.opacity(c.showsPillChrome ? 1 : 0),
                            lineWidth: 1
                        )
                    )
                    .modifier(FloatingControlPressFeedback(isButtonPressed: c.isControlButtonPressed))
                    .animation(.springLively, value: c.controlsUpdateKey)
                    .opacity(c.pillReplacement == nil ? 1 : 0)
                    .allowsHitTesting(c.pillReplacement == nil)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                }

                if let replacement = c.pillReplacement {
                    replacement
                        .padding(.horizontal, 16)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ModelControlsHeightPreferenceKey.self,
                    value: geometry.size.height
                )
            }
        }
        .onPreferenceChange(ModelControlsHeightPreferenceKey.self) { height in
            guard measuredHeight == nil || abs((measuredHeight ?? 0) - height) > 0.5 else {
                return
            }
            withAnimation(measuredHeight == nil || reduceMotion ? nil : .smooth(duration: 0.3)) {
                measuredHeight = height
            }
        }
        .frame(height: measuredHeight, alignment: .bottom)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, c.bottomPadding)
        .frame(maxWidth: c.maxWidth ?? .infinity)
        .frame(maxWidth: .infinity, alignment: c.alignment)
        .animation(.easeInOut(duration: 0.22), value: c.id)
        .animation(.springStandard, value: c.bottomPadding)
        .animation(.springLively, value: c.buttons == nil)
        .animation(.easeInOut(duration: 0.24), value: c.pillReplacement == nil)
        .background(alignment: .bottom) {
            if c.showsStandardFade {
                LinearGradient(
                    stops: [
                        .init(color: AquinasTheme.Colors.canvas.opacity(0.95), location: 0),
                        .init(color: AquinasTheme.Colors.canvas.opacity(0), location: 1)
                    ],
                    startPoint: UnitPoint(x: 0.5, y: 0.52),
                    endPoint: UnitPoint(x: 0.5, y: 0)
                )
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
            }
        }
        .background(alignment: .bottom) {
            if let extraFade = c.extraFade {
                LinearGradient(
                    colors: [
                        AquinasTheme.Colors.canvas.opacity(0),
                        AquinasTheme.Colors.canvas.opacity(extraFade.opacity)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: extraFade.height)
                .allowsHitTesting(false)
            }
        }
    }
}

private struct ModelControlsHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
