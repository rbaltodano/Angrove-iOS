import Foundation
import Testing
@testable import Aquinas_iOS

@Suite("Home recommended reading")
struct RecommendedReadingTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func freshDefaults() -> UserDefaults {
        let name = "RecommendedReadingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func source(_ work: String, id: String = UUID().uuidString) -> GroundingSourceSummary {
        GroundingSourceSummary(id: id, title: work, sourceName: work, passage: "")
    }

    @Test("Passages from one work count toward that work once")
    func groupsPassagesByWork() {
        let works = RecommendedReading.rankedWorks(from: [
            source("Summa Theologica", id: "corpus-1-0"),
            source("Summa Theologica", id: "corpus-2-1"),
            source("Summa Theologica", id: "corpus-3-2"),
            source("Confessions")
        ])
        #expect(works.map(\.title) == ["Summa Theologica", "Confessions"])
        #expect(works.first?.reason == "Referenced 3 times across your conversations.")
    }

    @Test("Scripture chapters reduce to their work; curated facts the Library can't open are skipped")
    func normalizesWorkTitles() {
        let works = RecommendedReading.rankedWorks(from: [
            source("John 14 — World English Bible"),
            source("Matthew 5 — World English Bible"),
            GroundingSourceSummary(id: "a", title: "Nicaea", sourceName: "Catechism of the Catholic Church §242", passage: ""),
            GroundingSourceSummary(id: "c", title: "Note", sourceName: "Aquinas curated reference note", passage: "")
        ])
        #expect(works.map(\.title) == ["World English Bible"])
    }

    @Test("The section stays hidden until three distinct works have been retrieved")
    func hiddenUntilThreeWorks() {
        let defaults = freshDefaults()
        let two = [source("Summa Theologica"), source("Summa Theologica"), source("Confessions")]
        #expect(RecommendedReading.works(from: two, now: now, defaults: defaults).isEmpty)

        let three = two + [source("On the Incarnation")]
        #expect(RecommendedReading.works(from: three, now: now, defaults: defaults).count == 3)
    }

    @Test("Picks hold for the refresh interval, then re-rank to the most-pulled works")
    func snapshotRefreshesEveryFewDays() {
        let defaults = freshDefaults()
        let initial = ["A", "B", "C"].map { source($0) }
        #expect(RecommendedReading.works(from: initial, now: now, defaults: defaults).map(\.title) == ["A", "B", "C"])

        let later = initial + Array(repeating: source("D"), count: 4)
        let soon = now.addingTimeInterval(RecommendedReading.refreshInterval - 60)
        #expect(RecommendedReading.works(from: later, now: soon, defaults: defaults).map(\.title) == ["A", "B", "C"])

        let after = now.addingTimeInterval(RecommendedReading.refreshInterval + 60)
        #expect(RecommendedReading.works(from: later, now: after, defaults: defaults).first?.title == "D")
    }
}
