//
//  ButtonChangeMotion.swift
//  Angrove-iOS
//

import SwiftUI

// The shared motion for a button whose label or contents change (DESIGN.md → Components →
// Buttons → "Changing label or contents"): the old text blurs out while the new text blurs in,
// the button's width springs to fit, and the button pulses up 5% and back.

/// Text that blurs its old value out and its new value in. Font, color, and line limit come
/// from the surrounding modifiers.
struct BlurSwapText<Value: Hashable>: View {
    let text: Text
    let value: Value

    init(_ string: String) where Value == String {
        text = Text(string)
        value = string
    }

    init(_ text: Text, value: Value) {
        self.text = text
        self.value = value
    }

    var body: some View {
        ZStack(alignment: .leading) {
            text
                .id(value)
                .transition(.blurFade)
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: value)
    }
}

private struct PulseOnChange<Value: Equatable>: ViewModifier {
    let value: Value
    let anchor: UnitPoint
    @State private var scale: CGFloat = 1
    @State private var task: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale, anchor: anchor)
            .onChange(of: value) { _, _ in pulse() }
            .onDisappear { task?.cancel() }
    }

    private func pulse() {
        task?.cancel()
        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
            scale = 1.05
        }
        task = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                scale = 1
            }
        }
    }
}

extension View {
    /// Pulses 5% and back whenever `value` changes. Anchor on the edge beside a fixed neighbor.
    func pulsesOnChange<Value: Equatable>(of value: Value, anchor: UnitPoint = .center) -> some View {
        modifier(PulseOnChange(value: value, anchor: anchor))
    }
}
