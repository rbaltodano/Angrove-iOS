import SwiftUI
import UIKit

struct RenderedGraphEdge: Identifiable {
    let id: String
    let fromNodeID: UUID
    let toNodeID: UUID
    let isSuggested: Bool
}

/// A simulated node: live position + velocity, integrated each frame.
struct SimBody {
    var pos: CGPoint
    var vel: CGVector
}

/// Per-insight bond angle around its node (free absolute angle in radians; VSEPR repulsion
/// spreads chips to maximize separation).
struct ChipAngle {
    var angle: Double
}

/// `pending` is a touch that could still be a tap; it becomes `pan` once it moves.
enum StudyDragMode { case rotate, pending, pan }

@MainActor
final class InsightCollisionSizeCache {
    var sizes: [String: CGSize] = [:]
}

func insightTreeCanvasClamp<T: Comparable>(_ value: T, lower: T, upper: T) -> T {
    min(max(value, lower), upper)
}
