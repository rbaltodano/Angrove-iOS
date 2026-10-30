//
//  SideMenuDragPresentation.swift
//  Angrove-iOS
//

import SwiftUI
import UIKit

private struct SideMenuDragPresentation: ViewModifier {
    @Binding var isPresented: Bool
    let activePage: AppPage
    let isStudyTopicDetailVisible: Bool
    let isSettingsDetailVisible: Bool
    let isBlocked: Bool
    let onBeginDrag: () -> Void
    let onDismiss: () -> Void
    let onOpenSearch: () -> Void
    let menu: AnyView

    @State private var attachmentScrollRegions = AttachmentScrollRegions()
    @State private var openingDrag = SideMenuOpeningDrag()
    @State private var isMenuAtTop = true
    @State private var hasFiredOpenHaptic = false

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
                .scrollDisabled(openingDrag.isActive)
                .onPreferenceChange(AttachmentScrollBoundsKey.self) { attachmentScrollRegions.update($0) }
                .simultaneousGesture(dragGesture)

            let progress = isPresented ? 1.0 : min(1.0, Double(openingDrag.offset / 345))
            AngroveTheme.Colors.scrim.opacity(0.16 * progress)
                .ignoresSafeArea()
                .allowsHitTesting(progress > 0.02)
                .onTapGesture(perform: onDismiss)
                .zIndex(3)

            menu
                .frame(width: 325)
                .offset(x: isPresented ? 0 : -345 + openingDrag.offset)
                .opacity(isPresented || openingDrag.isActive ? 1 : 0.96)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .allowsHitTesting(isPresented || openingDrag.isActive)
                .zIndex(1000)
        }
        .onPreferenceChange(SideMenuAtTopKey.self) { isMenuAtTop = $0 }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                // Direction and hit-region checks decide who grabs the gesture only once.
                // Once grabbed, a turn downward continues the same sidebar gesture.
                let requiresLeadingEdge = activePage == .insights || activePage == .conversation
                    || activePage == .library
                let canBegin = !attachmentScrollRegions.contains(value.startLocation)
                    && !ResponseSpeechPlayer.shared.isScrubbing
                    && !isPresented && !isBlocked
                    && !(activePage == .studyTopics && isStudyTopicDetailVisible)
                    && !(activePage == .settings && isSettingsDetailVisible)
                    && (!requiresLeadingEdge || value.startLocation.x < 30)
                let wasActive = openingDrag.isActive
                let opensSearch = openingDrag.update(
                    translation: value.translation,
                    canBegin: canBegin,
                    isMenuAtTop: isMenuAtTop
                )
                guard openingDrag.isActive else { return }
                if !wasActive { onBeginDrag() }
                if opensSearch {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.springRelaxed) { openingDrag.offset = 0 }
                    onOpenSearch()
                }
                guard !openingDrag.didOpenSearch else { return }
                if openingDrag.offset >= 175, !hasFiredOpenHaptic {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    hasFiredOpenHaptic = true
                } else if openingDrag.offset < 175 {
                    hasFiredOpenHaptic = false
                }
            }
            .onEnded { value in
                guard openingDrag.isActive else { return }
                if openingDrag.didOpenSearch {
                    openingDrag = SideMenuOpeningDrag()
                    hasFiredOpenHaptic = false
                    return
                }
                hasFiredOpenHaptic = false
                let shouldOpen = value.translation.width > 175
                    || value.predictedEndTranslation.width > 250
                if shouldOpen {
                    // Same entrance bookkeeping as the menu buttons, so a swipe-first
                    // opening never leaves the first-opening fade for a later tap.
                    SideMenuEntrance.prepareOpening()
                    // Every presenter animates explicitly, so the release can carry the
                    // finger's velocity into the spring instead of restarting from rest.
                    let remaining = max(1, 345 - openingDrag.offset)
                    let velocity = min(max(value.velocity.width / remaining, 0), 12)
                    withAnimation(.interpolatingSpring(
                        Spring(response: 0.42, dampingRatio: 0.86),
                        initialVelocity: velocity
                    )) {
                        openingDrag = SideMenuOpeningDrag()
                        isPresented = true
                    }
                } else {
                    withAnimation(.springStandard) {
                        openingDrag = SideMenuOpeningDrag()
                    }
                }
            }
    }
}

extension View {
    func sideMenuDragPresentation(
        isPresented: Binding<Bool>,
        activePage: AppPage,
        isStudyTopicDetailVisible: Bool,
        isSettingsDetailVisible: Bool,
        isBlocked: Bool,
        onBeginDrag: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onOpenSearch: @escaping () -> Void,
        menu: AnyView
    ) -> some View {
        modifier(SideMenuDragPresentation(
            isPresented: isPresented,
            activePage: activePage,
            isStudyTopicDetailVisible: isStudyTopicDetailVisible,
            isSettingsDetailVisible: isSettingsDetailVisible,
            isBlocked: isBlocked,
            onBeginDrag: onBeginDrag,
            onDismiss: onDismiss,
            onOpenSearch: onOpenSearch,
            menu: menu
        ))
    }
}
