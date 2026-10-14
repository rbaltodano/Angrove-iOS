import SwiftUI

struct ContextUsageIcon: View {
    let progress: CGFloat
    let color: Color
    var isSpinning: Bool = false

    private enum Phase { case idle, spinning, settling }

    @State private var phase: Phase = .idle
    @State private var startDate = Date()
    @State private var settleAngle: Double = 0   // angle (deg) used while not actively spinning
    @State private var arc: Double = 0           // 0 = progress ring, 1 = quarter spinner
    @State private var settleTask: Task<Void, Never>? = nil

    private let revDuration: Double = 1.1         // seconds per revolution
    private let settleDuration: Double = 1.0

    var body: some View {
        ZStack {
            // At rest this is a fill gauge: a full-width track and square ends keep a low reading
            // (a short arc) from looking like a frozen loading spinner.
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 3)
            TimelineView(.animation(paused: phase == .idle)) { timeline in
                let angle = phase == .spinning
                    ? timeline.date.timeIntervalSince(startDate) * 360.0 / revDuration
                    : settleAngle
                let trimEnd = 0.25 * arc + Double(min(max(progress, 0), 1)) * (1 - arc)
                Circle()
                    .trim(from: 0, to: trimEnd)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 3, lineCap: phase == .idle ? .butt : .round)
                    )
                    .rotationEffect(.degrees(-90 + angle))
                    .animation(.easeInOut(duration: 0.65), value: progress)
            }
        }
        .frame(width: 14, height: 14)
        .onAppear { if isSpinning { beginSpin() } }
        .onChange(of: isSpinning) { _, spinning in
            if spinning { beginSpin() } else { endSpin() }
        }
    }

    private func beginSpin() {
        settleTask?.cancel()
        startDate = Date()
        phase = .spinning
        withAnimation(.easeInOut(duration: 0.3)) { arc = 1 }
    }

    private func endSpin() {
        // Continue clockwise to the next upright position, then morph the arc back to the ring.
        let elapsed = Date().timeIntervalSince(startDate)
        let current = elapsed * 360.0 / revDuration
        let target = (current / 360.0).rounded(.up) * 360.0
        settleAngle = current
        phase = .settling
        withAnimation(.easeOut(duration: settleDuration)) {
            settleAngle = target
            arc = 0
        }
        settleTask = Task {
            try? await Task.sleep(for: .seconds(settleDuration))
            if !Task.isCancelled { phase = .idle }
        }
    }
}
