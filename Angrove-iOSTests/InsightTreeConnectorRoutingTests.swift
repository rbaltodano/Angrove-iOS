import CoreGraphics
import Foundation
import Testing
@testable import Angrove_iOS

@Suite("Insight Tree connector routing")
struct InsightTreeConnectorRoutingTests {
    private func edge(_ id: String, _ a: CGPoint, _ b: CGPoint, from: UUID = UUID(), to: UUID = UUID()) -> InsightTreeConnectorRouting.Connector {
        .init(id: id, start: a, end: b, fromNodeID: from, toNodeID: to)
    }

    @Test("Clear connectors remain straight and preserve their semantic endpoints")
    func clearRoute() {
        let connector = edge("a", .zero, CGPoint(x: 400, y: 0))
        let routes = InsightTreeConnectorRouting.routes(connectors: [connector], obstacles: [])
        #expect(routes.first?.bend == 0)
        #expect(routes.first?.point(at: 0) == connector.start)
        #expect(routes.first?.point(at: 1) == connector.end)
        #expect(routes.first?.gaps.isEmpty == true)
    }

    @Test("An unrelated label bends the connector around its footprint")
    func avoidsLabels() throws {
        let connector = edge("a", .zero, CGPoint(x: 400, y: 0))
        let obstacle = InsightTreeConnectorRouting.Obstacle(ownerID: UUID(), rect: CGRect(x: 170, y: -20, width: 60, height: 40))
        let route = try #require(InsightTreeConnectorRouting.routes(connectors: [connector], obstacles: [obstacle]).first)
        #expect(route.bend != 0)
        let samples = route.samples
        #expect(!(0..<route.segmentCount).contains { InsightTreeConnectorRouting.segmentIntersectsRect(samples[$0], samples[$0 + 1], obstacle.rect) })
        #expect(route.connector == connector)
    }

    @Test("Own-group labels cannot divert their parent's connector")
    func ownLabels() {
        let connector = edge("a", .zero, CGPoint(x: 400, y: 0))
        let obstacle = InsightTreeConnectorRouting.Obstacle(ownerID: connector.fromNodeID, rect: CGRect(x: 170, y: -20, width: 60, height: 40))
        #expect(InsightTreeConnectorRouting.routes(connectors: [connector], obstacles: [obstacle]).first?.bend == 0)
    }

    @Test("Crossings get one gap; actual shared endpoints stay joined")
    func crossings() throws {
        let a = edge("a", CGPoint(x: -100, y: 0), CGPoint(x: 100, y: 0))
        let b = edge("b", CGPoint(x: 0, y: -100), CGPoint(x: 0, y: 100))
        let routes = InsightTreeConnectorRouting.routes(connectors: [b, a], obstacles: [])
        #expect(routes[0].gaps.isEmpty)
        #expect(routes[1].gaps.count == 1)
        #expect(routes[1].gaps[0].contains(0.5))
        let shared = UUID()
        let connected = [edge("a", .zero, CGPoint(x: 100, y: 0), from: shared),
                         edge("b", .zero, CGPoint(x: 0, y: 100), from: shared)]
        #expect(InsightTreeConnectorRouting.routes(connectors: connected, obstacles: []).allSatisfy { $0.gaps.isEmpty })
    }

    @Test("Routing is stable across input order and reveal clips exact gap intervals")
    func stableAndReveal() {
        let a = edge("a", CGPoint(x: -100, y: 0), CGPoint(x: 100, y: 0))
        let b = edge("b", CGPoint(x: 0, y: -100), CGPoint(x: 0, y: 100))
        #expect(InsightTreeConnectorRouting.routes(connectors: [a, b], obstacles: []) == InsightTreeConnectorRouting.routes(connectors: [b, a], obstacles: []))
        #expect(InsightTreeConnectorRouting.visibleRanges(gaps: [0.4...0.6], drawn: 1) == [0...0.4, 0.6...1])
        #expect(InsightTreeConnectorRouting.visibleRanges(gaps: [0.4...0.6], drawn: 0.5) == [0...0.4])
    }
}
