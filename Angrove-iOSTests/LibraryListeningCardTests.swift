import ImageIO
import SwiftUI
import Testing
import UIKit
@testable import Angrove_iOS

@Suite("Library illustrated listening card", .serialized)
@MainActor
struct LibraryListeningCardTests {
    @Test("Every subject displays the exact original image")
    func bundledArtwork() throws {
        for artwork in LibraryArtwork.allCases {
            let url = try #require(artwork.resource("final"))
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            let original = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let rendered = try #require(LibraryPaintedArtwork(artwork: artwork).image)
            #expect(rendered.pngData() == UIImage(cgImage: original).pngData())
        }
        #expect(LibraryArtwork.forWork("aristotle-nicomachean-ethics") == .philosophy)
        #expect(LibrarySubject.allCases.count == 7)
        #expect(LibrarySubject.of(workID: "summa-theologica") == .earlyChristianity)
        #expect(LibraryArtwork.forWork("summa-theologica") == .church)
        #expect(LibraryArtwork.forWork("web-bible") == .scripture)
        #expect(LibraryArtwork.forWork("us-constitution") == .political)
        #expect(LibraryWorkAttribution.author(workID: "aristotle-nicomachean-ethics") == "Aristotle")
    }

    @Test("Light and dark artwork cards fit reference and small-phone widths",
          arguments: [272, 318], [UIUserInterfaceStyle.light, .dark])
    func layout(width: Int, style: UIUserInterfaceStyle) async throws {
        try await snapshotCard(width: width, style: style, listening: false)
        try await snapshotCard(width: width, style: style, listening: true)
    }

    private func snapshotCard(width: Int, style: UIUserInterfaceStyle, listening: Bool) async throws {
        let work = LibraryWork(id: "aristotle-nicomachean-ethics", title: "Nicomachean Ethics", passageCount: 1)
        let card = ScrollView { LibraryListeningCard(work: work,
            playback: .init(isListening: listening, progress: listening ? 0.63 : 0.24), action: {}) }
            .environment(\.colorScheme, style == .dark ? .dark : .light)
            .environment(\.scenePhase, .active)
            .frame(width: CGFloat(width))
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 300)
        window.overrideUserInterfaceStyle = style
        let controller = UIHostingController(rootView: card)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.view.frame = window.bounds
        try await Task.sleep(for: .milliseconds(800))
        controller.view.layoutIfNeeded()
        let fitting = controller.sizeThatFits(in: CGSize(width: width, height: 1000))
        #expect(fitting.width <= CGFloat(width) + 1)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let snapshot = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let appearance = style == .dark ? "dark" : "light"
        let state = listening ? "playing" : "paused"
        let path = "/tmp/angrove-library-card-\(width)-\(appearance)-\(state).png"
        let data = try #require(snapshot.pngData())
        try data.write(to: URL(fileURLWithPath: path))
        Attachment.record(data, named: "angrove-library-card-\(width)-\(appearance)-\(state).png")
        print("Library listening card snapshot: \(path)")
    }

    @Test("Original artwork blurs in once and stays revealed after scrolling away")
    func originalEntranceOnce() async throws {
        var scrollProxy: ScrollViewProxy?
        let artwork = ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    LibraryPaintedArtwork(artwork: .philosophy)
                        .frame(height: 250)
                        .id("art")
                    Color.clear.frame(height: 800).id("bottom")
                }
            }
            .onAppear { scrollProxy = proxy }
        }
        .background(AngroveTheme.Colors.canvas)
        .ignoresSafeArea()
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 318, height: 250)
        let controller = UIHostingController(rootView: artwork)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        defer { window.isHidden = true; window.rootViewController = nil }
        func snapshot() throws -> Data {
            controller.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return try #require(UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }.pngData())
        }
        try await Task.sleep(for: .milliseconds(100))
        let entrance = try snapshot()
        try await Task.sleep(for: .milliseconds(800))
        let original = try snapshot()
        if !UIAccessibility.isReduceMotionEnabled { #expect(entrance != original) }
        try await Task.sleep(for: .milliseconds(700))
        #expect(try snapshot() == original)
        let proxy = try #require(scrollProxy)
        proxy.scrollTo("bottom", anchor: .top)
        try await Task.sleep(for: .milliseconds(150))
        #expect(try snapshot() != original)
        proxy.scrollTo("art", anchor: .top)
        try await Task.sleep(for: .milliseconds(100))
        #expect(try snapshot() == original)
        Attachment.record(original, named: "original-artwork-after-blur.png")

    }

    @Test("Home places the shared listening card beneath the calendar")
    func homeListeningCard() async throws {
        let work = LibraryWork(id: "aristotle-nicomachean-ethics", title: "Nicomachean Ethics", passageCount: 1)
        let opening = ScrollView { HomeFigmaOpeningSection(
            greeting: "Good evening", userName: "Ryan",
            month: MonthlyUsageMonth(title: "October", totalVisits: 0,
                                     days: (1...31).map { MonthlyUsageDay(id: "\($0)", dayNumber: $0, count: 0) }),
            conversationCount: 0, insightCount: 0, studyTopicCount: 0, unfinishedCount: 0,
            questionOfTheDay: nil, usesLandscapeLayout: false, hidesGreetingHeader: true,
            onStartQuestion: { _ in }, listeningWork: work
        ) }
        .padding(24)
        .frame(width: 402, height: 700, alignment: .top)
        .background(AngroveTheme.Colors.canvas)
        .environment(\.scenePhase, .active)
        .environment(\.colorScheme, .light)
        .ignoresSafeArea()
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 700)
        let controller = UIHostingController(rootView: opening)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(800))
        controller.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let snapshot = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        Attachment.record(try #require(snapshot.pngData()), named: "home-calendar-listening-card.png")
    }

}
