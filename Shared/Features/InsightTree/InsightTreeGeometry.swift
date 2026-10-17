import Foundation
import CoreGraphics
import CryptoKit
import NaturalLanguage

/// Apple's sentence embedding, loaded once rather than for every vector.
private nonisolated enum SentenceEmbedding {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var embedding: NLEmbedding?

    static func vector(for text: String) -> [Double]? {
        lock.withLock {
            if embedding == nil { embedding = NLEmbedding.sentenceEmbedding(for: .english) }
            return embedding?.vector(for: text)
        }
    }
}

nonisolated func computeEmbedding(for text: String) -> [Double]? {
    if let vector = SentenceEmbedding.vector(for: text) {
        return vector
    }

    var buckets = Array(repeating: 0.0, count: 64)
    for scalar in text.lowercased().unicodeScalars {
        let index = Int(scalar.value) % buckets.count
        buckets[index] += 1
    }
    return buckets
}

nonisolated func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
    guard a.count == b.count else { return 0 }
    // This runs for every pair during clustering and semantic layout. Avoid the three
    // intermediate arrays previously created by `zip(...).map` and the two `map` calls.
    var dot = 0.0
    var squaredMagnitudeA = 0.0
    var squaredMagnitudeB = 0.0
    for index in a.indices {
        let valueA = a[index]
        let valueB = b[index]
        dot += valueA * valueB
        squaredMagnitudeA += valueA * valueA
        squaredMagnitudeB += valueB * valueB
    }
    let magA = sqrt(squaredMagnitudeA)
    let magB = sqrt(squaredMagnitudeB)
    guard magA > 0, magB > 0 else { return 0 }
    return dot / (magA * magB)
}

nonisolated func semanticDistance(_ a: [Double], _ b: [Double]) -> Double {
    1.0 - cosineSimilarity(a, b)
}

nonisolated let nodeNodeMinLength: CGFloat = 360
nonisolated private let nodeNodeDistanceScale: CGFloat = 320
/// Uniform room between Node Concepts. Scaling the whole mapping (floor included) keeps every
/// connector's length relative to the others. Saved layouts are scaled once to match
/// (`InsightTreeViewModel.migrateSpacing`).
nonisolated let nodeNodeSpacingScale: CGFloat = 1.4

nonisolated func mapDistanceToLength(_ distance: Double) -> CGFloat {
    (nodeNodeMinLength + CGFloat(max(distance, 0)) * nodeNodeDistanceScale) * nodeNodeSpacingScale
}

/// Bond length (insight connector radius) from how related an insight is to its parent node.
/// More related (smaller distance) → shorter bond; floored so close chips don't crowd the node.
nonisolated func insightBondLength(_ distance: Double) -> CGFloat {
    150 + CGFloat(min(max(distance, 0), 1)) * 180   // ~[150, 330]px
}

nonisolated func centroid(_ vectors: [[Double]]) -> [Double] {
    guard let first = vectors.first, !first.isEmpty else { return [] }
    var result = Array(repeating: 0.0, count: first.count)
    for vector in vectors where vector.count == first.count {
        for index in vector.indices {
            result[index] += vector[index]
        }
    }
    return result.map { $0 / Double(max(vectors.count, 1)) }
}

struct CodablePoint: Codable {
    let x: CGFloat
    let y: CGFloat

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}
