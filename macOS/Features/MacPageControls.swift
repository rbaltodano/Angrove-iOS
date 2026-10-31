import SwiftUI

/// One action a page puts in the workspace's Model Controls bar.
struct MacPageControlAction: Identifiable {
    let title: String
    let symbol: String
    let action: () -> Void
    var id: String { title }
}

/// Publishes a page's actions to the workspace's Model Controls bar. Model status shows only
/// while the shared queue is busy, as on iPhone; a page with no actions publishes just that.
struct MacPageControls: View {
    let actions: [MacPageControlAction]
    let modelTasks: ModelTaskQueue
    let queuePopup: ModelTasksPopupState

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .preference(key: MacGlobalModelControlsKey.self,
                        value: MacGlobalModelControls(configuration: Self.configuration(actions: actions, modelTasks: modelTasks, queuePopup: queuePopup)))
    }

    /// Also used by the workspace when no page publishes, so a page without actions shows nothing while idle.
    static func configuration(actions: [MacPageControlAction], modelTasks: ModelTaskQueue,
                              queuePopup: ModelTasksPopupState) -> ModelControlsConfiguration {
        var configuration = ModelControlsConfiguration(id: "mac-global")
        configuration.modelTasks = modelTasks
        configuration.modelTasksPopupState = queuePopup
        configuration.controlsUpdateKey = "\(modelTasks.isBusy)|" + actions.map(\.title).joined(separator: "|")
        if modelTasks.isBusy || !actions.isEmpty {
            configuration.buttons = AnyView(MacPageControlButtons(actions: actions, modelTasks: modelTasks, queuePopup: queuePopup))
        }
        return configuration
    }
}

private struct MacPageControlButtons: View {
    let actions: [MacPageControlAction]
    let modelTasks: ModelTaskQueue
    let queuePopup: ModelTasksPopupState

    var body: some View {
        HStack(spacing: 24) {
            if modelTasks.isBusy {
                MacGlobalModelStatus(modelTasks: modelTasks, queuePopup: queuePopup)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
            ForEach(actions) { action in
                MacPageControlActionButton(action: action)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
    }
}

private struct MacPageControlActionButton: View {
    let action: MacPageControlAction
    @State private var isPressed = false

    var body: some View {
        Button(action: action.action) {
            HStack(spacing: 6) {
                Image(systemName: action.symbol)
                    .angroveIcon(.small)
                    .frame(width: 16, height: 16)
                Text(action.title)
                    .font(BrandTypography.font("Figtree-Bold", size: 14))
            }
            .foregroundStyle(AngroveTheme.Colors.lightGreen)
            .frame(minHeight: 21)
            .contentShape(Rectangle())
        }
        .buttonStyle(FloatingControlButtonStyle(isPressed: $isPressed))
        .accessibilityLabel(action.title)
        .modelControlHoverLabel(action.title)
    }
}

struct MacGlobalModelStatus: View {
    let modelTasks: ModelTaskQueue
    let queuePopup: ModelTasksPopupState
    @State private var isPressed = false

    var body: some View {
        ModelStatusButton(modelTasks: modelTasks, action: {
            withAnimation(.springStandard) { queuePopup.isOpen.toggle() }
        }, controlIsPressed: $isPressed)
        .buttonStyle(FloatingControlButtonStyle(isPressed: $isPressed))
    }
}
