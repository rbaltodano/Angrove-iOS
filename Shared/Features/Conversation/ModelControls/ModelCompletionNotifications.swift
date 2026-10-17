//
//  ModelCompletionNotifications.swift
//  Angrove-iOS
//

import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

enum ModelCompletionNotificationKind {
    case question
    case insightDefinition
    case pageReturn
}

struct ModelCompletionNotification: Identifiable {
    let id = UUID()
    let title: String
    let kind: ModelCompletionNotificationKind
    let returnPage: AppPage?
    let openAction: @MainActor () -> Void
}

@MainActor
@Observable
final class ModelCompletionNotificationCenter {
    private(set) var notifications: [ModelCompletionNotification] = []
    private(set) var isStackExpanded = false

    func expandStack() {
        withAnimation(.springStandard) {
            isStackExpanded = notifications.count > 1
        }
    }

    /// Keep the expansion choice while an Insight occupies the dock, then restore it.
    func showsExpandedStack(presentingCard: Bool) -> Bool {
        isStackExpanded && !presentingCard
    }

    private func resetEmptyStack() {
        if notifications.isEmpty { isStackExpanded = false }
    }
    @ObservationIgnored private var pageReturnTask: Task<Void, Never>?

    func post(
        title: String,
        kind: ModelCompletionNotificationKind = .question,
        returnPage: AppPage? = nil,
        postsSystemNotification: Bool = true,
        systemNotificationTitle: String? = nil,
        systemNotificationBody: String? = nil,
        openAction: @escaping @MainActor () -> Void
    ) {
        withAnimation(.springStandard) {
            if kind == .pageReturn {
                notifications.removeAll { $0.kind == .pageReturn }
            }
            notifications.insert(
                ModelCompletionNotification(
                    title: title,
                    kind: kind,
                    returnPage: returnPage,
                    openAction: openAction
                ),
                at: 0
            )
        }
        #if os(iOS)
        if postsSystemNotification, kind != .pageReturn, UIApplication.shared.applicationState != .active {
            AngroveSystemNotifications.postCompletedResponse(
                title: systemNotificationTitle ?? "Response Ready",
                body: systemNotificationBody ?? title
            )
        }
        #else
        if postsSystemNotification, kind != .pageReturn, !NSApplication.shared.isActive {
            AngroveSystemNotifications.postCompletedResponse(title: systemNotificationTitle ?? "Response Ready", body: systemNotificationBody ?? title)
        }
        #endif
        playCompletionHaptics()
    }

    @discardableResult
    func schedulePageReturn(
        title: String,
        returnPage: AppPage,
        openAction: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        dismissPageReturn()
        let task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.post(title: title, kind: .pageReturn, returnPage: returnPage, openAction: openAction)
        }
        pageReturnTask = task
        return task
    }

    func dismissPageReturn() {
        pageReturnTask?.cancel()
        pageReturnTask = nil
        withAnimation(.springStandard) {
            notifications.removeAll { $0.kind == .pageReturn }
            resetEmptyStack()
        }
    }

    func dismiss(id: UUID) {
        withAnimation(.springStandard) {
            notifications.removeAll { $0.id == id }
            resetEmptyStack()
        }
    }

    func open(id: UUID) {
        guard let notification = notifications.first(where: { $0.id == id }) else {
            return
        }
        dismiss(id: id)
        notification.openAction()
    }

    private func playCompletionHaptics() {
        guard SettingsHaptics.isEnabled else { return }
        let generator = CanvasImpactFeedback(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.7)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            generator.prepare()
            generator.impactOccurred(intensity: 0.7)
        }
    }
}

extension Notification.Name {
    static let aquinasMiniScrollButtonVisibilityChanged = Notification.Name("aquinasMiniScrollButtonVisibilityChanged")
}

struct ModelCompletionNotificationPill: View {
    let title: String
    let kind: ModelCompletionNotificationKind
    let width: CGFloat
    let onOpen: () -> Void
    let onDismiss: () -> Void

    private var iconName: String {
        switch kind {
        case .question: "QuestionNotificationIcon"
        case .insightDefinition: "InsightNotificationIcon"
        case .pageReturn: "QuestionNotificationIcon"
        }
    }

    private var iconColor: Color {
        switch kind {
        case .question, .pageReturn: AngroveTheme.Colors.headingText
        case .insightDefinition: AngroveTheme.Colors.lightGreen
        }
    }

    private var titleColor: Color {
        switch kind {
        case .question, .pageReturn: AngroveTheme.Colors.paragraphText
        case .insightDefinition: AngroveTheme.Colors.lightGreen
        }
    }

    private var accessibilityDescription: String {
        switch kind {
        case .question:
            String(localized: "View completed question: \(title)")
        case .insightDefinition:
            String(localized: "View completed Insight Definition: \(title)")
        case .pageReturn:
            title
        }
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onOpen) {
                HStack(spacing: 4) {
                    Image(iconName)
                        .renderingMode(.template)
                        .resizable()
                        .foregroundStyle(iconColor)
                        .frame(width: 14, height: 14)

                    Text(title)
                        .font(AngroveTheme.Typography.uiLabel)
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        // Fixed text box, leading-aligned: long titles overflow to the right
                        // (and fade out) instead of centering and clipping the icon.
                        .frame(width: width - 18 - 40 - 14 - 4, alignment: .leading)
                        .clipped()
                }
                .padding(.leading, 18)
                .padding(.trailing, 40)
                .frame(width: width, height: 50, alignment: .leading)
                // Text fades out over the last 24pt before the fixed dismiss button.
                .mask {
                    HStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 24)
                        Color.clear.frame(width: 40)
                    }
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityDescription)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(AngroveTheme.Typography.uiLabel)
                    .foregroundStyle(AngroveTheme.Colors.headingText)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss notification")
            .padding(.trailing, 4)
        }
        .frame(width: width, height: 50)
        .background(AngroveTheme.Colors.canvasSecondary)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(AngroveTheme.Colors.popupBorder, lineWidth: 1)
        }
    }
}

/// Completion cards share one compact stack above the dock on both platforms.
struct ModelCompletionNotificationList: View {
    /// Retained for call-site compatibility; cards use a fixed compact width.
    let width: CGFloat
    static let cardWidth: CGFloat = 175
    var presentingCard = false
    @Environment(\.modelCompletionNotifications) private var completionNotifications
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let center = completionNotifications, !center.notifications.isEmpty {
            let expanded = center.showsExpandedStack(presentingCard: presentingCard)
            let stacked = !expanded && center.notifications.count > 1
            let depth = min(center.notifications.count - 1, 2)

            ScrollView(.vertical) {
                ZStack(alignment: .top) {
                    ForEach(center.notifications.enumerated(), id: \.element.id) { index, notification in
                        ModelCompletionNotificationRow(
                            notification: notification,
                            width: Self.cardWidth,
                            onOpen: { center.open(id: notification.id) },
                            onDismiss: { center.dismiss(id: notification.id) }
                        )
                        .scaleEffect(x: expanded ? 1 : 1 - CGFloat(min(index, 2)) * 0.10,
                                     y: 1, anchor: .top)
                        .offset(y: expanded ? CGFloat(index) * 66 : CGFloat(min(index, 2)) * 8)
                        .opacity(expanded || index < 3 ? 1 : 0)
                        .zIndex(Double(center.notifications.count - index))
                        .allowsHitTesting(!stacked && (expanded || index == 0))
                        .accessibilityHidden(stacked || (!expanded && index > 0))
                    }

                    if stacked {
                        Button {
                            if !presentingCard { center.expandStack() }
                        } label: {
                            Color.clear
                                .frame(width: Self.cardWidth, height: 50 + CGFloat(depth) * 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(center.notifications.count) notifications")
                        .accessibilityValue(center.notifications[0].title)
                        .accessibilityHint(presentingCard
                            ? "Dismiss the open card to expand notifications"
                            : "Expand notifications")
                        .zIndex(Double(center.notifications.count + 1))
                    }
                }
                .frame(width: Self.cardWidth, height: expanded
                    ? 50 + CGFloat(center.notifications.count - 1) * 66
                    : 50 + CGFloat(depth) * 8, alignment: .top)
            }
            .scrollDisabled(!expanded)
            .scrollIndicators(.hidden)
            .frame(width: Self.cardWidth, height: expanded
                ? min(248, 50 + CGFloat(center.notifications.count - 1) * 66)
                : 50 + CGFloat(depth) * 8)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .springStandard, value: expanded)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .springStandard,
                       value: center.notifications.map(\.id))
            .transition(.bottomDockCard)
        }
    }
}

private struct ModelCompletionNotificationRow: View {
    let notification: ModelCompletionNotification
    let width: CGFloat
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            if notification.kind == .pageReturn {
                ModelControlsConfirmationPill(
                    title: notification.title,
                    width: width,
                    onConfirm: onOpen,
                    onDecline: onDismiss,
                    iconName: (notification.returnPage ?? .conversation).sidebarIconName,
                    showsControlBorder: true
                )
            } else {
                ModelCompletionNotificationPill(
                    title: notification.title,
                    kind: notification.kind,
                    width: width,
                    onOpen: onOpen,
                    onDismiss: onDismiss
                )
            }
        }
    }
}
