import CoreGraphics
import Foundation

/// How the Insight Tree grows. Every Node Concept hangs from exactly one parent, chosen once by
/// subject similarity and then kept, and is drawn off that parent. Lines and positions therefore
/// come from the same decision and never drift apart. Insights attach loosely or tightly to the
/// nearest concept; a cohesive group of loose Insights buds off into a child concept.
///
/// Similarities are cosine similarity in the bundled MiniLM space (see
/// `InsightTreeSemanticPolicy`), calibrated against a real device tree: Insights score 0.50–0.78
/// against their own concept and related concepts score 0.45–0.70 against each other.
nonisolated enum InsightTreeGrowth {
    /// Below this against every concept, an Insight starts a new concept of its own.
    static let attachSimilarity = 0.35
    /// At or above this an Insight is a tight member; between the two it hangs loosely and is
    /// a candidate for budding.
    static let tightSimilarity = 0.50
    /// A bud's members must each sit this close to the bud's own centroid.
    static let budCohesion = 0.55
    static let budMinimumCount = 3
    /// A bud this similar to its origin is just the origin reworded, so it stays put. Kept below
    /// `nodeMergeSimilarity` so the merge pass never folds a new bud straight back.
    static let budMaximumParentSimilarity = 0.62
    /// Bud members must be closer to each other, on average, than to their origin by this much.
    static let budSeparationMargin = 0.05
    /// Two concepts that share a Midpoint are pulled together when choosing parents, so the
    /// Midpoint between them stays short.
    static let sharedMidpointAffinity = 0.12

    // MARK: - Budding

    struct Member: Equatable {
        let id: UUID
        let vector: [Double]
    }

    /// The loose members of one concept that should bud into a child concept, or nil.
    static func budGroup(members: [Member], anchor: [Double]) -> [UUID]? {
        guard !anchor.isEmpty else { return nil }
        let loose = members.filter {
            $0.vector.count == anchor.count && cosineSimilarity($0.vector, anchor) < tightSimilarity
        }
        guard loose.count >= budMinimumCount else { return nil }

        // Start from the loose member with the most close neighbors, then settle on the members
        // close to the group's own centroid. Requiring closeness to the centroid, not just to a
        // neighbor, keeps a chain (A~B, B~C, A≁C) from counting as a group.
        var group: [Member] = []
        for candidate in loose.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let neighbors = loose.filter { cosineSimilarity($0.vector, candidate.vector) >= budCohesion }
            if neighbors.count > group.count { group = neighbors }
        }
        guard group.count >= budMinimumCount else { return nil }
        for _ in 0..<3 {
            let center = centroid(group.map(\.vector))
            let next = loose.filter { cosineSimilarity($0.vector, center) >= budCohesion }
            if next.map(\.id) == group.map(\.id) { break }
            group = next
        }
        guard group.count >= budMinimumCount else { return nil }

        let center = centroid(group.map(\.vector))
        guard cosineSimilarity(center, anchor) < budMaximumParentSimilarity else { return nil }
        let toEachOther = group.map { cosineSimilarity($0.vector, center) }.reduce(0, +) / Double(group.count)
        let toOrigin = group.map { cosineSimilarity($0.vector, anchor) }.reduce(0, +) / Double(group.count)
        guard toEachOther >= toOrigin + budSeparationMargin else { return nil }
        return group.map(\.id).sorted { $0.uuidString < $1.uuidString }
    }

    // MARK: - Parents and placement

    struct Node: Sendable {
        let id: UUID
        /// Subject vector (label and definition); empty when not embedded yet.
        let vector: [Double]
        /// Saved or explicit parents, most preferred first (a Midpoint's sources, a promoted
        /// node's origin, or the parent this node grew from last time).
        let fixedParents: [UUID]
        let restoredPosition: CGPoint?
        /// Footprint radius, to keep a newly placed node off its neighbors.
        let radius: CGFloat
        /// Placed Midpoints lean toward all of their sources, not just their tree parent.
        let leansToward: [UUID]
    }

    struct Result: Sendable {
        var parents: [UUID: UUID] = [:]
        var positions: [UUID: CGPoint] = [:]
        /// Nodes given a fresh position this pass (their layout anchors must follow).
        var placed: Set<UUID> = []
        /// Parent links chosen with real vectors on both ends, safe to save.
        var persistableParents: [UUID: UUID] = [:]
        var root: UUID?
    }

    /// Attaches every node to one parent and places any node without a usable position.
    /// `relayout` places every node fresh from the root (used once to migrate older trees).
    static func grow(_ nodes: [Node], affinity: [Set<UUID>: Double] = [:], relayout: Bool) -> Result {
        var result = Result()
        guard !nodes.isEmpty else { return result }
        let byID = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = nodes.sorted { $0.id.uuidString < $1.id.uuidString }

        func similarity(_ a: Node, _ b: Node) -> Double {
            let base = a.vector.isEmpty || a.vector.count != b.vector.count ? 0 : cosineSimilarity(a.vector, b.vector)
            return base + (affinity[[a.id, b.id]] ?? 0)
        }
        func parentPreference(_ node: Node) -> UUID? {
            node.fixedParents.first { byID[$0] != nil && $0 != node.id }
        }

        // Root: the node most other saved links lead to; on a fresh tree, the most central one.
        var descendantCounts: [UUID: Int] = [:]
        for node in nodes {
            var current = node.id
            var seen: Set<UUID> = [current]
            while let parent = byID[current].flatMap(parentPreference), seen.insert(parent).inserted {
                current = parent
            }
            descendantCounts[current, default: 0] += 1
        }
        // A node with its own explicit parent cannot be the root while a free node exists.
        // A concept still waiting for its vector cannot anchor the tree either.
        let free = ordered.filter { parentPreference($0) == nil }
        let embedded = free.filter { !$0.vector.isEmpty }
        let rootCandidates = embedded.isEmpty ? (free.isEmpty ? ordered : free) : embedded
        let centrality = Dictionary(uniqueKeysWithValues: rootCandidates.map { candidate in
            (candidate.id, ordered.reduce(0.0) { $0 + ($1.id == candidate.id ? 0 : similarity(candidate, $1)) })
        })
        let root = rootCandidates.max { lhs, rhs in
            let left = descendantCounts[lhs.id] ?? 0, right = descendantCounts[rhs.id] ?? 0
            if left != right { return left < right }
            let lc = centrality[lhs.id] ?? 0
            let rc = centrality[rhs.id] ?? 0
            return lc == rc ? lhs.id.uuidString > rhs.id.uuidString : lc < rc
        }!
        result.root = root.id

        // Prim's growth, honoring saved/explicit parents first; a free node joins the attached
        // node it is most similar to. Each node attaches once, so no cycle can form.
        var attached: [UUID] = [root.id]
        var attachedSet: Set<UUID> = [root.id]
        // Each newly attached parent updates the frontier once. Preserve the first attached
        // parent for exact ties, matching the original nested scan's deterministic order.
        var frontier: [UUID: (parent: UUID, score: Double)] = [:]
        func addParent(_ parent: Node) {
            for child in ordered where !attachedSet.contains(child.id) {
                let score = similarity(child, parent)
                if frontier[child.id] == nil || score > frontier[child.id]!.score {
                    frontier[child.id] = (parent.id, score)
                }
            }
        }
        addParent(root)
        while attachedSet.count < nodes.count {
            if Task.isCancelled { return Result() }
            if let waiting = ordered.first(where: { node in
                !attachedSet.contains(node.id) && parentPreference(node).map(attachedSet.contains) == true
            }), let parent = parentPreference(waiting) {
                result.parents[waiting.id] = parent
                attached.append(waiting.id); attachedSet.insert(waiting.id)
                addParent(waiting)
                if !waiting.vector.isEmpty { result.persistableParents[waiting.id] = parent }
                continue
            }
            // Nodes whose explicit parent is still unattached wait, unless nothing else can move.
            let free = ordered.filter { !attachedSet.contains($0.id) && parentPreference($0) == nil }
            let pool = free.isEmpty ? ordered.filter { !attachedSet.contains($0.id) } : free
            var best: (child: Node, parent: UUID, score: Double)?
            for child in pool {
                guard let edge = frontier[child.id] else { continue }
                if best == nil || edge.score > best!.score { best = (child, edge.parent, edge.score) }
            }
            guard let best else { break }
            result.parents[best.child.id] = best.parent
            attached.append(best.child.id); attachedSet.insert(best.child.id)
            addParent(best.child)
            if !best.child.vector.isEmpty, byID[best.parent]?.vector.isEmpty == false {
                result.persistableParents[best.child.id] = best.parent
            }
        }

        // Lines beyond the tree (a Midpoint's other sources), known to both ends, so placement
        // keeps them from crossing too.
        var secondary: [UUID: Set<UUID>] = [:]
        for node in nodes {
            for parent in node.fixedParents where byID[parent] != nil && parent != node.id && result.parents[node.id] != parent
                && result.parents[parent] != node.id {
                secondary[node.id, default: []].insert(parent)
                secondary[parent, default: []].insert(node.id)
            }
        }

        // Placement, parents before children.
        var children: [UUID: [UUID]] = [:]
        for id in attached { if let parent = result.parents[id] { children[parent, default: []].append(id) } }
        for id in attached {
            guard let node = byID[id] else { continue }
            if !relayout, let restored = node.restoredPosition {
                result.positions[id] = restored
                continue
            }
            guard let parentID = result.parents[id], let parent = byID[parentID],
                  let anchor = result.positions[parentID] else {
                result.positions[id] = node.restoredPosition ?? .zero
                if node.restoredPosition == nil || relayout { result.placed.insert(id) }
                continue
            }
            let length = mapDistanceToLength(1 - min(max(similarity(node, parent), 0), 1))
            result.positions[id] = placement(of: node, from: anchor, parentID: parentID, length: length,
                                             byID: byID, result: result, children: children, secondary: secondary)
            result.placed.insert(id)
        }
        if relayout { recenter(&result, on: nodes.compactMap(\.restoredPosition)) }
        return result
    }

    /// A fresh layout keeps the old tree's center, so the camera still finds it.
    private static func recenter(_ result: inout Result, on previous: [CGPoint]) {
        guard !previous.isEmpty, !result.positions.isEmpty else { return }
        func center(_ points: [CGPoint]) -> CGPoint {
            CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
                    y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
        }
        let target = center(previous), current = center(Array(result.positions.values))
        let dx = target.x - current.x, dy = target.y - current.y
        for (id, point) in result.positions { result.positions[id] = CGPoint(x: point.x + dx, y: point.y + dy) }
        result.placed = Set(result.positions.keys)
    }

    /// Off its parent, in a direction clear of the parent's other connectors and of nearby
    /// nodes: toward a Midpoint's other sources, or else continuing away from the grandparent.
    private static func placement(
        of node: Node,
        from anchor: CGPoint,
        parentID: UUID,
        length: CGFloat,
        byID: [UUID: Node],
        result: Result,
        children: [UUID: [UUID]],
        secondary: [UUID: Set<UUID>]
    ) -> CGPoint {
        var neighbors = (children[parentID] ?? []).filter { $0 != node.id }
        if let grandparent = result.parents[parentID] { neighbors.append(grandparent) }
        let occupied = neighbors.compactMap { id -> CGFloat? in
            guard let point = result.positions[id] else { return nil }
            return atan2(point.y - anchor.y, point.x - anchor.x)
        }

        let leanTargets = node.leansToward.compactMap { result.positions[$0] }.filter { $0 != anchor }
        let preferred: CGFloat
        if !leanTargets.isEmpty {
            let center = CGPoint(x: leanTargets.map(\.x).reduce(0, +) / CGFloat(leanTargets.count),
                                 y: leanTargets.map(\.y).reduce(0, +) / CGFloat(leanTargets.count))
            preferred = atan2(center.y - anchor.y, center.x - anchor.x)
        } else if let grandparent = result.parents[parentID], let point = result.positions[grandparent] {
            preferred = atan2(anchor.y - point.y, anchor.x - point.x)
        } else {
            preferred = -.pi / 2
        }

        func gap(_ angle: CGFloat) -> CGFloat {
            occupied.map { abs(wrapped(angle - $0)) }.min() ?? .pi
        }
        func clearance(_ point: CGPoint) -> Bool {
            result.positions.allSatisfy { id, other in
                let minimum = (node.radius + (byID[id]?.radius ?? 0)) * InsightTreeEdgeUntangling.coreClearance
                return hypot(point.x - other.x, point.y - other.y) >= minimum
            }
        }
        // Every line already drawn (tree and secondary), so the new node's own lines (to its
        // parent and to any placed secondary partner) can avoid crossing them.
        var drawn: [(CGPoint, CGPoint)] = result.parents.compactMap { child, parent in
            guard child != node.id, let a = result.positions[child], let b = result.positions[parent] else { return nil }
            return (a, b)
        }
        for (id, partners) in secondary where id != node.id {
            for partner in partners where partner != node.id && id.uuidString < partner.uuidString {
                if let a = result.positions[id], let b = result.positions[partner] { drawn.append((a, b)) }
            }
        }
        let partners = (secondary[node.id] ?? []).compactMap { result.positions[$0] }
        func crossings(_ point: CGPoint) -> Int {
            ([anchor] + partners).reduce(0) { total, end in
                total + drawn.filter { segment in
                    segment.0 != end && segment.1 != end
                        && InsightTreeConnectorRouting.intersectionFraction(end, point, segment.0, segment.1) != nil
                }.count
            }
        }
        let candidates = stride(from: 0, to: 360, by: 10).map { CGFloat($0) * .pi / 180 }
        let scored = candidates.map { angle -> (angle: CGFloat, score: CGFloat) in
            let point = CGPoint(x: anchor.x + cos(angle) * length, y: anchor.y + sin(angle) * length)
            // No crossings first, then clear space, then an open angle, then the preferred direction.
            let score = CGFloat(-20 * crossings(point)) + (clearance(point) ? 10 : 0)
                + min(gap(angle), .pi / 3) * 3 - abs(wrapped(angle - preferred))
            return (angle, score)
        }
        let angle = scored.max { $0.score == $1.score ? $0.angle > $1.angle : $0.score < $1.score }!.angle
        return CGPoint(x: anchor.x + cos(angle) * length, y: anchor.y + sin(angle) * length)
    }

    private static func wrapped(_ angle: CGFloat) -> CGFloat {
        var value = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if value > .pi { value -= 2 * .pi }
        if value < -.pi { value += 2 * .pi }
        return value
    }
}
