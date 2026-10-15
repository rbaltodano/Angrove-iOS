//
//  ModelTasksCard.swift
//  Angrove-iOS
//

import SwiftUI

import UniformTypeIdentifiers

@Observable
final class ModelTasksPopupState {
    var isOpen = false

    func reset() {
        isOpen = false
    }
}

struct ModelTasksCard: View {
    let modelTasks: ModelTaskQueue
    var popupState: ModelTasksPopupState? = nil
    @Environment(\.openModelTaskPage) private var openModelTaskPage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draggingTaskID: UUID?
    @State private var dismissTask: Task<Void, Never>?

    private var showsIdle: Bool {
        #if os(iOS)
        modelTasks.allTasks.isEmpty && [.ready, .development].contains(ModelDeliveryState.shared.phase)
        #else
        modelTasks.allTasks.isEmpty
        #endif
    }

    private var taskCounter: some View {
        Text("\(modelTasks.completedTasks.count) of \(modelTasks.totalCount)")
            .font(BrandTypography.font("Figtree-Regular", size: 14))
            .monospacedDigit()
    }

    private var cardCornerRadius: CGFloat {
        #if os(macOS)
        24
        #else
        36
        #endif
    }

    private let rowExitDuration = 0.4
    private let rowExitStagger = 0.15

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Model Tasks")
                    .font(BrandTypography.font("Figtree-Bold", size: 18))
                    .foregroundColor(AngroveTheme.Colors.headingText)

                #if os(macOS)
                Spacer()
                // Tasks replace the model selector while they run, and the selector returns when they finish.
                ZStack(alignment: .trailing) {
                    if modelTasks.allTasks.isEmpty {
                        ModelPicker()
                            .transition(reduceMotion ? .opacity : .blurFade)
                    } else {
                        taskCounter
                            .transition(reduceMotion ? .opacity : .blurFade)
                    }
                }
                .animation(reduceMotion ? nil : .springStandard, value: modelTasks.allTasks.isEmpty)
                #else
                if !modelTasks.allTasks.isEmpty {
                    Spacer()
                    taskCounter
                }
                #endif
            }

            #if os(iOS)
            if ModelDeliveryState.shared.phase.showsStatus {
                ModelDownloadStatusView(delivery: .shared)
            }
            #endif

            VStack(alignment: .leading, spacing: 4) {
                ForEach(modelTasks.allTasks.enumerated(), id: \.element.id) { index, task in
                    ModelTaskRow(
                        task: task,
                        isDragging: draggingTaskID == task.id,
                        onOpen: {
                            openModelTaskPage(task)
                        },
                        onStop: modelTasks.stopCurrent,
                        onRemove: {
                            modelTasks.removeUpcoming(id: task.id)
                        },
                        draggingTaskID: $draggingTaskID,
                        onReorder: { draggedID in
                            guard draggedID != task.id else { return }
                            let didMove = modelTasks.moveUpcoming(
                                id: draggedID,
                                relativeTo: task.id,
                                placeAfterTarget: false
                            )
                            if didMove {
                                CanvasImpactFeedback(style: .light)
                                    .impactOccurred(intensity: 0.5)
                            }
                        }
                    )
                    .transition(
                        .asymmetric(
                            insertion: .opacity,
                            removal: .offset(x: reduceMotion ? 0 : 24)
                                .combined(with: .opacity)
                        )
                        .animation(
                            .smooth(duration: rowExitDuration)
                                .delay(reduceMotion ? 0 : Double(index) * rowExitStagger)
                        )
                    )
                }

                if showsIdle {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.dotted")
                            .font(.system(size: 12, weight: .regular))
                            .frame(width: 12, height: 12)

                        Text("Model is currently idle...")
                            .font(BrandTypography.font("Figtree-Regular", size: 14))
                            .lineLimit(1)
                            #if os(macOS)
                            .settingsTextReveal()
                            #endif
                    }
                    .frame(minHeight: 28)
                    .transition(.opacity)
                }
            }
        }
        .foregroundColor(AngroveTheme.Colors.paragraphText.opacity(0.75))
        .animation(.springLively, value: modelTasks.allTasks)
        .frame(maxWidth: .infinity, alignment: .leading)
        #if os(macOS)
        .padding(28)
        #else
        .padding(32)
        #endif
        .frame(width: 355)
        .background(AngroveTheme.Colors.canvasSecondary)
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(AngroveTheme.Colors.popupBorder, lineWidth: 1)
        )
        .onChange(of: modelTasks.allTasks.count) { oldCount, newCount in
            dismissTask?.cancel()
            guard oldCount > 0, newCount == 0, let popupState else { return }
            let exitDuration = rowExitDuration
                + (reduceMotion ? 0 : Double(oldCount - 1) * rowExitStagger)
            dismissTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(exitDuration))
                guard !Task.isCancelled, modelTasks.allTasks.isEmpty else { return }
                popupState.reset()
            }
        }
        #if os(iOS)
        .task { await ModelDeliveryState.shared.refreshAvailability() }
        #endif
        .onDisappear {
            dismissTask?.cancel()
        }
    }
}

#if os(macOS)
/// The model new tasks use, with a menu of the models this Mac can run. Choosing one switches
/// after the current task finishes (`MacApplicationRuntime.selectModel`).
private struct ModelPicker: View {
    private let runtime = MacApplicationRuntime.shared

    var body: some View {
        MacActionMenu(entries: {
            runtime.availableTiers.map { tier in
                MacMenuEntry(
                    LocalizedStringResource(stringLiteral: tier.modelName),
                    symbol: tier == runtime.modelTier ? "checkmark" : ""
                ) { runtime.selectModel(tier) }
            }
        }) {
            HStack(spacing: 6) {
                Text(runtime.modelTier.modelName)
                    .font(BrandTypography.font("Figtree-Bold", size: 12))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(AngroveTheme.Colors.paragraphText.opacity(0.75))
            .contentShape(Rectangle())
        }
        .pointerStyle(.link)
        .accessibilityLabel("Model: \(runtime.modelTier.modelName)")
    }
}
#endif

private struct ModelTaskRow: View {
    let task: ModelTaskSnapshot
    let isDragging: Bool
    let onOpen: () -> Void
    let onStop: () -> Void
    let onRemove: () -> Void
    @Binding var draggingTaskID: UUID?
    /// Called continuously as a dragged row is carried over this row, so upcoming tasks
    /// visibly reflow into their landing order before the drag is released — the same
    /// live-preview feel as rearranging objects in an auto-layout frame.
    let onReorder: (_ draggedID: UUID) -> Void

    @ViewBuilder
    var body: some View {
        if task.phase == .upcoming {
            rowContent
                .opacity(isDragging ? 0.35 : 1)
                .scaleEffect(isDragging ? 0.97 : 1, anchor: .leading)
                .onDrag {
                    draggingTaskID = task.id
                    return NSItemProvider(object: task.id.uuidString as NSString)
                }
                .onDrop(
                    of: [.text],
                    delegate: ModelTaskDropDelegate(
                        targetID: task.id,
                        draggingTaskID: $draggingTaskID,
                        onReorder: onReorder
                    )
                )
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                HStack(spacing: 4) {
                    taskStatusIcon

                    Text(task.title)
                        .font(BrandTypography.font("Figtree-Regular", size: 14))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())

            taskAction
        }
        .frame(minHeight: 28)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var taskStatusIcon: some View {
        ZStack {
            switch task.phase {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AngroveTheme.Colors.headingText)
                    .transition(.opacity)
            case .current:
                ContextUsageIcon(
                    progress: 0,
                    color: AngroveTheme.Colors.paragraphText.opacity(0.75),
                    isSpinning: true
                )
                .transition(.opacity)
            case .upcoming:
                Image(systemName: "circle.dotted")
                    .font(.system(size: 14, weight: .regular))
                    .transition(.opacity)
            }
        }
        .frame(width: 14, height: 14)
        .animation(.easeInOut(duration: 0.2), value: task.phase)
    }

    @ViewBuilder
    private var taskAction: some View {
        ZStack {
            switch task.phase {
            case .completed:
                EmptyView()
            case .current:
                Button(action: onStop) {
                    Image(systemName: "stop.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AngroveTheme.Colors.paragraphText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop current model task")
                .transition(.opacity)
            case .upcoming:
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AngroveTheme.Colors.paragraphText.opacity(0.5))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove queued model task")
                .transition(.opacity)
            }
        }
        .frame(width: 14, height: 14)
        .animation(.easeInOut(duration: 0.2), value: task.phase)
    }
}

/// Reorders upcoming model tasks live as a dragged row passes over another row, mirroring
/// how objects slide into place while dragging inside an auto-layout frame.
private struct ModelTaskDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggingTaskID: UUID?
    let onReorder: (_ draggedID: UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingTaskID, draggingTaskID != targetID else { return }
        onReorder(draggingTaskID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingTaskID = nil
        return true
    }

    func dropExited(info: DropInfo) {}
}

struct ModelTaskCounter: View {
    let currentTaskNumber: Int
    let totalTaskCount: Int

    var body: some View {
        HStack(spacing: 0) {
            Text(currentTaskNumber, format: .number)
                .contentTransition(.numericText(value: Double(currentTaskNumber)))
                .animation(
                    .springQuick,
                    value: currentTaskNumber
                )

            Text("/")

            Text(totalTaskCount, format: .number)
                .contentTransition(.numericText(value: Double(totalTaskCount)))
                .animation(
                    .springQuick,
                    value: totalTaskCount
                )
        }
        .monospacedDigit()
    }
}
