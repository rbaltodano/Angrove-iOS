import SwiftUI


/// The isolated Branch workspace. Model content arrives as one validated batch; presentation
/// reveals it independently, so no child can burst while another is still generating.
struct StudyBranchScene: View {
    let sourceTitle: String
    let initialPosition: CGPoint
    let isPromoted: Bool
    let children: [InsightModel]
    let isReady: Bool
    var childOffsets: [UUID: CGPoint] = [:]
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
    /// Children whose title has replaced the flashing loading icon.
    @State private var revealedTitleIDs: Set<UUID> = []
    @State private var loadingFlash: Double = 1

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let origin = hasCentered ? center : initialPosition
            let offsets = Dictionary(uniqueKeysWithValues: children.enumerated().map { index, child in
                (child.id, childOffsets[child.id] ?? StudyBranchAnimation.offset(
                    index: index, count: children.count, bondLength: 190))
            })
            let extent = StudyBranchAnimation.extent(offsets: Array(offsets.values),
                nodeHeight: nodeHeight, childSize: CGSize(width: childWidth, height: childHeight))
            let fitScale = min(1, (proxy.size.height - 32) / max(extent.height, 1),
                               (proxy.size.width - 32) / max(extent.width, 1))
            ZStack {
                ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                    let offset = offsets[child.id] ?? .zero
                    let destination = CGPoint(x: center.x + offset.x, y: center.y + offset.y)
                    let released = releasedIDs.contains(child.id)
                    FadedCanvasLine(
                        start: CGPoint(x: center.x + recoil.width, y: center.y + recoil.height),
                        end: released ? destination : center,
                        canvasSize: proxy.size,
                        color: AngroveTheme.Colors.primaryReadable.opacity(0.28),
                        style: StrokeStyle(lineWidth: 1 / max(fitScale, 0.01))
                    )
                    .opacity(released ? 1 : 0)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .allowsHitTesting(false)
                    Button {
                        guard finished else { return }
                        _ = openedInsightIDs.insert(child.id)
                        onInsightTapped(child)
                    } label: {
                        childChip(child)
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
            .animation(.springStandard, value: fitScale)
            .task(id: isPromoted && !children.isEmpty) {
                // Release the loading children as soon as the Insight becomes a Node Concept,
                // before the model has produced any text.
                guard isPromoted, !children.isEmpty, !finished else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    loadingFlash = 0.35
                }
                do { try await Task.sleep(for: .milliseconds(320)) }
                catch { return }
                for (index, child) in children.enumerated() where !releasedIDs.contains(child.id) {
                    if index > 0 {
                        do { try await Task.sleep(for: .seconds(StudyBranchAnimation.releaseDelay() - (reduceMotion ? 0 : 0.08))) }
                        catch { return }
                    }
                    guard !Task.isCancelled else { return }
                    let offset = offsets[child.id] ?? .zero
                    let length = max(hypot(offset.x, offset.y), 1)
                    if SettingsHaptics.isEnabled {
                        CanvasImpactFeedback(style: .medium).impactOccurred(intensity: 0.8)
                    }
                    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : StudyBranchAnimation.burst) {
                        _ = releasedIDs.insert(child.id)
                    }
                    if !reduceMotion {
                        withAnimation(.springMicro) {
                            recoil = CGSize(width: -offset.x / length * 9, height: -offset.y / length * 9)
                        }
                        do { try await Task.sleep(for: .milliseconds(80)) }
                        catch { return }
                        withAnimation(.springStandard) { recoil = .zero }
                    }
                }
            }
            .task(id: isReady) {
                // Once the whole validated batch exists, titles replace the loading icons one
                // at a time.
                guard isReady, !finished, !children.isEmpty else { return }
                while releasedIDs.count < children.count {
                    do { try await Task.sleep(for: .milliseconds(60)) }
                    catch { return }
                }
                do { try await Task.sleep(for: .milliseconds(450)) }
                catch { return }
                for child in children {
                    guard !Task.isCancelled else { return }
                    if SettingsHaptics.isEnabled {
                        CanvasImpactFeedback(style: .light).impactOccurred(intensity: 0.7)
                    }
                    withAnimation(.easeOut(duration: 0.32)) {
                        _ = revealedTitleIDs.insert(child.id)
                    }
                    do { try await Task.sleep(for: .milliseconds(320)) }
                    catch { return }
                }
                do { try await Task.sleep(for: .milliseconds(400)) }
                catch { return }
                guard !Task.isCancelled else { return }
                loadingFlash = 1
                finished = true
                onFinished()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isPromoted && !isReady ? "Branching \(sourceTitle)" : "Study \(sourceTitle)")
    }
}

extension StudyBranchScene {
    /// A new Insight: the flashing Node Concept icon alone while the model works, then the same
    /// icon-and-title chip the tree uses, gliding in.
    @ViewBuilder
    fileprivate func childChip(_ child: InsightModel) -> some View {
        ZStack {
            if revealedTitleIDs.contains(child.id) {
                InsightTreeChip(title: child.title, isUndiscovered: !openedInsightIDs.contains(child.id))
                    .transition(.glideFadeUp)
            } else {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AngroveTheme.Colors.lightGreen)
                    .opacity(loadingFlash)
                    .modifier(InsightTreeChipChrome())
                    .transition(.fadeBlur)
            }
        }
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
            .font(BrandTypography.font("Figtree-Bold", size: 18, relativeTo: .headline))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

enum StudyBranchAnimation {
    // A slow start, fast middle, and long deceleration: a burst rather than a spring bounce.
    static let burst = Animation.timingCurve(0.55, 0, 0.15, 1, duration: 0.65)
    static func releaseDelay() -> Double { Double.random(in: 0.1...0.25) }
    static func offset(index: Int, count: Int, bondLength: CGFloat) -> CGPoint {
        let angle = Double(index) / Double(max(count, 1)) * 2 * .pi + .pi / 8
        return CGPoint(x: cos(angle) * bondLength, y: sin(angle) * bondLength)
    }

    /// Fit one connected cluster without altering the relative length of any of its bonds.
    static func extent(offsets: [CGPoint], nodeHeight: CGFloat, childSize: CGSize) -> CGSize {
        let halfWidth = max(138, offsets.map { abs($0.x) + childSize.width / 2 }.max() ?? 0)
        let halfHeight = max(nodeHeight / 2, offsets.map { abs($0.y) + childSize.height / 2 }.max() ?? 0)
        return CGSize(width: halfWidth * 2 + 16, height: halfHeight * 2 + 16)
    }
}
