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
    static let springRelaxed = Animation.spring(response: 0.5, dampingFraction: 0.8)
    /// The Insight Tree focus curve, also used for quotation-marker movement.
    static let springCamera = Animation.spring(response: 0.58, dampingFraction: 0.64, blendDuration: 0.08)
    /// Visible bounce for playful confirmations.
    static let springBouncy = Animation.spring(response: 0.4, dampingFraction: 0.68)
}
