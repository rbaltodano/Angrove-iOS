import Foundation
import Testing
import SwiftUI
import UIKit
@testable import Angrove_iOS

@Suite("Complete Library editions")
struct BundledLibraryReaderTests {
    @MainActor
    @Test("Complete edition reader renders on a small phone in both appearances")
    func readerLayout() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 780)
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "CompleteLibraryLayouts")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { window.isHidden = true; window.rootViewController = nil }
        for scheme in [ColorScheme.light, .dark] {
            let reader = LibraryView(
                onOpenMenu: {}, modelTasks: ModelTaskQueue(),
                modelTasksPopupState: ModelTasksPopupState(), onReaderVisibilityChange: { _ in },
                navigationRequest: LibraryNavigationRequest(
                    sourceTitle: "Ecclesiastical History", sourceName: "Ecclesiastical History",
                    sourceID: "eusebius-ecclesiastical-history"
                )
            )
            .environment(\.colorScheme, scheme)
            window.overrideUserInterfaceStyle = scheme == .light ? .light : .dark
            window.rootViewController = UIHostingController(rootView: reader)
            window.makeKeyAndVisible()
            try await Task.sleep(for: .seconds(2))
            window.layoutIfNeeded()
            var didRender = false
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                didRender = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            #expect(didRender)
            let bytes = try #require(image.pngData())
            try bytes.write(to: directory.appending(path: scheme == .light ? "reader-light.png" : "reader-dark.png"))
        }
    }

    @Test("Every catalog work has a complete reader edition with no uncovered paragraphs")
    func completeCatalog() throws {
        let corpus = try #require(BundledPassageCorpus.bundled())
        #expect(corpus.indicesBySource.count == 37)
        for sourceID in corpus.indicesBySource.keys.sorted() {
            let edition = try #require(BundledLibraryReader.document(sourceID: sourceID))
            let paragraphs = try #require(edition.loadPassages())
            #expect(!paragraphs.isEmpty)
            #expect(paragraphs.allSatisfy { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        }
    }

    @Test("Previously partial editions include their final books and chapters")
    func restoredWorks() throws {
        let westminster = try #require(BundledLibraryReader.document(sourceID: "westminster-confession"))
        #expect(westminster.sections.contains { $0.title.hasPrefix("Chap. xxxiii.") })
        let eusebius = try #require(BundledLibraryReader.document(sourceID: "eusebius-ecclesiastical-history"))
        #expect(eusebius.sections.filter { $0.title.hasPrefix("Book ") }.count == 10)
        let gibbon = try #require(BundledLibraryReader.document(sourceID: "gibbon-decline-and-fall"))
        #expect(gibbon.sections.map(\.title) == (1...6).map { "Volume \($0)" })
        let paragraphs = try #require(gibbon.loadPassages())
        #expect(paragraphs.contains { $0.text.contains("Chapter LXXI:") })
        #expect(paragraphs.reduce(0) { $0 + $1.text.count } > 8_000_000)
        let tacitus = try #require(BundledLibraryReader.document(sourceID: "tacitus-annals-histories"))
        #expect(tacitus.sections.contains { $0.title == "Histories: BOOK V" })
        let constitution = try #require(BundledLibraryReader.document(sourceID: "us-constitution"))
        #expect(constitution.sections.contains { $0.title == "AMENDMENT XXVII" })
    }

    @Test("Books are in reading order and Bible chapter links retain their location")
    func readingOrderAndCitations() throws {
        let metaphysics = try #require(BundledLibraryReader.document(sourceID: "aristotle-metaphysics"))
        #expect(metaphysics.sections.map(\.title) == (1...14).map { "Book \($0)" })
        let bible = try #require(BundledLibraryReader.document(sourceID: "web-bible"))
        #expect(bible.sections.first?.title == "Genesis")
        let john = try #require(bible.sections.first { $0.title == "John" })
        #expect(john.children.map(\.title) == (1...21).map { "Chapter \($0)" })
        let corpus = try #require(BundledPassageCorpus.bundled())
        let original = try #require(corpus.passages(forSource: "web-bible").first { $0.text.hasPrefix("[JHN14]") })
        let location = try #require(bible.readerIndex(forRetrievalChunk: original.chunkIndex))
        let chapter = try #require(john.children.first { $0.title == "Chapter 14" })
        #expect((chapter.lowerBound...chapter.upperBound).contains(location))
        #expect(LibraryPassageLocator.label(sourceID: "web-bible", chunkIndex: original.chunkIndex) == "John 14")
    }
}
