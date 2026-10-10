import SwiftUI
import UIKit
import simd

// Simulation behavior for the shared global and conversation canvas.
extension InsightTreeCanvasView {
    // MARK: - Live Physics Simulation

    /// `nodes` with each position replaced by its live simulated position (falls back to the
    /// view model's position until a body is seeded). Everything renders off this.
    var displayNodes: [NodeModel] {
        nodes.map { node in
            guard let body = bodies[node.id] else { return node }
            var copy = node
            copy.position = body.pos
            return copy
        }
    }

    func canvasInsights(for node: NodeModel) -> [InsightModel] {
        let members = canvasInsightMembers(
            nodeLabel: node.conceptLabel,
            insights: node.insights,
            preservesMatchingTitle: placedMidpointNodeIDs.contains(node.id)
        )
        return showsAllClusterInsights ? members : Array(members.prefix(6))
    }

    /// Live simulated position for a node id (for by-id lookups).
    func simPosition(of id: UUID) -> CGPoint? {
        bodies[id]?.pos ?? nodes.first(where: { $0.id == id })?.position
    }

    /// Node footprint for the overlap-separation force — its longest bond plus chip extent.
    private func simFootprintRadius(_ node: NodeModel) -> CGFloat {
        if placedMidpointNodeIDs.contains(node.id) { return 70 }
        let maxBond = canvasInsights(for: node)
            .map { bondLength(forInsightID: $0.id) }
            .max() ?? 70
        return maxBond + 64
    }

    func startSim(
        intensity: Double = 1,
        alphaDecay: Double = Self.alphaDecay,
        addsBreeze: Bool = false,
        frameBudget: Int = Self.settleFrameBudget
    ) {
        simFramesRemaining = max(simFramesRemaining, frameBudget)
        alpha = max(alpha, intensity)
        simAlphaDecay = alphaDecay
        if addsBreeze {
            breezeStartedAt = CACurrentMediaTime()
            let angle = CGFloat.random(in: -0.5...0.5)
            breezeDirection = CGVector(dx: cos(angle), dy: sin(angle))
        }
        lastTickAt = 0
        guard displayLink == nil else { return }
        let driver = DisplayLinkDriver()
        driver.onTick = { ts in stepSimulation(now: ts) }
        driver.start()
        displayLink = driver
    }

    func stopSim() {
        displayLink?.stop()
        displayLink = nil
        simFramesRemaining = 0
        lastTickAt = 0
    }

    private func freezeSimulation(_ nextBodies: [UUID: SimBody]? = nil) {
        var frozen = nextBodies ?? bodies
        for (id, var body) in frozen {
            body.vel = .zero
            frozen[id] = body
        }
        bodies = frozen
        alpha = 0
        breezeStartedAt = nil
        stopSim()
    }

    /// Seed bodies for new nodes, drop bodies for removed nodes, preserve the rest (no jump),
    /// and wake the sim. Called when the view model's topology changes.
    func reconcileBodies() {
        let isInitialLayout = bodies.isEmpty
        let liveIDs = Set(nodes.map(\.id))
        var next = bodies.filter { liveIDs.contains($0.key) }
        if !isInitialLayout {
            for (id, var body) in next {
                body.vel = CGVector(
                    dx: body.vel.dx * 0.2,
                    dy: body.vel.dy * 0.2
                )
                next[id] = body
            }
        }
        for node in nodes where next[node.id] == nil {
            next[node.id] = SimBody(pos: node.position, vel: .zero)
        }
        bodies = next

        // Seed/drop per-insight bond angles. A node without external bonds starts evenly
        // distributed. Otherwise every new Insight enters the largest open arc among both its
        // sibling Insight bonds and all node-to-node lines connected to the parent concept.
        let chipIDs = Set(nodes.flatMap { canvasInsights(for: $0).map(\.id) })
        var nextAngles = chipAngles.filter { chipIDs.contains($0.key) }
        pinnedChipAngleIDs.formIntersection(chipIDs)
        for node in nodes {
            let visibleInsights = canvasInsights(for: node)
            var occupiedAngles = connectedNodeBondAngles(for: node.id)
            if isInitialLayout && occupiedAngles.isEmpty {
                for (index, insight) in visibleInsights.enumerated() where nextAngles[insight.id] == nil {
                    nextAngles[insight.id] = ChipAngle(
                        angle: baseChipAngle(index: index, count: visibleInsights.count)
                    )
                }
                continue
            }

            occupiedAngles.append(
                contentsOf: visibleInsights.compactMap { nextAngles[$0.id]?.angle }
            )
            for insight in visibleInsights where nextAngles[insight.id] == nil {
                let seed = maximizedChipGapAngle(among: occupiedAngles)
                nextAngles[insight.id] = ChipAngle(angle: seed)
                occupiedAngles.append(seed)
            }
        }
        chipAngles = nextAngles

        // Seed elevation angles here too, not only in the sim: opening a tree freezes the sim, so
        // it never runs to assign them and every Insight would sit flat on the plane. Insights
        // already placed keep their angle; the sim (when it runs) eases them to new targets.
        var nextElevations = chipElevationAngles.filter { chipIDs.contains($0.key) }
        for node in nodes where !placedMidpointNodeIDs.contains(node.id) {
            let members = canvasInsights(for: node).compactMap { insight in
                nextAngles[insight.id].map {
                    InsightClusterSpatialLayout.Member(id: insight.id, azimuth: $0.angle)
                }
            }
            for (id, target) in InsightClusterSpatialLayout.elevationTargets(members)
            where nextElevations[id] == nil {
                nextElevations[id] = target
            }
        }
        chipElevationAngles = nextElevations

        if isInitialLayout {
            // Restored positions are already authoritative. Opening the Canvas should be
            // perfectly still rather than replaying a global settling pass.
            freezeSimulation()
        } else {
            startSim(
                intensity: Self.updateIntensity,
                alphaDecay: Self.updateAlphaDecay,
                addsBreeze: true,
                frameBudget: 90
            )
        }
    }

    /// One cleanup step. Anchors each node to its semantic (MDS) target, separates overlapping
    /// footprints/chips, spreads chip-label angles, holds pinned nodes fixed, and writes back once.
    func stepSimulation(now: CFTimeInterval) {
        guard !bodies.isEmpty else { return }
        guard simFramesRemaining > 0 else {
            freezeSimulation()
            return
        }
        let dt = lastTickAt == 0 ? CGFloat(1.0 / 60) : CGFloat(min(now - lastTickAt, Self.simMaxDt))
        lastTickAt = now
        let dtScale = dt * 60   // ≈1 at 60fps; keeps motion frame-rate independent

        // Which nodes are held fixed this frame.
        var pinned = placedMidpointNodeIDs
        if isHoveringTarget, let focused = focusedNodeID() {
            pinned.insert(focused)   // keep the open-card node from sliding under its card
        }

        let nodeByID = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let entries = bodies.map { ($0.key, $0.value) }
        var forces: [UUID: CGVector] = [:]
        var maxChipAngMotion: Double = 0   // keeps the sim awake while chips are still spreading

        // Live world footprint of every visible chip. These participate in one global collision
        // pass, regardless of which Node Concept owns them.
        struct ChipInfo {
            let id: UUID
            let nodeID: UUID
            let angle: Double
            let radius: CGFloat
            let pos: CGPoint
            let halfWidth: CGFloat
            let halfHeight: CGFloat
        }
        var chipInfos: [ChipInfo] = []
        for node in nodes {
            guard let body = bodies[node.id] else { continue }
            if placedMidpointNodeIDs.contains(node.id) {
                guard let insight = node.insights.first else { continue }
                let size = insightCollisionSize(for: insight)
                chipInfos.append(
                    ChipInfo(
                        id: insight.id,
                        nodeID: node.id,
                        angle: 0,
                        radius: 0,
                        pos: body.pos,
                        halfWidth: size.width / 2,
                        halfHeight: size.height / 2
                    )
                )
                continue
            }
            let visibleInsights = canvasInsights(for: node)
            for (index, insight) in visibleInsights.enumerated() {
                let theta: Double
                let radius: CGFloat
                let pos: CGPoint
                if draggingChipID == insight.id, let live = draggingChipWorldPosition {
                    // The dragged chip's real-time position, so collision/spread this frame
                    // reacts to where it actually is right now instead of its last committed
                    // (angle, bond length) — this is what makes nearby chips make room for it
                    // live instead of only after the drag ends.
                    pos = live
                    radius = hypot(live.x - body.pos.x, live.y - body.pos.y)
                    theta = Double(atan2(live.y - body.pos.y, live.x - body.pos.x))
                } else {
                    theta = chipAngles[insight.id]?.angle ?? baseChipAngle(index: index, count: visibleInsights.count)
                    radius = bondLength(forInsightID: insight.id)
                    pos = CGPoint(x: body.pos.x + cos(theta) * radius, y: body.pos.y + sin(theta) * radius)
                }
                let size = insightCollisionSize(for: insight)
                chipInfos.append(
                    ChipInfo(
                        id: insight.id,
                        nodeID: node.id,
                        angle: theta,
                        radius: radius,
                        pos: pos,
                        halfWidth: size.width / 2,
                        halfHeight: size.height / 2
                    )
                )
            }
        }

        // Every domain around a node: its insight bonds AND the fixed directions of its
        // node-to-node lines. Only chip angles move — node positions belong to the MDS targets,
        // so line directions act as read-only repellers that keep chips off visible edges.
        enum BondKind { case insight(UUID); case fixedEdge }
        struct Bond { let angle: Double; let kind: BondKind }
        var bondsByNode: [UUID: [Bond]] = [:]
        var chipInfoByID: [UUID: ChipInfo] = [:]
        for ci in chipInfos {
            bondsByNode[ci.nodeID, default: []].append(Bond(angle: ci.angle, kind: .insight(ci.id)))
            chipInfoByID[ci.id] = ci
        }
        // Use the SAME edges that are rendered (displayGraphEdges fabricates a line for the
        // 2-node / ring fallback), so every visible node-to-node line repels chips too.
        for edge in displayGraphEdges() {
            guard let aPos = bodies[edge.fromNodeID]?.pos, let bPos = bodies[edge.toNodeID]?.pos else { continue }
            bondsByNode[edge.fromNodeID, default: []].append(Bond(angle: Double(atan2(bPos.y - aPos.y, bPos.x - aPos.x)), kind: .fixedEdge))
            bondsByNode[edge.toNodeID, default: []].append(Bond(angle: Double(atan2(aPos.y - bPos.y, aPos.x - bPos.x)), kind: .fixedEdge))
        }

        // Insight collision. A collision rotates both free bonds away from contact; across nodes
        // it also gently separates their parent nodes, allowing Insights in unrelated concepts to
        // affect one another without discarding the semantic layout. Same-node chips only rotate:
        // the angular spread below is planar, and opposite elevations can still bring two sibling
        // labels together on screen.
        var crossNodeForces: [UUID: CGVector] = [:]
        var chipTorque: [UUID: Double] = [:]
        func addCrossNodeForce(_ force: CGVector, to nodeID: UUID) {
            let current = crossNodeForces[nodeID, default: .zero]
            crossNodeForces[nodeID] = CGVector(
                dx: current.dx + force.dx,
                dy: current.dy + force.dy
            )
        }
        let chipRectangles = chipInfos.map {
            CGRect(x: $0.pos.x - $0.halfWidth - Self.insightCollisionPadding / 2,
                   y: $0.pos.y - $0.halfHeight - Self.insightCollisionPadding / 2,
                   width: $0.halfWidth * 2 + Self.insightCollisionPadding,
                   height: $0.halfHeight * 2 + Self.insightCollisionPadding)
        }
        for pair in SpatialCollisionIndex.pairs(for: chipRectangles) {
            do {
                let first = chipInfos[pair.first]
                let second = chipInfos[pair.second]
                let isSameNode = first.nodeID == second.nodeID

                let dx = first.pos.x - second.pos.x
                let dy = first.pos.y - second.pos.y
                let overlapX = first.halfWidth + second.halfWidth
                    + Self.insightCollisionPadding - abs(dx)
                let overlapY = first.halfHeight + second.halfHeight
                    + Self.insightCollisionPadding - abs(dy)
                guard overlapX > 0, overlapY > 0 else { continue }

                let firstSortsBeforeSecond = first.id.uuidString < second.id.uuidString
                let xDirection: CGFloat = abs(dx) > 0.5
                    ? (dx >= 0 ? 1 : -1)
                    : (firstSortsBeforeSecond ? -1 : 1)
                let yDirection: CGFloat = abs(dy) > 0.5
                    ? (dy >= 0 ? 1 : -1)
                    : (firstSortsBeforeSecond ? 1 : -1)
                let separation: CGVector = overlapX < overlapY
                    ? CGVector(dx: xDirection * overlapX, dy: 0)
                    : CGVector(dx: 0, dy: yDirection * overlapY)
                let separationLength = max(hypot(separation.dx, separation.dy), 1)
                let unitX = separation.dx / separationLength
                let unitY = separation.dy / separationLength
                let force = CGVector(
                    dx: separation.dx * Self.bubblePushK,
                    dy: separation.dy * Self.bubblePushK
                )
                if !isSameNode {
                    addCrossNodeForce(force, to: first.nodeID)
                    addCrossNodeForce(CGVector(dx: -force.dx, dy: -force.dy), to: second.nodeID)
                }

                let normalizedDepth = Double(min(min(overlapX, overlapY) / 48, 2))
                if first.radius > 1 {
                    let tangentX = CGFloat(-sin(first.angle))
                    let tangentY = CGFloat(cos(first.angle))
                    let tangentialContact = Double(unitX * tangentX + unitY * tangentY)
                    chipTorque[first.id, default: 0] +=
                        tangentialContact * normalizedDepth * Self.crossNodeChipTorqueK
                }
                if second.radius > 1 {
                    let tangentX = CGFloat(-sin(second.angle))
                    let tangentY = CGFloat(cos(second.angle))
                    let tangentialContact = Double(-unitX * tangentX - unitY * tangentY)
                    chipTorque[second.id, default: 0] +=
                        tangentialContact * normalizedDepth * Self.crossNodeChipTorqueK
                }
            }
        }

        // Anchor spring toward the MDS target + whole-node and global Insight separation.
        let nodeRectangles = entries.map { entry -> CGRect in
            let radius = nodeByID[entry.0].map { simFootprintRadius($0) } ?? 240
            return CGRect(x: entry.1.pos.x - radius - Self.overlapPadding / 2, y: entry.1.pos.y - radius - Self.overlapPadding / 2,
                          width: radius * 2 + Self.overlapPadding, height: radius * 2 + Self.overlapPadding)
        }
        var neighborIndices: [Int: [Int]] = [:]
        for pair in SpatialCollisionIndex.pairs(for: nodeRectangles) {
            neighborIndices[pair.first, default: []].append(pair.second)
            neighborIndices[pair.second, default: []].append(pair.first)
        }
        for i in entries.indices {
            let (idA, a) = entries[i]
            if pinned.contains(idA) { continue }
            var fx = crossNodeForces[idA]?.dx ?? 0
            var fy = crossNodeForces[idA]?.dy ?? 0
            if let target = layoutTargets[idA] {
                fx += (target.x - a.pos.x) * Self.anchorSpringK
                fy += (target.y - a.pos.y) * Self.anchorSpringK
            }
            if let breezeStartedAt {
                let progress = min(max((now - breezeStartedAt) / Self.breezeDuration, 0), 1)
                if progress < 1 {
                    // A single soft gust: the sine-squared envelope reaches zero at both
                    // ends, avoiding the abrupt force changes that read as jitter.
                    let envelope = CGFloat(pow(sin(.pi * progress), 2))
                    let phaseOffset = Double(idA.uuid.0) / 255 * 0.18
                    let localVariation = CGFloat(
                        0.88 + 0.12 * sin(progress * .pi + phaseOffset)
                    )
                    fx += breezeDirection.dx * Self.breezeForce * envelope * localVariation
                    fy += breezeDirection.dy * Self.breezeForce * envelope * localVariation
                }
            }
            for j in (neighborIndices[i] ?? []).sorted() {
                let (idB, b) = entries[j]
                var dx = a.pos.x - b.pos.x
                var dy = a.pos.y - b.pos.y
                var dist = hypot(dx, dy)
                if dist < 0.5 { dx = .random(in: -1...1); dy = .random(in: -1...1); dist = 1 }

                if let na = nodeByID[idA], let nb = nodeByID[idB] {
                    let minDist = simFootprintRadius(na) + simFootprintRadius(nb) + Self.overlapPadding
                    if dist < minDist {
                        let push = (minDist - dist) * 0.18
                        fx += (dx / dist) * push
                        fy += (dy / dist) * push
                    }
                }
            }
            // No idle jitter: once the short settling pass ends, nodes stay put.
            fx += CGFloat.random(in: -Self.jitterAmplitude...Self.jitterAmplitude) * CGFloat(alpha)
            fy += CGFloat.random(in: -Self.jitterAmplitude...Self.jitterAmplitude) * CGFloat(alpha)
            forces[idA] = CGVector(dx: fx, dy: fy)
        }

        // Chip-angle spread: Insight bonds and fixed Node lines repel with equal domain weight,
        // maximizing separation across every bond connected to the parent Node Concept.
        for (_, bonds) in bondsByNode where bonds.count > 1 {
            for ii in bonds.indices {
                guard case .insight(let id) = bonds[ii].kind else { continue }
                let bi = bonds[ii]
                var torque = 0.0
                for jj in bonds.indices where jj != ii {
                    var dθ = wrapAngle(bi.angle - bonds[jj].angle)
                    if abs(dθ) < 1e-4 { dθ = .random(in: -0.05...0.05) }
                    torque += Self.bondDomainK * (dθ >= 0 ? 1 : -1)
                        / (abs(dθ) + Self.chipAngleEps)

                    // Extra push once two Insight labels' angular gap is tighter than their real
                    // widths need at this orbit radius — the uniform spread above doesn't know
                    // either chip's width, so a long title can still settle too close to its
                    // neighbor even at "maximized" angular separation.
                    if case .insight(let otherID) = bonds[jj].kind,
                       let chipA = chipInfoByID[id], let chipB = chipInfoByID[otherID],
                       chipA.radius > 1 {
                        let requiredGap = atan2(
                            chipA.halfWidth + chipB.halfWidth + Self.chipWidthAngularPadding,
                            chipA.radius
                        )
                        let deficit = requiredGap - abs(dθ)
                        if deficit > 0 {
                            torque += Self.chipWidthRepulsionK * (dθ >= 0 ? 1 : -1) * Double(deficit)
                        }
                    }
                }
                chipTorque[id, default: 0] += torque
            }
        }
        // Cooling factor (simulated annealing). The angular repulsion never vanishes at
        // equilibrium, so leaving motion uncooled makes bonds oscillate around the ±π boundary —
        // visible as jitter that only stops when the frame budget expires. Scaling every frame's
        // displacement by `alpha` (which decays to 0) lets the layout converge and freeze smoothly.
        let cool = alpha
        let coolCG = CGFloat(alpha)

        if !chipTorque.isEmpty {
            var nextAngles = chipAngles
            for (id, torque) in chipTorque {
                // A pinned chip (deliberately dragged, or facing a Midpoint it's a source of)
                // still repels its siblings via the torque IT exerts on THEM above — only the
                // write-back of ITS OWN angle is skipped, so the spread simulation can't quietly
                // rotate a chosen angle back out from under it.
                guard !pinnedChipAngleIDs.contains(id), id != draggingChipID else { continue }
                guard var ch = nextAngles[id] else { continue }
                let rawStep = max(-Self.chipMaxAngStep, min(Self.chipMaxAngStep, torque * Self.chipAngGain * Double(dtScale)))
                let step = rawStep * cool
                ch.angle += step
                maxChipAngMotion = max(maxChipAngMotion, abs(step))
                nextAngles[id] = ch
            }
            chipAngles = nextAngles
        }

        // Elevation spread: each cluster's Insights alternate up and down the ±45° band around
        // their Node Concept. Angles ease toward those targets (cooled like the bond angles) so a
        // reordering glides instead of snapping. A drag only moves a chip around its node; its
        // height, like every sibling's, follows from the new order.
        if Self.depthCuesEnabled {
            var nextElevations = chipElevationAngles
            var membersByNode: [UUID: [InsightClusterSpatialLayout.Member]] = [:]
            for ci in chipInfos where ci.radius > 1 {
                membersByNode[ci.nodeID, default: []].append(
                    InsightClusterSpatialLayout.Member(id: ci.id, azimuth: ci.angle)
                )
            }
            for members in membersByNode.values {
                for (id, target) in InsightClusterSpatialLayout.elevationTargets(members) {
                    guard let current = nextElevations[id] else {
                        nextElevations[id] = target
                        continue
                    }
                    let step = (target - current) * Self.elevationEaseRate * CGFloat(dtScale) * coolCG
                    maxChipAngMotion = max(maxChipAngMotion, Double(abs(step)))
                    nextElevations[id] = current + step
                }
            }
            if nextElevations != chipElevationAngles { chipElevationAngles = nextElevations }
        }

        // Integrate (semi-implicit Euler; force scaled into velocity so spacing is effective).
        var next = bodies
        var maxMove: CGFloat = 0
        for (id, force) in forces {
            guard var body = next[id], !pinned.contains(id) else { continue }
            let vx = (body.vel.dx + force.dx * Self.forceGain * dtScale) * Self.simDamping
            let vy = (body.vel.dy + force.dy * Self.forceGain * dtScale) * Self.simDamping
            // Clamp the per-frame move (matches the view model's ±4 clamp), then cool it.
            let stepX = max(-Self.simMaxStep, min(Self.simMaxStep, vx * dtScale)) * coolCG
            let stepY = max(-Self.simMaxStep, min(Self.simMaxStep, vy * dtScale)) * coolCG
            body.pos.x += stepX
            body.pos.y += stepY
            body.vel = CGVector(dx: vx, dy: vy)
            next[id] = body
            maxMove = max(maxMove, hypot(stepX, stepY))
        }

        // Pinned bodies track their authoritative view-model position — with two exceptions:
        // a placed Midpoint being dragged directly (its own chip has no orbit, so the drag just
        // repositions it 1:1), and a placed Midpoint currently sourced by the chip being
        // rotate-dragged, which leans toward it by a fraction of how far that chip has moved from
        // where the drag started. Both read live off `draggingChipWorldPosition` (updated every
        // drag move, bypassing the chip's own pinned angle/radius — see `insightWorldPosition`).
        for id in pinned {
            if id == draggingChipID, let live = draggingChipWorldPosition {
                next[id]?.pos = live
                continue
            }
            if placedMidpointNodeIDs.contains(id),
               let draggingChipID, let live = draggingChipWorldPosition,
               let start = draggingChipStartWorldPosition,
               let sources = placedMidpointSources[id],
               sources.contains(where: { !$0.isNode && $0.insightID == draggingChipID }) {
                let followFactor: CGFloat = 0.35
                let base = nodeByID[id]?.position ?? next[id]?.pos ?? .zero
                next[id]?.pos = CGPoint(
                    x: base.x + (live.x - start.x) * followFactor,
                    y: base.y + (live.y - start.y) * followFactor
                )
                continue
            }
            if let node = nodeByID[id] { next[id]?.pos = node.position }
        }

        alpha = max(Self.alphaFloor, alpha * (1 - simAlphaDecay))
        simFramesRemaining -= 1
        // Settle once the actual (cooled) per-frame motion is negligible — both node displacement
        // and chip-angle rotation. Because displacement is cooled by `alpha`, this is reached
        // smoothly instead of being cut off by the frame budget mid-jitter.
        let settled = maxMove <= Self.settleVelocityThreshold && maxChipAngMotion <= 0.002
        if simFramesRemaining <= 0 || (alpha <= 0.01 && settled) {
            freezeSimulation(next)
        } else {
            bodies = next
        }
    }

    /// The node id owning the currently focused/hovered target, if any.
    private func focusedNodeID() -> UUID? {
        if let nodeID = pulsingNodeID { return nodeID }
        if let insightID = focusedInsightID ?? pulsingInsightID {
            return nodes.first(where: { $0.insights.contains { $0.id == insightID } })?.id
        }
        return nil
    }

    /// Report live positions up for persistence.
    func persistLivePositions() {
        guard !bodies.isEmpty else { return }
        onPositionsSettled(bodies.mapValues(\.pos))
    }

}
