import SwiftUI
import Testing
import UIKit
@testable import Angrove_iOS

@Suite("Citation wrapping layout", .serialized)
@MainActor
struct ResponseCitationLayoutTests {
    private let title = "Summa Theologica, Treatise On The Work Of The Six Days, Question 83, Article 1"

    private final class Measurements {
        var frames: [String: CGRect] = [:]
    }

    private struct ResponseSample: View {
        let link: ParsedInsightLink
        let alignment: TextAlignment
        let measurements: Measurements
        private let font = Font.custom("LibreBaskerville-Regular", size: 16)

        var body: some View {
            FlowLayout(alignment: alignment) {
                Text("Before")
                    .font(font)
                ResponseCitationChip(link: link, textFont: font)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named("response"))
                    } action: { measurements.frames["citation"] = $0 }
                Text("After")
                    .font(font)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named("response"))
                    } action: { measurements.frames["after"] = $0 }
                Text("End")
                    .font(font)
            }
            .frame(maxWidth: .infinity)
            .coordinateSpace(name: "response")
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private struct JustifiedSample: View {
        let measurements: Measurements
        let justified: Bool

        var body: some View {
            FlowLayout(alignment: .center, justified: justified) {
                ForEach(0..<3) { index in
                    Color.clear
                        .frame(width: 60, height: 20)
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: .named("justified"))
                        } action: { measurements.frames[String(index)] = $0 }
                }
            }
            .coordinateSpace(name: "justified")
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    @Test("Justified paragraphs stretch wrapped rows and leave the last row left aligned",
          arguments: [true, false])
    func justifiedLastLine(justified: Bool) async throws {
        let measurements = Measurements()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 160, height: 300))
        let controller = UIHostingController(rootView: JustifiedSample(measurements: measurements, justified: justified))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))

        let first = try #require(measurements.frames["0"])
        let second = try #require(measurements.frames["1"])
        let last = try #require(measurements.frames["2"])
        if justified {
            #expect(abs(first.minX) < 1)
            #expect(abs(second.maxX - 160) < 1)
            #expect(abs(last.minX) < 1)
        } else {
            #expect(first.minX > 0)
            #expect(abs(last.midX - 80) < 1)
        }
        #expect(last.minY >= first.maxY + FlowLayout.rowSpacing - 1)
    }

    @Test("Long citation chips wrap without overflow or overlap", arguments: [TextAlignment.leading, .center])
    func longCitationWraps(alignment: TextAlignment) async throws {
        let link = try #require(ParsedInsightLink(token: "[\(title)](aq-cite://summa-theologica/4200)."))
        let measurements = Measurements()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 240, height: 800))
        let controller = UIHostingController(rootView: ResponseSample(link: link, alignment: alignment, measurements: measurements))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))

        let citation = try #require(measurements.frames["citation"])
        let after = try #require(measurements.frames["after"])
        #expect(citation.minX >= -1)
        #expect(citation.maxX <= 241)
        #expect(citation.height > 40)
        #expect(after.minY >= citation.maxY + FlowLayout.rowSpacing - 1)
    }

    @Test("Cached citations rewrap when the response becomes narrower")
    func responseResize() async throws {
        let link = try #require(ParsedInsightLink(token: "[\(title)](aq-cite://summa-theologica/4200)."))
        let measurements = Measurements()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 340, height: 800))
        let controller = UIHostingController(rootView: ResponseSample(link: link, alignment: .leading, measurements: measurements))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        let wide = try #require(measurements.frames["citation"])

        window.frame.size.width = 180
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        let narrow = try #require(measurements.frames["citation"])
        #expect(narrow.maxX <= 181)
        #expect(narrow.height > wide.height)
        let after = try #require(measurements.frames["after"])
        #expect(after.minY >= narrow.maxY + FlowLayout.rowSpacing - 1)
    }
}
