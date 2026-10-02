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
    let menu: AnyView

    @State private var attachmentScrollBounds: [CGRect] = []
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var hasFiredOpenHaptic = false

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
                .onPreferenceChange(AttachmentScrollBoundsKey.self) { attachmentScrollBounds = $0 }
                .simultaneousGesture(dragGesture)

            let progress = isPresented ? 1.0 : min(1.0, Double(dragOffset / 345))
            AngroveTheme.Colors.scrim.opacity(0.16 * progress)
                .ignoresSafeArea()
                .allowsHitTesting(progress > 0.02)
                .onTapGesture(perform: onDismiss)
                .animation(.easeInOut(duration: 0.22), value: isPresented)
                .zIndex(3)

            menu
                .frame(width: 325)
                .offset(x: isPresented ? 0 : -345 + dragOffset)
                .opacity(isPresented || isDragging ? 1 : 0.96)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .allowsHitTesting(isPresented || isDragging)
                .zIndex(1000)
                .animation(.springStandard, value: isPresented)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                guard !AttachmentScrollBoundsKey.contains(value.startLocation, in: attachmentScrollBounds),
                      !isPresented, !isBlocked,
                      !(activePage == .studyTopics && isStudyTopicDetailVisible),
                      !(activePage == .settings && isSettingsDetailVisible),
                      abs(value.translation.width) > abs(value.translation.height) else { return }
                guard value.translation.width > 0 else { return }
                // Pages with horizontally scrolling content only open the menu from the edge.
                let requiresLeadingEdge = activePage == .insights || activePage == .conversation
                    || activePage == .library
                guard !requiresLeadingEdge || value.startLocation.x < 30 else { return }

                if !isDragging {
                    isDragging = true
                    onBeginDrag()
                }
                dragOffset = min(345, value.translation.width)
                if dragOffset >= 175, !hasFiredOpenHaptic {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    hasFiredOpenHaptic = true
                } else if dragOffset < 175 {
                    hasFiredOpenHaptic = false
                }
            }
            .onEnded { value in
                guard isDragging else { return }
                hasFiredOpenHaptic = false
                let shouldOpen = value.translation.width > 175
                    || value.predictedEndTranslation.width > 250
                if shouldOpen {
                    isDragging = false
                    dragOffset = 0
                    isPresented = true
                } else {
                    withAnimation(.springStandard) {
                        isDragging = false
                        dragOffset = 0
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
            menu: menu
        ))
    }
}
