//
//  ModelCompletionNotifications.swift
//  Angrove-iOS
//

import SwiftUI
import UIKit

private let defaultOpenModelTaskPage: (ModelTaskSnapshot) -> Void = { _ in }

extension EnvironmentValues {
    @Entry var openModelTaskPage: (ModelTaskSnapshot) -> Void = defaultOpenModelTaskPage
    @Entry var modelCompletionNotifications: ModelCompletionNotificationCenter? = nil
}

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
    @ObservationIgnored private var pageReturnTask: Task<Void, Never>?

    func post(
        title: String,
        kind: ModelCompletionNotificationKind = .question,
        returnPage: AppPage? = nil,
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
        if kind != .pageReturn, UIApplication.shared.applicationState != .active {
            AngroveSystemNotifications.postCompletedResponse(title: title)
        }
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
        }
    }

    func dismiss(id: UUID) {
        withAnimation(.springStandard) {
            notifications.removeAll { $0.id == id }
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
        let generator = UIImpactFeedbackGenerator(style: .light)
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
        Button(action: onOpen) {
            HStack(spacing: 8) {
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
                        .truncationMode(.tail)
                }
                .frame(maxWidth: 238, alignment: .leading)

                Spacer(minLength: 0)

                Text("View", comment: "Action that opens completed model content.")
                    .font(AngroveTheme.Typography.uiLabel)
                    .foregroundStyle(iconColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityDescription)
        .padding(.horizontal, 24)
        .frame(width: width, height: 50)
        .background(AngroveTheme.Colors.canvasSecondary)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(AngroveTheme.Colors.darkBrown.opacity(0.08), lineWidth: 1)
        }
    }
}
