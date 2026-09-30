//
//  ModelControlsHost.swift
//  Aquinas-iOS
//

import SwiftUI

/// What the visible page wants the app's single Model Controls bar to show.
///
/// Pages never render their own bar. A page-specific controls view (`InquiryControlDock`,
/// `PageModelControls`, `LibraryModelControls`) stays mounted invisibly inside its page — so it
/// keeps owning its state — and publishes this description. `ModelControlsHost`, mounted once
/// by the app shell, renders it. Switching between populated pages swaps the buttons inside
/// one pill (blurring out and in, per DESIGN.md); an empty page tucks the dock away.
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
    /// A page's docked card (e.g. the Insight Tree's Insight card), stacked directly above
    /// the pill. Published separately by the page and merged in by the preference key.
    var dockedCard: ModelControlsDockedCard? = nil
    /// Marks a contribution that carries only `dockedCard`, not a surface's controls.
    var isDockedCardOnly = false

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
        guard var current = value else {
            value = next
            return
        }
        if next.isDockedCardOnly {
            current.dockedCard = next.dockedCard ?? current.dockedCard
            value = current
            return
        }
        var merged = next
        merged.dockedCard = next.dockedCard ?? current.dockedCard
        if !current.isDockedCardOnly, current.priority > next.priority {
            current.dockedCard = merged.dockedCard
            value = current
            return
        }
        value = merged
    }
}

/// A card a page docks above the shared Model Controls pill.
struct ModelControlsDockedCard {
    /// Identifies the card's content; a change animates the stack.
    var key: String
    var view: AnyView
}

extension View {
    /// Publishes this page's controls to the shell's single `ModelControlsHost`.
    func modelControls(_ configuration: ModelControlsConfiguration) -> some View {
        preference(key: ModelControlsPreferenceKey.self, value: configuration)
    }

    /// Docks `card` above the shell's Model Controls pill while `key` is non-empty. The card
    /// renders inside the shared controls stack, so it always sits one stack gap above the pill.
    func modelControlsDockedCard<Card: View>(
        key: String,
        @ViewBuilder card: () -> Card
    ) -> some View {
        let docked = key.isEmpty ? nil : ModelControlsDockedCard(key: key, view: AnyView(card()))
        return transformPreference(ModelControlsPreferenceKey.self) { value in
            guard let docked else { return }
            if value == nil {
                value = ModelControlsConfiguration(id: "none", isDockedCardOnly: true)
            }
            value?.dockedCard = docked
        }
    }
}

/// The one Model Controls host in the app. Mounted once by the shell; populated pages swap
/// their published buttons inside it, while pages with no controls let it disappear.
struct ModelControlsHost: View {
    let configuration: ModelControlsConfiguration?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelCompletionNotifications) private var completionNotifications
    @State private var measuredHeight: CGFloat?

    private static let empty = ModelControlsConfiguration(id: "none")

    var body: some View {
        let c = configuration ?? Self.empty
        let showsContent = hasVisibleContent(c)
        // A ZStack, not a Group: Group would hand the measuring modifiers below to the
        // transient child, so a re-shown dock never reported its height and pages reserved
        // only the bottom padding (docked cards slid under the pill). Bottom-aligned so the
        // departing dock stays pinned to the bottom edge while the host collapses around it.
        ZStack(alignment: .bottom) {
            if showsContent {
                controlsStack(c)
                    .transition(reduceMotion ? .opacity : .modelControlsDock)
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
        .frame(height: showsContent ? measuredHeight : 0, alignment: .bottom)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, showsContent ? c.bottomPadding : 0)
        .frame(maxWidth: c.maxWidth ?? .infinity)
        .frame(maxWidth: .infinity, alignment: c.alignment)
        .animation(.easeInOut(duration: 0.22), value: c.id)
        .animation(.springStandard, value: c.bottomPadding)
        .animation(
            reduceMotion
                ? .easeInOut(duration: 0.2)
                : (showsContent ? .springStandard : .modelControlsDockExit),
            value: showsContent
        )
        .animation(.easeInOut(duration: 0.24), value: c.pillReplacement == nil)
        .background(alignment: .bottom) {
            if showsContent && c.showsStandardFade {
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
                .transition(.opacity)
            }
        }
        .background(alignment: .bottom) {
            if showsContent, let extraFade = c.extraFade {
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
                .transition(.opacity)
            }
        }
    }

    private func hasVisibleContent(_ c: ModelControlsConfiguration) -> Bool {
        c.buttons != nil || c.pillReplacement != nil || c.showsScrollToBottom
            || c.contextCard?.isOpen == true || c.supplementalPopupIsOpen
            || c.modelTasksPopupState?.isOpen == true || c.confirmationTitle != nil
            || completionNotifications?.notifications.isEmpty == false
            || c.dockedCard != nil
    }

    private func controlsStack(_ c: ModelControlsConfiguration) -> some View {
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
            dockedCard: c.dockedCard,
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
    }
}

private struct ModelControlsDockBlur: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}

private extension AnyTransition {
    /// The Insight card's bottom-anchored movement, with blur across the entire dock.
    /// A spring front-loads its change, so reusing it for removal hides the dock before the
    /// movement reads; the exit eases in instead, mirroring the entrance's settle.
    static var modelControlsDock: AnyTransition {
        let dockTransform = AnyTransition.scale(scale: 0.35, anchor: .bottom)
            .combined(with: .offset(y: 24))
            .combined(with: .opacity)
            .combined(with: .modifier(
                active: ModelControlsDockBlur(radius: 8),
                identity: ModelControlsDockBlur(radius: 0)
            ))

        return .asymmetric(
            insertion: dockTransform.animation(.springStandard),
            removal: dockTransform.animation(.modelControlsDockExit)
        )
    }
}

private extension Animation {
    static let modelControlsDockExit = Animation.easeIn(duration: 0.26)
}

private struct ModelControlsHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
