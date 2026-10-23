import AppKit
import QuartzCore
import SwiftUI

/// Measures delivered display callbacks, including frames missed while the main thread is busy.
/// Only this small overlay updates; sampling never publishes per-frame state to the board.
struct WorktreeFrameRateCounter: View {
    @State private var framesPerSecond: Int?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        WorktreeFrameRateLabel(framesPerSecond: framesPerSecond)
            .background {
                WorktreeFrameRateInput(isActive: scenePhase == .active) { framesPerSecond = $0 }
            }
            .onChange(of: scenePhase) { _, _ in framesPerSecond = nil }
            .allowsHitTesting(false)
    }
}

struct WorktreeFrameRateLabel: View {
    let framesPerSecond: Int?

    var body: some View {
        MacModelControlHoverLabel(help: MacModelControlHelp(
            title: framesPerSecond.map { "\($0) FPS" } ?? "— FPS", shortcut: nil))
            .accessibilityLabel("Frame rate")
            .accessibilityValue(framesPerSecond.map { "\($0) frames per second" } ?? "Measuring")
    }
}

/// Average callback rate over half a second, using elapsed wall time rather than the display's
/// advertised refresh rate. A long frame therefore lowers the readout instead of being skipped.
struct WorktreeFrameRateSample {
    private var start: CFTimeInterval?
    private var last: CFTimeInterval?
    private var intervals = 0

    mutating func record(at time: CFTimeInterval) -> Int? {
        guard time.isFinite else { return nil }
        guard let start, let last else {
            self.start = time
            self.last = time
            return nil
        }
        guard time > last else { return nil }
        self.last = time
        intervals += 1
        let elapsed = time - start
        guard elapsed >= 0.5 else { return nil }
        let rate = Int((Double(intervals) / elapsed).rounded())
        self.start = time
        intervals = 0
        return rate
    }
}

struct WorktreeFrameRateInput: NSViewRepresentable {
    let isActive: Bool
    let onSample: (Int) -> Void

    func makeNSView(context: Context) -> FrameRateSurface { FrameRateSurface() }

    func updateNSView(_ view: FrameRateSurface, context: Context) {
        view.onSample = onSample
        view.setActive(isActive)
    }

    static func dismantleNSView(_ view: FrameRateSurface, coordinator: ()) { view.stop() }

    final class FrameRateSurface: NSView {
        var onSample: ((Int) -> Void)?
        private var link: CADisplayLink?
        private var sample = WorktreeFrameRateSample()
        private var isActive = false

        private final class Target: NSObject {
            weak var surface: FrameRateSurface?
            init(_ surface: FrameRateSurface) { self.surface = surface }
            @objc func tick(_ link: CADisplayLink) { surface?.tick() }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            startIfNeeded()
        }

        func setActive(_ active: Bool) {
            isActive = active
            if active { startIfNeeded() } else { stop() }
        }

        private func startIfNeeded() {
            guard isActive, window != nil, link == nil else { return }
            // The view's display link follows its window between screens and stops delivering
            // callbacks when hidden. Its target holds the view weakly to avoid a retain cycle.
            let link = displayLink(target: Target(self), selector: #selector(Target.tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        func stop() {
            link?.invalidate()
            link = nil
            sample = WorktreeFrameRateSample()
        }

        private func tick() {
            if let rate = sample.record(at: CACurrentMediaTime()) { onSample?(rate) }
        }
    }
}
