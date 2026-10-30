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
    @State private var presentedTasks: [ModelTaskSnapshot]
    @State private var leavingTaskIDs: Set<UUID> = []
    @State private var enteringTaskIDs: Set<UUID> = []
    @State private var hasPresentedTasks: Bool

    init(modelTasks: ModelTaskQueue, popupState: ModelTasksPopupState? = nil) {
        self.modelTasks = modelTasks
        self.popupState = popupState
        _presentedTasks = State(initialValue: modelTasks.allTasks)
        _hasPresentedTasks = State(initialValue: !modelTasks.allTasks.isEmpty)
    }

    private var showsIdle: Bool {
        #if os(iOS)
        presentedTasks.isEmpty && [.ready, .development].contains(ModelDeliveryState.shared.phase)
        #else
        presentedTasks.isEmpty
        #endif
    }

    private var taskCounter: some View {
        Text("\(presentedTasks.filter { $0.phase == .completed }.count) of \(presentedTasks.count)")
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

    private var hiddenTaskIDs: Set<UUID> { leavingTaskIDs.union(enteringTaskIDs) }

    private let rowExitDuration = 0.24
    private let resizeDuration = 0.36

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
                    if presentedTasks.isEmpty {
                        ModelPicker()
                            .transition(reduceMotion ? .opacity : .blurFade)
                    } else {
                        taskCounter
                            .transition(reduceMotion ? .opacity : .blurFade)
                    }
                }
                .animation(reduceMotion ? nil : .springStandard, value: presentedTasks.isEmpty)
                #else
                if !presentedTasks.isEmpty {
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
                ForEach(presentedTasks) { task in
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
                    // Keep the departing row's space until its fade finishes. Only then
                    // remove it from layout, so the bottom-pinned card resizes smoothly.
                    .opacity(hiddenTaskIDs.contains(task.id) ? 0 : 1)
                    .blur(radius: !reduceMotion && hiddenTaskIDs.contains(task.id) ? 8 : 0)
                    .allowsHitTesting(!hiddenTaskIDs.contains(task.id))
                    .accessibilityHidden(hiddenTaskIDs.contains(task.id))
                    .animation(.easeOut(duration: rowExitDuration), value: hiddenTaskIDs.contains(task.id))
                    .transition(.opacity)
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
        .animation(reduceMotion ? nil : .smooth(duration: resizeDuration), value: presentedTasks)
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
        .task(id: modelTasks.allTasks) {
            await synchronizePresentation()
        }
        #if os(iOS)
        .task { await ModelDeliveryState.shared.refreshAvailability() }
        #endif
    }

    @MainActor
    private func synchronizePresentation() async {
        let liveTasks = modelTasks.allTasks
        if !liveTasks.isEmpty { hasPresentedTasks = true }
        let liveIDs = Set(liveTasks.map(\.id))
        let previousIDs = Set(presentedTasks.map(\.id))
        let departing = presentedTasks.filter { !liveIDs.contains($0.id) }
        enteringTaskIDs = enteringTaskIDs.intersection(liveIDs)
            .union(liveIDs.subtracting(previousIDs))
        // Keep removed snapshots at their old positions, even if a new task arrives or
        // the waiting queue is reordered during the fade. The queue itself stays live.
        var next = liveTasks
        for (index, task) in presentedTasks.enumerated() where !liveIDs.contains(task.id) {
            next.insert(task, at: min(index, next.count))
        }
        // Carry the size animation through the card's padding, background and host,
        // including arrivals whose reserved space is laid out before they reveal.
        withAnimation(reduceMotion ? nil : .smooth(duration: resizeDuration)) {
            presentedTasks = next
            leavingTaskIDs = Set(departing.map(\.id))
        }
        if !departing.isEmpty {
            do { try await Task.sleep(for: .seconds(rowExitDuration)) }
            catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .smooth(duration: resizeDuration)) {
                presentedTasks = liveTasks
                // Keep exit IDs until the next update so removed views cannot fade
                // back in while SwiftUI retains them for their layout transition.
            }
        }
        // Reverse the exit for arrivals: first make room, then fade out the blur.
        // Retain pending arrivals across task updates so a completion or another
        // enqueue during the resize cannot strand an invisible row.
        if !enteringTaskIDs.isEmpty || (liveTasks.isEmpty && hasPresentedTasks) {
            do { try await Task.sleep(for: .seconds(reduceMotion ? 0 : resizeDuration)) }
            catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: rowExitDuration)) {
                enteringTaskIDs = []
            }
        }
        guard liveTasks.isEmpty, hasPresentedTasks, !Task.isCancelled else { return }
        popupState?.reset()
    }
}

#if os(macOS)
/// The model new tasks use, with a menu of the models this Mac can run. Choosing one switches
/// after the current task finishes (`MacApplicationRuntime.selectModel`).
private struct ModelPicker: View {
    private let runtime = MacApplicationRuntime.shared

    var body: some View {
        if MacModelTier.offered.count > 1 {
            menu
        } else {
            name
        }
    }

    private var name: some View {
        Text(runtime.modelTier.modelName)
            .font(BrandTypography.font("Figtree-Bold", size: 12))
            .foregroundColor(AngroveTheme.Colors.paragraphText.opacity(0.75))
    }

    private var menu: some View {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    .transition(reduceMotion ? .opacity : .blurFade)
            case .current:
                ContextUsageIcon(
                    progress: 0,
                    color: AngroveTheme.Colors.paragraphText.opacity(0.75),
                    isSpinning: true
                )
                .transition(reduceMotion ? .opacity : .blurFade)
            case .upcoming:
                Image(systemName: "circle.dotted")
                    .font(.system(size: 14, weight: .regular))
                    .transition(reduceMotion ? .opacity : .blurFade)
            }
        }
        .frame(width: 14, height: 14)
        .animation(.easeInOut(duration: 0.24), value: task.phase)
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
