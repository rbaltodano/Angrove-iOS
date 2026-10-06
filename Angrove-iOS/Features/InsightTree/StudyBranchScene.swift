import SwiftUI
import UIKit

/// The isolated Branch workspace. Model content arrives as one validated batch; presentation
/// reveals it independently, so no child can burst while another is still generating.
struct StudyBranchScene: View {
    let sourceTitle: String
    let initialPosition: CGPoint
    let isPromoted: Bool
    let children: [InsightModel]
    let isReady: Bool
    let onFinished: () -> Void
    let onInsightTapped: (InsightModel) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasCentered = false
    @State private var releasedIDs: Set<UUID> = []
    @State private var recoil: CGSize = .zero
    @State private var finished = false
    @State private var nodeHeight: CGFloat = 100
    @State private var childHeight: CGFloat = 72
    @State private var childWidth: CGFloat = 160
    @State private var openedInsightIDs: Set<UUID> = []

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let origin = hasCentered ? center : initialPosition
            let columns = StudyBranchAnimation.columns(count: children.count, width: proxy.size.width, childWidth: childWidth)
            let topCount = max(children.count / 2, 1)
            let rows = Int(ceil(Double(topCount) / Double(columns)) + ceil(Double(max(children.count - topCount, 0)) / Double(columns)))
            let contentHeight = nodeHeight + CGFloat(rows) * (childHeight + 16) + 48
            let planeWidth = max(proxy.size.width, (childWidth + 24) * CGFloat(columns) + 40)
            let planeSize = CGSize(width: planeWidth, height: proxy.size.height)
            let fitScale = min(1, proxy.size.height / max(contentHeight, 1), proxy.size.width / planeWidth)
            ZStack {
                ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                    let point = StudyBranchAnimation.destination(
                        index: index, count: children.count, size: planeSize,
                        nodeHeight: nodeHeight, childHeight: childHeight, columns: columns
                    )
                    let destination = CGPoint(x: point.x - planeWidth / 2 + center.x, y: point.y)
                    let released = releasedIDs.contains(child.id)
                    AnimatableLine(
                        start: CGPoint(x: center.x + recoil.width, y: center.y + recoil.height),
                        end: released ? destination : center
                    )
                    .stroke(AngroveTheme.Colors.divider.opacity(0.55), lineWidth: 1)
                    .opacity(released ? 1 : 0)
                    .allowsHitTesting(false)
                    Button {
                        guard finished else { return }
                        _ = openedInsightIDs.insert(child.id)
                        onInsightTapped(child)
                    } label: {
                        InsightTreeChip(title: child.title, isUndiscovered: !openedInsightIDs.contains(child.id))
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .allowsHitTesting(released && finished)
                    .accessibilityHidden(!released)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                        childWidth = max(childWidth, size.width)
                        childHeight = max(childHeight, size.height)
                    }
                    .opacity(released ? 1 : 0)
                    .scaleEffect(released || reduceMotion ? 1 : 0.2)
                    .position(released ? destination : center)
                    .zIndex(2)
                }
                Group {
                    if isPromoted {
                        VStack(spacing: 18) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(AngroveTheme.Colors.lightGreen)
                            BranchLoadingTitle(title: sourceTitle, isLoading: !isReady)
                        }
                        .transition(.opacity)
                    } else {
                        InsightTreeChip(title: sourceTitle)
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: min(proxy.size.width - 48, 260))
                .padding(8)
                .background(AngroveTheme.Colors.canvas, in: RoundedRectangle(cornerRadius: 16))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { nodeHeight = $0 }
                .position(origin)
                .offset(recoil)
                .zIndex(1)
            }
            .scaleEffect(fitScale)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .springStandard) {
                    hasCentered = true
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isPromoted)
            .task(id: isReady) {
                guard isReady, !finished, !children.isEmpty else { return }
                // Let the ready labels report their footprints before the first burst.
                do { try await Task.sleep(for: .milliseconds(40)) }
                catch { return }
                for (index, child) in children.enumerated() {
                    if index > 0 {
                        do { try await Task.sleep(for: .seconds(StudyBranchAnimation.releaseDelay() - (reduceMotion ? 0 : 0.08))) }
                        catch { return }
                    }
                    guard !Task.isCancelled else { return }
                    let point = StudyBranchAnimation.destination(
                        index: index, count: children.count, size: planeSize,
                        nodeHeight: nodeHeight, childHeight: childHeight, columns: columns
                    )
                    let destination = CGPoint(x: point.x - planeWidth / 2 + center.x, y: point.y)
                    let dx = destination.x - center.x, dy = destination.y - center.y
                    let length = max(hypot(dx, dy), 1)
                    let direction = CGVector(dx: dx / length, dy: dy / length)
                    if SettingsHaptics.isEnabled {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.8)
                    }
                    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : StudyBranchAnimation.burst) {
                        _ = releasedIDs.insert(child.id)
                    }
                    if !reduceMotion {
                        withAnimation(.springMicro) {
                            recoil = CGSize(width: -direction.dx * 9, height: -direction.dy * 9)
                        }
                        do { try await Task.sleep(for: .milliseconds(80)) }
                        catch { return }
                        withAnimation(.springStandard) { recoil = .zero }
                    }
                }
                do { try await Task.sleep(for: .milliseconds(650)) }
                catch { return }
                guard !Task.isCancelled else { return }
                withAnimation(.springStandard) { recoil = .zero }
                finished = true
                onFinished()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isPromoted && !isReady ? "Branching \(sourceTitle)" : "Study \(sourceTitle)")
    }
}

private struct BranchLoadingTitle: View {
    let title: String
    let isLoading: Bool
    var body: some View {
        Group {
            if isLoading {
                titleText.modifier(ThinkingShimmer(isActive: true, color: AngroveTheme.Colors.primaryReadable))
            } else {
                titleText.foregroundStyle(AngroveTheme.Colors.primaryReadable)
            }
        }
    }
    private var titleText: some View {
        Text(title)
            .font(.custom("Figtree-Bold", size: 18, relativeTo: .headline))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

enum StudyBranchAnimation {
    // A slow start, fast middle, and long deceleration: a burst rather than a spring bounce.
    static let burst = Animation.timingCurve(0.55, 0, 0.15, 1, duration: 0.65)
    static func releaseDelay() -> Double { Double.random(in: 0.1...0.25) }
    static func columns(count: Int, width: CGFloat, childWidth: CGFloat) -> Int {
        min(max((count + 1) / 2, 1), max(Int((width - 40) / (childWidth + 24)), 1))
    }

    /// Balanced groups above and below the node use natural chip sizes. Narrow phones add
    /// rows instead of shrinking several single-line titles into one crowded horizontal arc.
    static func destination(index: Int, count: Int, size: CGSize,
                            nodeHeight: CGFloat, childHeight: CGFloat, columns: Int = 3) -> CGPoint {
        let topCount = max(count / 2, 1)
        let isTop = index < topCount
        let groupCount = isTop ? topCount : count - topCount
        let groupIndex = isTop ? index : index - topCount
        let row = groupIndex / max(columns, 1)
        let rowCount = min(columns, groupCount - row * columns)
        let column = groupIndex % max(columns, 1)
        let x = size.width / 2 + (CGFloat(column) - CGFloat(rowCount - 1) / 2)
            * (size.width - 40) / CGFloat(max(columns, 1))
        let separation = (nodeHeight + childHeight) / 2 + 24 + CGFloat(row) * (childHeight + 16)
        return CGPoint(x: x, y: size.height / 2 + (isTop ? -separation : separation))
    }
}
