import CoreGraphics
import Foundation

/// Removes Node-to-Node connector crossings by rigidly rotating the smaller side of a crossing
/// bond around the node it hangs from. Rotation keeps every bond length (semantic distance)
/// intact, so only direction changes. A move is accepted only when it lowers the crossing count
/// without adding a footprint overlap; pinned nodes (placed Midpoints) never move.
nonisolated enum InsightTreeEdgeUntangling {
    static let maximumPasses = 32
    /// Smallest rotation first, so the layout keeps as much of its current shape as possible.
    static let rotations: [CGFloat] = stride(from: 15, through: 180, by: 15).flatMap { degrees -> [CGFloat] in
        let radians = CGFloat(degrees) * .pi / 180
        return degrees == 180 ? [radians] : [radians, -radians]
    }

    /// Footprints include each Node's full Insight orbit. Orbits may interleave (the live canvas
    /// rotates chips apart), so a turn only has to keep Node cores apart: half the footprint.
    static let coreClearance: CGFloat = 0.5

    /// A bond longer than this multiple of its semantic length is pulled back toward it.
    static let stretchLimit: CGFloat = 1.4

    struct Bond: Hashable {
        let a: UUID
        let b: UUID

        /// Order-independent identity for the undirected connector between two nodes.
        static func between(_ x: UUID, _ y: UUID) -> Bond {
            x.uuidString < y.uuidString ? Bond(a: x, b: y) : Bond(a: y, b: x)
        }
    }

    static func untangle(
        positions: [UUID: CGPoint],
        edges: [(UUID, UUID)],
        pinned: Set<UUID>,
        radii: [UUID: CGFloat],
        lengths: [Bond: CGFloat] = [:]
    ) -> [UUID: CGPoint] {
        var bonds: [Bond] = []
        var seen: Set<Bond> = []
        for (from, to) in edges where from != to && positions[from] != nil && positions[to] != nil {
            let bond = Bond.between(from, to)
            if seen.insert(bond).inserted { bonds.append(bond) }
        }
        guard bonds.count > 1 else { return positions }
        bonds.sort { ($0.a.uuidString, $0.b.uuidString) < ($1.a.uuidString, $1.b.uuidString) }

        var adjacency: [UUID: [UUID]] = [:]
        for bond in bonds {
            adjacency[bond.a, default: []].append(bond.b)
            adjacency[bond.b, default: []].append(bond.a)
        }
        let ids = positions.keys.sorted { $0.uuidString < $1.uuidString }
        var working = positions
        tighten(&working, bonds: bonds, adjacency: adjacency, ids: ids, pinned: pinned, radii: radii, lengths: lengths)

        for _ in 0..<maximumPasses {
            let crossings = crossingPairs(bonds, working)
            guard !crossings.isEmpty else { break }
            var improved = false
            for (first, second) in crossings {
                if let move = bestMove(for: [first, second], bonds: bonds, adjacency: adjacency,
                                       ids: ids, positions: working, pinned: pinned, radii: radii) {
                    for (id, point) in move { working[id] = point }
                    improved = true
                    break
                }
            }
            if !improved { break }
        }
        tighten(&working, bonds: bonds, adjacency: adjacency, ids: ids, pinned: pinned, radii: radii, lengths: lengths)
        return working
    }

    /// Restored positions can leave a branch far from the concept it is now bonded to (the
    /// spanning tree changes as Insights arrive). Slide the smaller hanging side straight back
    /// along the bond toward its semantic length, keeping its own shape, when that adds no
    /// crossing and no core overlap.
    private static func tighten(
        _ working: inout [UUID: CGPoint],
        bonds: [Bond],
        adjacency: [UUID: [UUID]],
        ids: [UUID],
        pinned: Set<UUID>,
        radii: [UUID: CGFloat],
        lengths: [Bond: CGFloat]
    ) {
        let stretched = bonds.compactMap { bond -> (Bond, CGFloat, CGFloat)? in
            guard let goal = lengths[bond], goal > 0, let a = working[bond.a], let b = working[bond.b] else { return nil }
            let length = hypot(a.x - b.x, a.y - b.y)
            return length > goal * stretchLimit ? (bond, length, goal) : nil
        }.sorted { $0.1 / $0.2 > $1.1 / $1.2 }

        for (bond, _, goal) in stretched {
            var sides: [(side: Set<UUID>, pivot: UUID, tip: UUID)] = []
            for (pivot, tip) in [(bond.a, bond.b), (bond.b, bond.a)] {
                if let side = pendantSide(from: tip, across: pivot, adjacency: adjacency), side.isDisjoint(with: pinned) {
                    sides.append((side, pivot, tip))
                }
            }
            sides.sort { $0.side.count < $1.side.count }
            moving: for (side, pivot, tip) in sides {
                guard let anchor = working[pivot], let end = working[tip] else { continue }
                let length = hypot(end.x - anchor.x, end.y - anchor.y)
                let touched = bonds.filter { side.contains($0.a) || side.contains($0.b) }
                let crossingsBefore = touchedCrossings(touched, bonds, working)
                let overlapsBefore = overlapCount(side, ids, working, radii)
                // Fully back to semantic length first, then partial pulls.
                for factor in [CGFloat(1), 1.25, 1.6, 2.2] where goal * factor < length {
                    let shift = (length - goal * factor) / length
                    let dx = (anchor.x - end.x) * shift, dy = (anchor.y - end.y) * shift
                    var candidate = working
                    for id in side {
                        if let point = working[id] { candidate[id] = CGPoint(x: point.x + dx, y: point.y + dy) }
                    }
                    guard touchedCrossings(touched, bonds, candidate) <= crossingsBefore,
                          overlapCount(side, ids, candidate, radii) <= overlapsBefore else { continue }
                    working = candidate
                    break moving
                }
            }
        }
    }

    /// Every unordered pair of bonds that properly intersect without sharing a node.
    static func crossingPairs(_ bonds: [Bond], _ positions: [UUID: CGPoint]) -> [(Bond, Bond)] {
        var result: [(Bond, Bond)] = []
        for i in bonds.indices {
            for j in (i + 1)..<bonds.count where crosses(bonds[i], bonds[j], positions) {
                result.append((bonds[i], bonds[j]))
            }
        }
        return result
    }

    static func crossingCount(_ bonds: [Bond], _ positions: [UUID: CGPoint]) -> Int {
        crossingPairs(bonds, positions).count
    }

    private static func crosses(_ first: Bond, _ second: Bond, _ positions: [UUID: CGPoint]) -> Bool {
        guard first.a != second.a, first.a != second.b, first.b != second.a, first.b != second.b,
              let a = positions[first.a], let b = positions[first.b],
              let c = positions[second.a], let d = positions[second.b] else { return false }
        return InsightTreeConnectorRouting.intersectionFraction(a, b, c, d) != nil
    }

    /// The cheapest turn that strictly lowers the crossings among the bonds it touches without
    /// adding a core overlap. A branch hanging off a crossing bond turns rigidly around that
    /// bond's other end. A node on a loop (a Midpoint joined to several parents) cannot turn as
    /// a branch, so it alone may swing around one neighbor, at a higher cost because its other
    /// bonds change length.
    private static func bestMove(
        for crossing: [Bond],
        bonds: [Bond],
        adjacency: [UUID: [UUID]],
        ids: [UUID],
        positions: [UUID: CGPoint],
        pinned: Set<UUID>,
        radii: [UUID: CGFloat]
    ) -> [UUID: CGPoint]? {
        var candidates: [(side: Set<UUID>, pivot: UUID, weight: CGFloat)] = []
        for moving in crossing {
            for (pivot, tip) in [(moving.a, moving.b), (moving.b, moving.a)] {
                if let side = pendantSide(from: tip, across: pivot, adjacency: adjacency) {
                    if side.isDisjoint(with: pinned) { candidates.append((side, pivot, 1)) }
                } else if !pinned.contains(tip) {
                    for neighbor in adjacency[tip] ?? [] { candidates.append(([tip], neighbor, 3)) }
                }
            }
        }

        var best: (cost: CGFloat, move: [UUID: CGPoint])?
        for (side, pivot, weight) in candidates {
            guard let center = positions[pivot] else { continue }
            let touched = bonds.filter { side.contains($0.a) || side.contains($0.b) }
            let crossingsBefore = touchedCrossings(touched, bonds, positions)
            let overlapsBefore = overlapCount(side, ids, positions, radii)
            for angle in rotations {
                // Rotations are ordered smallest-first, so a costlier one cannot win.
                let cost = abs(angle) * CGFloat(side.count) * weight
                if let best, cost >= best.cost { break }
                var candidate = positions
                let cosine = cos(angle), sine = sin(angle)
                for id in side {
                    guard let point = positions[id] else { continue }
                    let dx = point.x - center.x, dy = point.y - center.y
                    candidate[id] = CGPoint(x: center.x + dx * cosine - dy * sine,
                                            y: center.y + dx * sine + dy * cosine)
                }
                guard touchedCrossings(touched, bonds, candidate) < crossingsBefore,
                      overlapCount(side, ids, candidate, radii) <= overlapsBefore else { continue }
                best = (cost, side.reduce(into: [:]) { $0[$1] = candidate[$1] })
                break
            }
        }
        return best?.move
    }

    /// The nodes reachable from `tip` without crossing back over its bond to `pivot`. Nil when
    /// the bond sits on a cycle, because rotating one side would then stretch another bond.
    private static func pendantSide(from tip: UUID, across pivot: UUID, adjacency: [UUID: [UUID]]) -> Set<UUID>? {
        var side: Set<UUID> = [tip]
        var queue = [tip]
        while let current = queue.popLast() {
            for next in adjacency[current] ?? [] {
                if current == tip && next == pivot { continue }
                if next == pivot { return nil }
                if side.insert(next).inserted { queue.append(next) }
            }
        }
        return side
    }

    /// Crossings involving at least one moved bond; crossings elsewhere cannot change.
    private static func touchedCrossings(_ touched: [Bond], _ bonds: [Bond], _ positions: [UUID: CGPoint]) -> Int {
        let touchedSet = Set(touched)
        var count = 0
        for bond in touched {
            for other in bonds where crosses(bond, other, positions) {
                // Count a touched-touched pair once.
                if touchedSet.contains(other) {
                    if bond.a.uuidString + bond.b.uuidString < other.a.uuidString + other.b.uuidString { count += 1 }
                } else {
                    count += 1
                }
            }
        }
        return count
    }

    private static func overlapCount(_ side: Set<UUID>, _ ids: [UUID], _ positions: [UUID: CGPoint], _ radii: [UUID: CGFloat]) -> Int {
        var count = 0
        for id in side {
            guard let point = positions[id] else { continue }
            for other in ids where !side.contains(other) {
                guard let otherPoint = positions[other] else { continue }
                let minimum = ((radii[id] ?? 0) + (radii[other] ?? 0)) * coreClearance
                if hypot(point.x - otherPoint.x, point.y - otherPoint.y) < minimum { count += 1 }
            }
        }
        return count
    }
}
