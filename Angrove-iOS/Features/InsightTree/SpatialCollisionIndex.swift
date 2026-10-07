import CoreGraphics
import Foundation

/// Broad phase only: exact overlap/force rules still decide whether a candidate collides.
nonisolated enum SpatialCollisionIndex {
    struct Pair: Hashable, Sendable { let first: Int; let second: Int }
    private struct Cell: Hashable { let x: Int; let y: Int }

    static func pairs(for rectangles: [CGRect], cellSize: CGFloat = 256) -> [Pair] {
        guard cellSize.isFinite, cellSize > 0 else { return [] }
        var cells: [Cell: [Int]] = [:]
        var pairs: Set<Pair> = []
        for (index, rectangle) in rectangles.enumerated() {
            guard !rectangle.isNull, !rectangle.isInfinite,
                  rectangle.minX.isFinite, rectangle.minY.isFinite,
                  rectangle.maxX.isFinite, rectangle.maxY.isFinite else { continue }
            let minX = floor(rectangle.minX / cellSize), maxX = floor(rectangle.maxX / cellSize)
            let minY = floor(rectangle.minY / cellSize), maxY = floor(rectangle.maxY / cellSize)
            // Bound pathological coordinates/giant footprints without losing collision coverage.
            if abs(minX) > 1e9 || abs(maxX) > 1e9 || abs(minY) > 1e9 || abs(maxY) > 1e9
                || (maxX - minX + 1) * (maxY - minY + 1) > 4096 {
                return rectangles.indices.flatMap { i in rectangles.indices.filter { $0 > i }.map { Pair(first: i, second: $0) } }
            }
            for x in Int(minX)...Int(maxX) {
                for y in Int(minY)...Int(maxY) {
                    let cell = Cell(x: x, y: y)
                    for prior in cells[cell] ?? [] { pairs.insert(Pair(first: prior, second: index)) }
                    cells[cell, default: []].append(index)
                }
            }
        }
        return pairs.sorted { $0.first == $1.first ? $0.second < $1.second : $0.first < $1.first }
    }
}
