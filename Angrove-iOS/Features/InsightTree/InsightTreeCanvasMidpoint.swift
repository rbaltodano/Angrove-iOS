import SwiftUI
import UIKit
import simd

// Midpoint behavior for the shared global and conversation canvas.
extension InsightTreeCanvasView {
    // MARK: - Midpoint Mode

    static let canvasSpace = "treeCanvas"

    /// Installs the three stable loading children, frames their promoted Node Concept, and splays
    /// them into place. Their text remains hidden until the model publishes all three as ready.
    func beginMakeNodeLoading(
        _ children: [(id: UUID, orbitIndex: Int)],
        in newNodes: [NodeModel],
        size: CGSize
    ) {
        if studyBranchSource != nil {
            revealState.revealedInsightIDs.formUnion(children.map(\.id))
            return
        }
        guard revealState.pendingMakeNodeChildren.isEmpty else { return }
        let pending = children
            .sorted { $0.orbitIndex < $1.orbitIndex }
            .map {
                InsightTreeRevealState.PendingMakeNodeChild(id: $0.id, orbitIndex: $0.orbitIndex)
            }
        revealState.pendingMakeNodeChildren = pending
        revealState.makeNodeLoadingStartedAt = Date().timeIntervalSinceReferenceDate

        for child in pending {
            revealState.loadingInsightIDs.insert(child.id)
            revealState.unsplayedInsightIDs.insert(child.id)
        }
        onGeneratingChange(true)
        markUndiscovered(pending.map(\.id))

        // Frame the promoted Node Concept and all three loading children before touring them.
        onRequestDismissHover()
        let generatedNodeIDs = Set(pending.compactMap { child in
            newNodes.first(where: {
                $0.insights.contains { $0.id == child.id }
            })?.id
        })
        let generatedNodePositions = generatedNodeIDs.compactMap { simPosition(of: $0) }
        let framePositions = generatedNodePositions
            + pending.compactMap { worldPosition(forInsightID: $0.id) }
        if !framePositions.isEmpty {
            zoomToFit(
                worldPositions: framePositions,
                in: size,
                padding: 90,
                fitFactor: 1.0,
                center: generatedNodePositions.count == 1
                    ? generatedNodePositions.first
                    : nil
            )
        }

        for child in pending {
            let delay = Double(child.orbitIndex) * 0.15
            Task {
                try? await Task.sleep(for: .seconds(delay))
                await MainActor.run {
                    withAnimation(.springBouncy) {
                        _ = revealState.unsplayedInsightIDs.remove(child.id)
                    }
                }
            }
        }

        // Covers the fast-response race where generation and the node rebuild arrive in one
        // SwiftUI update; the readiness onChange path covers the normal slower response.
        scheduleMakeNodeRevealIfReady(in: size)
    }

    /// Starts the existing three-stop camera tour only when all child titles and definitions have
    /// replaced their loading content. The former 3.5-second simulated dwell remains a minimum.
    func scheduleMakeNodeRevealIfReady(in size: CGSize) {
        guard !revealState.pendingMakeNodeChildren.isEmpty, revealState.makeNodeRevealTask == nil else { return }
        let childIDs = Set(revealState.pendingMakeNodeChildren.map(\.id))
        guard childIDs.isSubset(of: generatedMakeNodeChildIDs) else { return }

        let children = revealState.pendingMakeNodeChildren
        let startedAt = revealState.makeNodeLoadingStartedAt
            ?? Date().timeIntervalSinceReferenceDate
        let elapsed = Date().timeIntervalSinceReferenceDate - startedAt
        let remainingDelay = max(3.5 - elapsed, 0)

        revealState.makeNodeRevealTask = Task {
            try? await Task.sleep(for: .seconds(remainingDelay))
            guard !Task.isCancelled else { return }
            for (index, child) in children.enumerated() {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if let position = worldPosition(forInsightID: child.id) {
                        // The first stop restores the default zoom while panning; later stops
                        // retain it, matching the existing Make Node choreography.
                        focusInsight(
                            at: position,
                            in: size,
                            targetScale: index == 0 ? 1 : nil
                        )
                    }
                }
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if let position = worldPosition(forInsightID: child.id) {
                        rippleTrigger = RippleTrigger(
                            worldOrigin: position,
                            startTime: Date().timeIntervalSinceReferenceDate,
                            strength: 2.8,
                            radiusScale: 0.5
                        )
                    }
                    playGeneratedHaptics()
                    onMakeNodeChildRevealed(child.id)
                    withAnimation(.easeOut(duration: 0.32)) {
                        revealState.loadingInsightIDs.remove(child.id)
                        revealState.revealedInsightIDs.insert(child.id)
                    }
                }
                try? await Task.sleep(for: .milliseconds(700))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                revealState.pendingMakeNodeChildren = []
                revealState.makeNodeLoadingStartedAt = nil
                revealState.makeNodeRevealTask = nil
                onGeneratingChange(false)
            }
        }
    }

    /// Starts the existing loading presentation as soon as the placed identity enters the tree.
    /// Generation completion is signaled separately, so a slow model never reveals blank text.
    func beginMidpointLoading(_ insightID: UUID, in size: CGSize) {
        guard revealState.midpointLoadingStartedAt[insightID] == nil else { return }
        revealState.midpointLoadingStartedAt[insightID] = Date().timeIntervalSinceReferenceDate
        revealState.loadingInsightIDs.insert(insightID)
        cameraState.userMovedSincePlacement = false
        markUndiscovered([insightID])
        if let position = worldPosition(forInsightID: insightID) {
            focusHoveredTarget(at: position, in: size)
        }
    }

    /// Preserves the existing 3.5-second minimum loading animation but waits longer when real
    /// generation takes longer. The generated title and definition are already in `nodes`.
    func scheduleMidpointReveal(_ insightID: UUID, in size: CGSize) {
        beginMidpointLoading(insightID, in: size)
        let startedAt = revealState.midpointLoadingStartedAt[insightID]
            ?? Date().timeIntervalSinceReferenceDate
        let elapsed = Date().timeIntervalSinceReferenceDate - startedAt
        let remainingDelay = max(3.5 - elapsed, 0)

        revealState.midpointRevealTask?.cancel()
        revealState.midpointRevealTask = Task {
            try? await Task.sleep(for: .seconds(remainingDelay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if let position = worldPosition(forInsightID: insightID) {
                    if !cameraState.userMovedSincePlacement {
                        focusHoveredTarget(at: position, in: size)
                    }
                    rippleTrigger = RippleTrigger(
                        worldOrigin: position,
                        startTime: Date().timeIntervalSinceReferenceDate,
                        strength: 2.8,
                        radiusScale: 0.5
                    )
                    playGeneratedHaptics()
                }
                withAnimation(.easeOut(duration: 0.32)) {
                    revealState.loadingInsightIDs.remove(insightID)
                    revealState.revealedInsightIDs.insert(insightID)
                }
                revealState.midpointLoadingStartedAt[insightID] = nil
            }
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            await MainActor.run { onMidpointInsightLoaded(insightID) }
        }
    }

    func selectedWorldPositions() -> [CGPoint] {
        selectedCanvasTargets.compactMap { worldPosition(for: $0) }
    }

    func reportMidpointWeights() {
        guard let handle = effectiveMidpointHandle() else { return }
        onMidpointWeightsChange(midpointWeights(for: handle))
    }

    func centeredMidpointHandle() -> CGPoint? {
        midpointCenter().map(constrainHandle)
    }

    func effectiveMidpointHandle() -> CGPoint? {
        midpointHandleWorld.map(constrainHandle)
    }

    /// Moves the handle so that the given selected insight has the target weight.
    /// Two insights: lerp along the A→B segment. Three+: search along the centroid→vertex
    /// ray (the other weights redistribute automatically as the handle recomputes).
    func applyMidpointTarget(index: Int, weight target: Double) {
        let positions = selectedWorldPositions()
        guard index >= 0, index < positions.count else { return }
        let t = min(max(target, 0), 1)
        let newHandle: CGPoint

        if positions.count == 2 {
            let a = positions[0], b = positions[1]
            // weight[0] = 1 - frac, weight[1] = frac
            let frac = CGFloat(index == 0 ? (1 - t) : t)
            newHandle = CGPoint(x: a.x + (b.x - a.x) * frac, y: a.y + (b.y - a.y) * frac)
        } else if let center = midpointCenter() {
            let v = positions[index]
            // weight[index] increases monotonically with s along center→vertex.
            var lo: CGFloat = -1.2, hi: CGFloat = 1.0
            for _ in 0..<26 {
                let mid = (lo + hi) / 2
                let h = CGPoint(x: center.x + (v.x - center.x) * mid, y: center.y + (v.y - center.y) * mid)
                if midpointWeights(for: h)[index] < t { lo = mid } else { hi = mid }
            }
            let s = (lo + hi) / 2
            newHandle = CGPoint(x: center.x + (v.x - center.x) * s, y: center.y + (v.y - center.y) * s)
        } else {
            return
        }

        withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.9)) {
            midpointHandleWorld = constrainHandle(newHandle)
        }
        reportMidpointWeights()
    }

    /// Geometric center of the selection (exact midpoint for two, centroid for 3+).
    private func midpointCenter() -> CGPoint? {
        let positions = selectedWorldPositions()
        guard !positions.isEmpty else { return nil }
        let sum = positions.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(positions.count), y: sum.y / CGFloat(positions.count))
    }

    /// The selected target whose world position is closest to a point.
    func nearestSelectedTarget(to point: CGPoint) -> CanvasSelectionTarget? {
        selectedCanvasTargets.min { a, b in
            let pa = worldPosition(for: a) ?? .zero
            let pb = worldPosition(for: b) ?? .zero
            return hypot(pa.x - point.x, pa.y - point.y) < hypot(pb.x - point.x, pb.y - point.y)
        }
    }

    /// Blend weights for each selected target given the handle position.
    /// Two targets interpolate along their segment. For larger selections, the geometric
    /// centroid is defined as the exact equal-weight position; moving away from it uses
    /// normalized inverse-distance weights.
    func midpointWeights(for handle: CGPoint) -> [Double] {
        let positions = selectedWorldPositions()
        guard positions.count >= 2 else { return positions.map { _ in 1.0 } }

        if positions.count == 2 {
            let a = positions[0], b = positions[1]
            let abx = b.x - a.x, aby = b.y - a.y
            let denom = abx * abx + aby * aby
            let t = denom > 0 ? insightTreeCanvasClamp(((handle.x - a.x) * abx + (handle.y - a.y) * aby) / denom, lower: 0, upper: 1) : 0.5
            return [Double(1 - t), Double(t)]
        }

        let center = positions.reduce(CGPoint.zero) {
            CGPoint(x: $0.x + $1.x, y: $0.y + $1.y)
        }
        let centroid = CGPoint(
            x: center.x / CGFloat(positions.count),
            y: center.y / CGFloat(positions.count)
        )
        let selectionScale = positions.reduce(CGFloat.zero) {
            max($0, hypot($1.x - centroid.x, $1.y - centroid.y))
        }
        let centerTolerance = max(selectionScale * 0.000_001, 0.000_1)
        if hypot(handle.x - centroid.x, handle.y - centroid.y) <= centerTolerance {
            return positions.map { _ in 1.0 / Double(positions.count) }
        }

        let epsilon: CGFloat = 0.0001
        let inverse = positions.map { 1.0 / Double(max(hypot($0.x - handle.x, $0.y - handle.y), epsilon)) }
        let total = inverse.reduce(0, +)
        return total > 0 ? inverse.map { $0 / total } : positions.map { _ in 1.0 / Double(positions.count) }
    }

    /// Clamps a handle position to the valid region: the segment (two targets)
    /// or the selection polygon (3+ targets).
    func constrainHandle(_ point: CGPoint) -> CGPoint {
        let positions = selectedWorldPositions()
        if positions.count == 2 {
            return closestPointOnSegment(point, positions[0], positions[1])
        }
        if positions.count >= 3 {
            let boundary = convexHull(of: positions)
            if boundary.count == 2 {
                return closestPointOnSegment(point, boundary[0], boundary[1])
            }
            return pointInPolygon(point, boundary) ? point : closestPointOnPolygon(point, boundary)
        }
        return point
    }

    /// Returns the selection's convex boundary in winding order. Selection order reflects tap
    /// order, so using it directly can create a self-intersecting polygon that incorrectly
    /// pushes the true centroid outside the draggable region.
    func convexHull(of points: [CGPoint]) -> [CGPoint] {
        let sorted = points
            .sorted { lhs, rhs in
                lhs.x == rhs.x ? lhs.y < rhs.y : lhs.x < rhs.x
            }
            .reduce(into: [CGPoint]()) { unique, point in
                if unique.last != point { unique.append(point) }
            }
        guard sorted.count > 2 else { return sorted }

        func cross(_ origin: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - origin.x) * (b.y - origin.y)
                - (a.y - origin.y) * (b.x - origin.x)
        }

        var lower: [CGPoint] = []
        for point in sorted {
            while lower.count >= 2,
                  cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 {
                lower.removeLast()
            }
            lower.append(point)
        }

        var upper: [CGPoint] = []
        for point in sorted.reversed() {
            while upper.count >= 2,
                  cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 {
                upper.removeLast()
            }
            upper.append(point)
        }

        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }

    private func closestPointOnSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGPoint {
        let abx = b.x - a.x, aby = b.y - a.y
        let denom = abx * abx + aby * aby
        guard denom > 0 else { return a }
        let t = insightTreeCanvasClamp(((p.x - a.x) * abx + (p.y - a.y) * aby) / denom, lower: 0, upper: 1)
        return CGPoint(x: a.x + abx * t, y: a.y + aby * t)
    }

    private func pointInPolygon(_ p: CGPoint, _ poly: [CGPoint]) -> Bool {
        guard poly.count >= 3 else { return false }
        var inside = false
        var j = poly.count - 1
        for i in poly.indices {
            let pi = poly[i], pj = poly[j]
            if (pi.y > p.y) != (pj.y > p.y),
               p.x < (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y) + pi.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    private func closestPointOnPolygon(_ p: CGPoint, _ poly: [CGPoint]) -> CGPoint {
        guard poly.count >= 2 else { return p }
        var best = poly[0]
        var bestDist = CGFloat.greatestFiniteMagnitude
        for i in poly.indices {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            let candidate = closestPointOnSegment(p, a, b)
            let dist = hypot(candidate.x - p.x, candidate.y - p.y)
            if dist < bestDist {
                bestDist = dist
                best = candidate
            }
        }
        return best
    }

    /// Points every source of a placed Midpoint at that Midpoint's own node, except `excluding`
    /// (the chip the user just deliberately dragged, whose angle is authoritative). Two connected
    /// chips facing each other is what keeps their line from cutting across an unrelated one —
    /// e.g. the line between their own two parent Nodes.
    func reangleMidpointSources(of midpointID: UUID, excluding: UUID? = nil) {
        guard let midpointNode = nodes.first(where: { $0.id == midpointID }),
              let sources = placedMidpointSources[midpointID] else { return }
        for source in sources where !source.isNode && source.insightID != excluding {
            guard let parent = parentNode(ofInsightID: source.insightID) else { continue }
            let angle = Double(atan2(
                midpointNode.position.y - parent.position.y,
                midpointNode.position.x - parent.position.x
            ))
            chipAngles[source.insightID] = ChipAngle(angle: angle)
            pinnedChipAngleIDs.insert(source.insightID)
        }
    }

    /// Every placed Midpoint that `insightID` is itself a source of.
    func midpointIDs(sourcedBy insightID: UUID) -> [UUID] {
        placedMidpointSources.compactMap { midpointID, sources in
            sources.contains { !$0.isNode && $0.insightID == insightID } ? midpointID : nil
        }
    }

}
