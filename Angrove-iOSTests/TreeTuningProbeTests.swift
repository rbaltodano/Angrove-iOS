import Foundation
import Testing
@testable import Angrove_iOS

/// TEMP: offline tuning against a device snapshot. Removed before merge.
private let treeTuningDumpPath = "/private/tmp/claude-501/-Users-ryanbaltodano-Developer-Aquinas-iOS-main/11fe7ee4-5eb2-4ce9-a69e-d1df63e9361a/scratchpad/dump/tree-dump.json"

@Suite("Tree tuning probe", .enabled(if: FileManager.default.fileExists(atPath: treeTuningDumpPath)))
struct TreeTuningProbeTests {
    static let path = treeTuningDumpPath
    struct DumpInsight: Decodable { let id: UUID; let title: String; let definition: String }
    struct DumpNode: Decodable { let id: UUID; let label: String; let definition: String; let kind: String; let insightIDs: [UUID] }
    struct Dump: Decodable { let nodes: [DumpNode]; let insights: [DumpInsight]; let edges: [[UUID]] }

    @Test func probe() async throws {
        let dump = try JSONDecoder().decode(Dump.self, from: Data(contentsOf: URL(fileURLWithPath: Self.path)))
        let provider = try MiniLMEmbeddingProvider()
        var vectors: [UUID: [Double]] = [:]
        for node in dump.nodes { vectors[node.id] = await provider.embed("\(node.label). \(node.definition)") }
        var out = ""
        let nodes = dump.nodes
        out += "SUBJECT SIMILARITY (top 3 per node)\n"
        for a in nodes {
            let ranked = nodes.filter { $0.id != a.id }.map { ($0.label, cosineSimilarity(vectors[a.id]!, vectors[$0.id]!)) }.sorted { $0.1 > $1.1 }
            out += "\(a.kind.prefix(4)) \(a.label): " + ranked.prefix(3).map { "\($0.0) \(String(format: "%.2f", $0.1))" }.joined(separator: " | ") + "\n"
        }
        out += "\nINSIGHTS vs nodes\n"
        for insight in dump.insights {
            guard let v = await provider.embed("\(insight.title). \(insight.definition)") else { continue }
            let owner = nodes.first { $0.insightIDs.contains(insight.id) }?.label ?? "-"
            let ranked = nodes.map { ($0.label, cosineSimilarity(v, vectors[$0.id]!)) }.sorted { $0.1 > $1.1 }
            out += "\(insight.title) [in \(owner)]: " + ranked.prefix(3).map { "\($0.0) \(String(format: "%.2f", $0.1))" }.joined(separator: " | ") + "\n"
        }
        try out.write(toFile: Self.path.replacingOccurrences(of: "tree-dump.json", with: "probe.txt"), atomically: true, encoding: .utf8)
    }

    @Test func growProbe() async throws {
        let dump = try JSONDecoder().decode(Dump.self, from: Data(contentsOf: URL(fileURLWithPath: Self.path)))
        let provider = try MiniLMEmbeddingProvider()
        var vectors: [UUID: [Double]] = [:]
        for node in dump.nodes { vectors[node.id] = await provider.embed("\(node.label). \(node.definition)") }
        let label = Dictionary(uniqueKeysWithValues: dump.nodes.map { ($0.id, $0.label) })
        var explicit: [UUID: [UUID]] = [:]
        for edge in dump.edges where dump.nodes.first(where: { $0.id == edge[1] })?.kind == "midpointConcept" {
            explicit[edge[1], default: []].append(edge[0])
        }
        for (child, parents) in explicit {
            explicit[child] = parents.sorted { cosineSimilarity(vectors[child]!, vectors[$0]!) > cosineSimilarity(vectors[child]!, vectors[$1]!) }
        }
        var affinity: [Set<UUID>: Double] = [:]
        for parents in explicit.values where parents.count > 1 { for a in parents { for b in parents where a != b { affinity[[a, b]] = 0.12 } } }
        let nodes = dump.nodes.map { node in
            InsightTreeGrowth.Node(id: node.id, vector: vectors[node.id]!, fixedParents: explicit[node.id] ?? [],
                restoredPosition: nil, radius: 300, leansToward: node.kind == "midpointConcept" ? (explicit[node.id] ?? []) : [])
        }
        let grown = InsightTreeGrowth.grow(nodes, affinity: affinity, relayout: true)
        var out = "ROOT \(label[grown.root!]!)\n"
        for (child, parent) in grown.parents.sorted(by: { label[$0.key]! < label[$1.key]! }) {
            out += "\(label[child]!) <- \(label[parent]!) \(String(format: "%.2f", cosineSimilarity(vectors[child]!, vectors[parent]!)))\n"
        }
        var edges = grown.parents.map { ($0.value, $0.key) }
        for (child, parents) in explicit { for parent in parents where grown.parents[child] != parent { edges.append((parent, child)) } }
        let bonds = edges.map { InsightTreeEdgeUntangling.Bond.between($0.0, $0.1) }
        out += "crossings after growth: \(InsightTreeEdgeUntangling.crossingCount(bonds, grown.positions)) of \(bonds.count) lines\n"
        let lengths = edges.map { hypot(grown.positions[$0.0]!.x - grown.positions[$0.1]!.x, grown.positions[$0.0]!.y - grown.positions[$0.1]!.y) }
        out += "line lengths: min \(Int(lengths.min()!)) max \(Int(lengths.max()!))\n"
        let treeBonds = grown.parents.map { InsightTreeEdgeUntangling.Bond.between($0.key, $0.value) }
        out += "tree-only crossings: \(InsightTreeEdgeUntangling.crossingCount(treeBonds, grown.positions))\n"
        var lengthMap: [InsightTreeEdgeUntangling.Bond: CGFloat] = [:]
        for (a, b) in edges { lengthMap[.between(a, b)] = mapDistanceToLength(1 - cosineSimilarity(vectors[a]!, vectors[b]!)) }
        let pinned = Set(dump.nodes.filter { $0.kind == "midpointConcept" }.map(\.id))
        let untangled = InsightTreeEdgeUntangling.untangle(positions: grown.positions, edges: edges, pinned: pinned,
            radii: grown.positions.mapValues { _ in 300 }, lengths: lengthMap)
        out += "after untangle (midpoints pinned): \(InsightTreeEdgeUntangling.crossingCount(bonds, untangled))\n"
        let free = InsightTreeEdgeUntangling.untangle(positions: grown.positions, edges: edges, pinned: [],
            radii: grown.positions.mapValues { _ in 300 }, lengths: lengthMap)
        out += "after untangle (nothing pinned): \(InsightTreeEdgeUntangling.crossingCount(bonds, free))\n"
        let freeLengths = edges.map { hypot(free[$0.0]!.x - free[$0.1]!.x, free[$0.0]!.y - free[$0.1]!.y) }.sorted()
        out += "final line lengths: \(freeLengths.map { Int($0) })\n"
        try out.write(toFile: Self.path.replacingOccurrences(of: "tree-dump.json", with: "grow.txt"), atomically: true, encoding: .utf8)
    }
}
