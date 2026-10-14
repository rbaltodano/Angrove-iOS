import Foundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

@MainActor final class CanvasImpactFeedback {
    enum Style { case light, medium, heavy, rigid, soft }
    #if canImport(UIKit)
    private let generator: UIImpactFeedbackGenerator
    #endif
    init(style: Style) {
        #if canImport(UIKit)
        let nativeStyle: UIImpactFeedbackGenerator.FeedbackStyle
        switch style {
        case .light: nativeStyle = .light
        case .medium: nativeStyle = .medium
        case .heavy: nativeStyle = .heavy
        case .rigid: nativeStyle = .rigid
        case .soft: nativeStyle = .soft
        }
        generator = UIImpactFeedbackGenerator(style: nativeStyle)
        #endif
    }
    func prepare() {
        #if canImport(UIKit)
        generator.prepare()
        #endif
    }
    func impactOccurred(intensity: CGFloat = 1) {
        #if canImport(UIKit)
        generator.impactOccurred(intensity: intensity)
        #else
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #endif
    }
}

@MainActor final class CanvasSelectionFeedback {
    #if canImport(UIKit)
    private let generator = UISelectionFeedbackGenerator()
    #endif
    func selectionChanged() {
        #if canImport(UIKit)
        generator.selectionChanged()
        #else
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        #endif
    }
}
