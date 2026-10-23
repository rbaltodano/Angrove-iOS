import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let angroveInsight = UTType(exportedAs: "com.angrove.insight")
}

/// One hover timer per target. Exiting, dropping or unmounting cancels navigation.
@MainActor @Observable
final class MacInsightSpringLoad {
    private(set) var isTargeted = false
    @ObservationIgnored private var task: Task<Void, Never>?

    func enter(open: (() -> Void)?) {
        guard !isTargeted else { return }
        isTargeted = true
        guard let open else { return }
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(500))
        task = Task {
            do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
            guard !Task.isCancelled, isTargeted else { return }
            open()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isTargeted = false
    }
}

private struct MacInsightDropDelegate: DropDelegate {
    let hover: MacInsightSpringLoad
    let open: (() -> Void)?
    let receive: ((WorktreeInsightDrop) -> Void)?

    func validateDrop(info: DropInfo) -> Bool {
        (open != nil || receive != nil) && info.hasItemsConforming(to: [.angroveInsight])
    }
    func dropEntered(info: DropInfo) { hover.enter(open: open) }
    func dropExited(info: DropInfo) { hover.cancel() }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .copy) }
    func performDrop(info: DropInfo) -> Bool {
        hover.cancel()
        guard let receive, let provider = info.itemProviders(for: [.angroveInsight]).first else { return false }
        Task { @MainActor in
            let data: Data? = await withCheckedContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: UTType.angroveInsight.identifier) { data, _ in
                    continuation.resume(returning: data)
                }
            }
            guard let data, let drop = try? JSONDecoder().decode(WorktreeInsightDrop.self, from: data) else { return }
            receive(drop)
        }
        return true
    }
}

private struct MacInsightDropDestination: ViewModifier {
    var open: (() -> Void)?
    var receive: ((WorktreeInsightDrop) -> Void)?
    @State private var hover = MacInsightSpringLoad()

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: AngroveTheme.Spacing.cardRadius)
                    .strokeBorder(AngroveTheme.Colors.lightGreen.opacity(hover.isTargeted ? 1 : 0), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .onDrop(of: [.angroveInsight], delegate: MacInsightDropDelegate(hover: hover, open: open, receive: receive))
            .onDisappear { hover.cancel() }
    }
}

extension View {
    func macInsightDropDestination(open: (() -> Void)? = nil,
                                   receive: ((WorktreeInsightDrop) -> Void)? = nil) -> some View {
        modifier(MacInsightDropDestination(open: open, receive: receive))
    }
}

extension EnvironmentValues {
    @Entry var macQuoteDroppedInsight: (WorktreeInsightDrop, UUID?) -> Void = { _, _ in }
    @Entry var macOpenBoardsForInsight: () -> Void = {}
}

/// The canvas accepts Insight cards plus its existing conversation and Trash payloads.
struct MacWorktreeDropDelegate: DropDelegate {
    let receive: ([String], CGPoint) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.angroveInsight, .text])
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .copy) }
    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.angroveInsight, .text])
        guard !providers.isEmpty else { return false }
        let location = info.location
        Task { @MainActor in
            var payloads: [String] = []
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.angroveInsight.identifier) {
                    let data: Data? = await withCheckedContinuation { continuation in
                        provider.loadDataRepresentation(forTypeIdentifier: UTType.angroveInsight.identifier) { data, _ in
                            continuation.resume(returning: data)
                        }
                    }
                    if let data, let drop = try? JSONDecoder().decode(WorktreeInsightDrop.self, from: data) {
                        payloads.append(drop.payload)
                    }
                } else {
                    let text: String? = await withCheckedContinuation { continuation in
                        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                            continuation.resume(returning: object as? String)
                        }
                    }
                    if let text { payloads.append(text) }
                }
            }
            _ = receive(payloads, location)
        }
        return true
    }
}
