import SwiftUI

enum MacSidebarTransition {
    static let timingScale = 0.5
    static let widthDuration = 0.42 * timingScale
    static let midpoint = widthDuration / 2
    static let fadeDuration = 0.14 * timingScale

    // Matches the corresponding mobile SideMenuRow delays.
    static func delay(for destination: MacDestination) -> Double {
        switch destination {
        case .home: 0.20
        case .insights: 0.25
        case .conversations: 0.30
        case .library: 0.325
        case .studyTopics: 0.35
        case .worktree: 0.375
        case .settings: 0.40
        }
    }
}

struct MacSidebarEntrance: ViewModifier {
    let isPresented: Bool
    let delay: Double
    var duration = 0.30
    var offset: CGFloat = 10
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(x: visible || reduceMotion ? 0 : -offset)
            .task(id: isPresented) {
                guard isPresented, !reduceMotion else {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: MacSidebarTransition.fadeDuration)) {
                        visible = isPresented
                    }
                    return
                }
                do { try await Task.sleep(for: .seconds(delay * MacSidebarTransition.timingScale)) } catch { return }
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: duration * MacSidebarTransition.timingScale)) { visible = true }
            }
    }
}

struct MacSidebarIconEntrance: ViewModifier {
    let isPresented: Bool
    let delay: Double
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        Group {
            if visible {
                if reduceMotion { content }
                else { content.sfSymbolDrawOn() }
            } else {
                content.hidden()
            }
        }
        .task(id: isPresented) {
            guard isPresented, !reduceMotion else {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { visible = isPresented }
                return
            }
            do { try await Task.sleep(for: .seconds(delay * MacSidebarTransition.timingScale)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.35 * MacSidebarTransition.timingScale)) { visible = true }
        }
    }
}

struct MacSidebarEntranceDivider: View {
    let isPresented: Bool
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 16) {
            Rectangle().fill(AngroveTheme.Colors.controlBorder).frame(height: 1)
                .scaleEffect(x: visible || reduceMotion ? 1 : 0.75, y: 1, anchor: .trailing)
            AppIconImage(size: 16)
                .rotationEffect(.degrees(visible || reduceMotion ? 0 : -45))
            Rectangle().fill(AngroveTheme.Colors.controlBorder).frame(height: 1)
                .scaleEffect(x: visible || reduceMotion ? 1 : 0.75, y: 1, anchor: .leading)
        }
        .opacity(visible ? 1 : 0)
        .task(id: isPresented) {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35 * MacSidebarTransition.timingScale)) { visible = isPresented }
        }
    }
}
