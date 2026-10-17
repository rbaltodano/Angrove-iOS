import CoreGraphics
import Foundation
import Testing
@testable import AngroveMac

@Suite("Tree growth frontier parity")
struct TreeGrowthFrontierTests {
    @Test("Frontier growth preserves original parents for ties, affinities and fixed-parent cycles")
    func parentParity() {
        for count in [2, 8, 24, 80] {
            let ids = (0..<count).map { stableUUID(from: "frontier-\($0)") }
            for mode in 0..<4 {
                let nodes = ids.enumerated().map { index, id in
                    InsightTreeGrowth.Node(id: id,
                        vector: mode == 0 ? [1, 0, 0] : (0..<8).map { Double((index * 13 + $0 * 7) % 17) / 17 },
                        fixedParents: mode >= 2 && index % 3 == 0 ? [ids[(index + 1) % count]] : [],
                        restoredPosition: CGPoint(x: index * 700, y: 0), radius: 80, leansToward: [])
                }
                let affinity: [Set<UUID>: Double] = mode == 3 ? [Set(ids.prefix(2)): 0.12] : [:]
                let actual = InsightTreeGrowth.grow(nodes, affinity: affinity, relayout: false)
                #expect(actual.parents == referenceParents(nodes, affinity: affinity))
                #expect(actual.parents.count == count - 1)
            }
        }
    }

    // Original exhaustive selection is retained only as a small-fixture oracle.
    private func referenceParents(_ nodes: [InsightTreeGrowth.Node], affinity: [Set<UUID>: Double]) -> [UUID: UUID] {
        typealias Node = InsightTreeGrowth.Node
        var result = InsightTreeGrowth.Result()
        guard !nodes.isEmpty else { return [:] }
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
        let root = rootCandidates.max { lhs, rhs in
            let left = descendantCounts[lhs.id] ?? 0, right = descendantCounts[rhs.id] ?? 0
            if left != right { return left < right }
            let lc = ordered.reduce(0) { $0 + ($1.id == lhs.id ? 0 : similarity(lhs, $1)) }
            let rc = ordered.reduce(0) { $0 + ($1.id == rhs.id ? 0 : similarity(rhs, $1)) }
            return lc == rc ? lhs.id.uuidString > rhs.id.uuidString : lc < rc
        }!
        result.root = root.id

        // Prim's growth, honoring saved/explicit parents first; a free node joins the attached
        // node it is most similar to. Each node attaches once, so no cycle can form.
        var attached: [UUID] = [root.id]
        var attachedSet: Set<UUID> = [root.id]
        while attachedSet.count < nodes.count {
            if let waiting = ordered.first(where: { node in
                !attachedSet.contains(node.id) && parentPreference(node).map(attachedSet.contains) == true
            }), let parent = parentPreference(waiting) {
                result.parents[waiting.id] = parent
                attached.append(waiting.id); attachedSet.insert(waiting.id)
                if !waiting.vector.isEmpty { result.persistableParents[waiting.id] = parent }
                continue
            }
            // Nodes whose explicit parent is still unattached wait, unless nothing else can move.
            let free = ordered.filter { !attachedSet.contains($0.id) && parentPreference($0) == nil }
            let pool = free.isEmpty ? ordered.filter { !attachedSet.contains($0.id) } : free
            var best: (child: Node, parent: UUID, score: Double)?
            for child in pool {
                for parentID in attached {
                    guard let parent = byID[parentID] else { continue }
                    let score = similarity(child, parent)
                    if best == nil || score > best!.score { best = (child, parentID, score) }
                }
            }
            guard let best else { break }
            result.parents[best.child.id] = best.parent
            attached.append(best.child.id); attachedSet.insert(best.child.id)
            if !best.child.vector.isEmpty, byID[best.parent]?.vector.isEmpty == false {
                result.persistableParents[best.child.id] = best.parent
            }
        }
        return result.parents
    }
}
