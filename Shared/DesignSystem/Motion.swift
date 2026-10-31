import SwiftUI

/// Named springs. Choose by role, not by number.
extension Animation {
    /// Default for cards, popups, and layout changes.
    static let springStandard = Animation.spring(response: 0.42, dampingFraction: 0.86)
    /// Faster settle: exits, small controls, toggles.
    static let springQuick = Animation.spring(response: 0.32, dampingFraction: 0.86)
    /// Very short feedback, such as press states.
    static let springMicro = Animation.spring(response: 0.2, dampingFraction: 0.86)
    /// Slight overshoot for selection and emphasis.
    static let springLively = Animation.spring(response: 0.36, dampingFraction: 0.78)
    /// Slow, large movements such as camera and page transitions.
    static let springRelaxed = Animation.spring(Spring.relaxed)
    /// The Insight Tree focus curve, also used for quotation-marker movement.
    static let springCamera = Animation.spring(response: 0.58, dampingFraction: 0.64, blendDuration: 0.08)
    /// Visible bounce for playful confirmations.
    static let springBouncy = Animation.spring(response: 0.4, dampingFraction: 0.68)
    /// The outward beat of the 5% button pulse; `springBouncy` brings it back.
    static let springPulse = Animation.spring(response: 0.22, dampingFraction: 0.52)
    /// Follows a drag closely, such as a Midpoint handle.
    static let springTracking = Animation.interactiveSpring(response: 0.2, dampingFraction: 0.9)
}

/// The shared rubberband used by released Insights and their Midpoint transfer.
extension Spring {
    nonisolated static let relaxed = Spring(response: 0.5, dampingRatio: 0.8)
}

/// The User Guide's first-visible fade, blur, and slight upward text reveal.
struct SettingsTextRevealModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isBootPageRevealAnimating) private var isBootPageRevealAnimating
    @State private var hasRevealed = false
    @State private var isVisible = false

    private var canReveal: Bool {
        isVisible && isBootPageRevealAnimating
    }

    func body(content: Content) -> some View {
        content
            .opacity(hasRevealed || reduceMotion ? 1 : 0)
            .blur(radius: hasRevealed || reduceMotion ? 0 : 4)
            .offset(y: hasRevealed || reduceMotion ? 0 : 12)
            .onGeometryChange(for: Bool.self) { proxy in
                textIsVisible(proxy, threshold: 0.01)
            } action: { visible in
                isVisible = visible
            }
            .task(id: canReveal) {
                guard canReveal, !hasRevealed else { return }
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                guard !Task.isCancelled else { return }
                var transaction = Transaction(animation: reduceMotion ? nil :
                    .timingCurve(0.25, 0.1, 0.25, 1, duration: 0.6))
                transaction.disablesAnimations = false
                withTransaction(transaction) { hasRevealed = true }
            }
    }
}

/// Reusable word-by-word heading reveal used by Settings and the Home greeting.
struct SettingsAnimatedHeading: View {
    let text: Text
    let wordCount: Int
    let accessibilityLabel: String
    var visibilityThreshold: CGFloat = 0.4
    var revealsOnAppear = false
    var isPageVisible = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isBootPageRevealAnimating) private var isBootPageRevealAnimating
    @State private var hasRevealed = false
    @State private var isVisible = false
    @State private var hasAppeared = false
    @State private var elapsed: Double = 0

    init(
        text: Text,
        wordCount: Int,
        accessibilityLabel: String,
        visibilityThreshold: CGFloat = 0.4,
        revealsOnAppear: Bool = false,
        isPageVisible: Bool = true
    ) {
        self.text = text
        self.wordCount = wordCount
        self.accessibilityLabel = accessibilityLabel
        self.visibilityThreshold = visibilityThreshold
        self.revealsOnAppear = revealsOnAppear
        self.isPageVisible = isPageVisible
    }

    init(
        title: String,
        font: Font,
        color: Color,
        visibilityThreshold: CGFloat = 0.01,
        lineBreaksBetweenWords: Bool = false,
        revealsOnAppear: Bool = false,
        isPageVisible: Bool = true
    ) {
        let words = title.split(separator: " ")
        var attributedText = Text(verbatim: "")
        for (index, word) in words.enumerated() {
            attributedText = attributedText
                + Text(verbatim: index == 0 ? "" : (lineBreaksBetweenWords ? "\n" : " "))
                + Text(verbatim: String(word))
                    .font(font)
                    .foregroundColor(color)
                    .customAttribute(SettingsRevealWord(index: index))
        }

        self.init(
            text: attributedText,
            wordCount: words.count,
            accessibilityLabel: title,
            visibilityThreshold: visibilityThreshold,
            revealsOnAppear: revealsOnAppear,
            isPageVisible: isPageVisible
        )
    }

    private var duration: Double {
        0.6 + Double(max(wordCount - 1, 0)) * 0.055
    }

    private var canReveal: Bool {
        isPageVisible && isBootPageRevealAnimating && (revealsOnAppear ? hasAppeared : isVisible)
    }

    var body: some View {
        text
            .textRenderer(SettingsHeadingRenderer(elapsed: reduceMotion ? duration : elapsed))
            .accessibilityLabel(Text(verbatim: accessibilityLabel))
            .accessibilityAddTraits(.isHeader)
            .onAppear {
                hasAppeared = true
            }
            .onGeometryChange(for: Bool.self) { proxy in
                textIsVisible(proxy, threshold: visibilityThreshold)
            } action: { visible in
                isVisible = visible
            }
            .task(id: canReveal) {
                guard canReveal, !hasRevealed else { return }
                // Home is mounted in a transaction that disables animations while hidden.
                // Render the initial text state before starting its own reveal transaction.
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                guard canReveal, !Task.isCancelled else { return }
                var transaction = Transaction(animation: reduceMotion ? nil : .linear(duration: duration))
                transaction.disablesAnimations = false
                withTransaction(transaction) {
                    hasRevealed = true
                    elapsed = duration
                }
            }
    }
}

/// Layout is available during boot even before scroll visibility callbacks arrive.
/// Measure against the scroll viewport so offscreen text still waits for scrolling.
private func textIsVisible(_ proxy: GeometryProxy, threshold: CGFloat) -> Bool {
    guard let viewport = proxy.bounds(of: .scrollView(axis: .vertical)) else { return true }
    let bounds = CGRect(origin: .zero, size: proxy.size)
    guard bounds.width > 0, bounds.height > 0 else { return false }
    let intersection = bounds.intersection(viewport)
    guard !intersection.isNull else { return false }
    return intersection.width * intersection.height / (bounds.width * bounds.height) >= threshold
}

struct SettingsRevealWord: TextAttribute {
    let index: Int
}

struct SettingsHeadingRenderer: TextRenderer {
    var elapsed: Double
    var animatableData: Double {
        get { elapsed }
        set { elapsed = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                let index = run[SettingsRevealWord.self]?.index ?? 0
                let progress = min(max((elapsed - Double(index) * 0.055) / 0.6, 0), 1)
                let fade = UnitCurve.bezier(
                    startControlPoint: UnitPoint(x: 0.25, y: 0.1),
                    endControlPoint: UnitPoint(x: 0.25, y: 1)
                ).value(at: progress)
                let movement = UnitCurve.bezier(
                    startControlPoint: UnitPoint(x: 0.2, y: 0.8),
                    endControlPoint: UnitPoint(x: 0.2, y: 1)
                ).value(at: progress)
                var copy = context
                copy.opacity *= fade
                copy.addFilter(.blur(radius: 4 * (1 - fade)))
                copy.translateBy(x: 0, y: 12 * (1 - movement))
                copy.draw(run)
            }
        }
    }
}

extension View {
    func settingsTextReveal() -> some View {
        modifier(SettingsTextRevealModifier())
    }
}
