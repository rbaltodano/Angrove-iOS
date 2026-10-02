import os
import SwiftUI

extension Notification.Name {
    static let openGroundingSourceInLibrary = Notification.Name("openGroundingSourceInLibrary")
}

nonisolated struct LibraryPassage: Decodable, Identifiable, Sendable {
    let text: String
    let title: String
    let sourceId: String
    let chunkIndex: Int
    var id: String { "\(sourceId)-\(chunkIndex)" }
}

nonisolated struct LibraryWork: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let passageCount: Int
}

private nonisolated struct LibrarySection: Identifiable, Sendable {
    let id: String
    let title: String
    let chunks: ClosedRange<Int>
    let children: [LibrarySection]

    init(id: String, title: String, chunks: ClosedRange<Int>, children: [LibrarySection] = []) {
        self.id = id
        self.title = title
        self.chunks = chunks
        self.children = children
    }
}

private nonisolated extension Array where Element == LibrarySection {
    func node(withID id: String) -> LibrarySection? {
        for node in self {
            if node.id == id { return node }
            if let match = node.children.node(withID: id) { return match }
        }
        return nil
    }

    /// The outline path to the most specific section whose range covers `chunkIndex`.
    func path(containingChunk chunkIndex: Int) -> [LibrarySection]? {
        guard let node = first(where: { $0.chunks.contains(chunkIndex) }) else { return nil }
        return [node] + (node.children.path(containingChunk: chunkIndex) ?? [])
    }

    func path(to id: String) -> [LibrarySection]? {
        for node in self {
            if node.id == id { return [node] }
            if let childPath = node.children.path(to: id) { return [node] + childPath }
        }
        return nil
    }
}

private nonisolated extension LibrarySection {
    var firstReadableDescendant: LibrarySection {
        children.first?.firstReadableDescendant ?? self
    }
}

private nonisolated struct LibraryDocument: Sendable {
    let title: String
    let context: String
    let navigationUnit: String
    let passages: [LibraryPassage]
    let sections: [LibrarySection]

    static func load(_ work: LibraryWork) -> LibraryDocument? {
        guard let corpus = BundledPassageCorpus.bundled() else { return nil }

        let passages = corpus.passages(forSource: work.id)
        guard let first = passages.first, let last = passages.last else { return nil }
        let sections = outline(
            for: work.id,
            passages: passages,
            firstChunkIndex: first.chunkIndex,
            lastChunkIndex: last.chunkIndex
        )

        return LibraryDocument(
            title: work.title,
            context: work.id == "us-declaration-of-independence"
                ? "The unanimous Declaration of the thirteen united States of America, adopted by Congress on July 4, 1776."
                : "A work from the Angrove research corpus.",
            navigationUnit: navigationUnit(for: work.id),
            passages: passages,
            sections: sections
        )
    }

    private static func navigationUnit(for sourceID: String) -> String {
        switch sourceID {
        case "summa-theologica":
            "Article"
        case "web-bible":
            "Book"
        case "council-of-trent":
            "Session"
        case "ecumenical-creeds-schaff":
            "Creed"
        case "seven-ecumenical-councils":
            "Council"
        case "augsburg-confession", "belgic-confession", "thirty-nine-articles":
            "Article"
        case "heidelberg-catechism", "roman-catechism-donovan":
            "Part"
        case "baltimore-catechism-3":
            "Lesson"
        case "us-declaration-of-independence", "westminster-confession",
             "aristotle-categories", "machiavelli-the-prince", "anselm-proslogion":
            "Chapter"
        case "aristotle-nicomachean-ethics", "aristotle-metaphysics", "boethius-consolation",
             "adam-smith-wealth-of-nations", "bede-ecclesiastical-history",
             "eusebius-ecclesiastical-history", "herodotus-histories", "josephus-antiquities",
             "livy-history-of-rome", "tacitus-annals-histories", "thucydides-peloponnesian-war",
             "augustine-city-of-god", "irenaeus-against-heresies":
            "Book"
        case "plutarch-parallel-lives":
            "Life"
        case "magna-carta":
            "Clause"
        case "us-constitution":
            "Article"
        case "gibbon-decline-and-fall", "athanasius-on-incarnation", "didache",
             "justin-martyr-first-apology":
            "Section"
        default:
            "Section"
        }
    }

    private static func outline(
        for sourceID: String,
        passages: [LibraryPassage],
        firstChunkIndex: Int,
        lastChunkIndex: Int
    ) -> [LibrarySection] {
        let anchors: [(chunkIndex: Int, title: String)]

        switch sourceID {
        case "web-bible":
            return bibleSections(from: passages)
        case "summa-theologica":
            return summaTreatiseSections(from: passages)
        case "us-declaration-of-independence":
            anchors = [
                (0, "Chapter 1"), (2, "Chapter 2"), (4, "Chapter 3"),
                (6, "Chapter 4"), (7, "Chapter 5"),
            ]
        case "council-of-trent":
            anchors = [
                (0, "Introduction"),
                (36, "Session I"), (39, "Session II"), (42, "Session III"),
                (48, "Session IV"), (57, "Session V"), (70, "Session VI"),
                (107, "Session VII"), (132, "Session VIII"), (134, "Session IX"),
                (138, "Session X"), (145, "Session XI"), (147, "Session XII"),
                (149, "Session XIII"), (180, "Session XIV"), (233, "Session XV"),
                (244, "Session XVI"), (260, "Session XVII"), (262, "Session XVIII"),
                (270, "Session XIX"), (275, "Session XX"), (278, "Session XXI"),
                (293, "Session XXII"), (323, "Session XXIII"), (353, "Session XXIV"),
                (421, "Session XXV"),
            ]
        case "ecumenical-creeds-schaff":
            anchors = [
                (0, "Apostles' Creed"),
                (20, "Niceno-Constantinopolitan Creed"),
                (48, "Athanasian Creed"),
                (59, "Christological Definitions"),
            ]
        case "seven-ecumenical-councils":
            anchors = [
                (0, "General Introduction"),
                (70, "First Council of Nicea"),
                (501, "First Council of Constantinople"),
                (599, "Council of Ephesus"),
                (734, "Council of Chalcedon"),
                (938, "Second Council of Constantinople"),
                (1024, "Third Council of Constantinople"),
                (1559, "Second Council of Nicea"),
            ]
        case "augsburg-confession":
            anchors = [
                (0, "Preface"),
                (14, "Articles I–V"),
                (24, "Articles VI–X"),
                (35, "Articles XI–XVI"),
                (45, "Articles XVII–XXI"),
                (55, "Articles XXII–XXVIII"),
            ]
        case "belgic-confession":
            anchors = [
                (0, "Introduction"),
                (1, "Articles I–III"),
                (4, "Articles IV–VII"),
                (8, "Articles VIII–XI"),
                (14, "Articles XII–XV"),
                (20, "Articles XVI–XX"),
                (27, "Articles XXI–XXVII"),
                (37, "Articles XXVIII–XXXVII"),
            ]
        case "heidelberg-catechism":
            anchors = [
                (0, "Introduction"),
                (4, "Part I: The Misery of Man"),
                (8, "Part II: The Redemption of Man"),
                (59, "Part III: Thankfulness"),
            ]
        case "thirty-nine-articles":
            anchors = [
                (0, "Royal Declaration"),
                (3, "Articles I–IV"),
                (6, "Articles V–IX"),
                (10, "Articles X–XIV"),
                (13, "Articles XV–XIX"),
                (16, "Articles XX–XXIV"),
                (19, "Articles XXV–XXXIX"),
            ]
        case "westminster-confession":
            anchors = [
                (0, "Chapter I: Holy Scripture"),
                (6, "Chapters II–IV"),
                (10, "Chapters V–VIII"),
                (15, "Chapters IX–XII"),
                (19, "Chapters XIII–XVI"),
                (23, "Chapters XVII–XX"),
                (27, "Chapters XXI–XXV"),
                (31, "Chapters XXVI–XXXIII"),
            ]
        case "baltimore-catechism-3":
            anchors = [
                (0, "Prayers and Instructions"),
                (28, "Lessons I–IV: Faith and Creation"),
                (46, "Lessons V–VII: The Fall and Redemption"),
                (72, "Lessons VIII–IX: Christ's Passion and Ascension"),
                (89, "Lessons X–XII: Grace and the Church"),
                (116, "Lessons XIII–XVI: The Sacraments"),
                (145, "Lessons XVII–XVIII: Christian Virtue"),
                (165, "Lessons XIX–XXI: Penance and Eucharist"),
                (188, "Lessons XXII–XXV: Mass and Holy Orders"),
                (225, "Lessons XXVI–XXVIII: Matrimony and Prayer"),
                (258, "Lessons XXIX–XXXI: The Commandments"),
                (281, "Lessons XXXII–XXXV: The Commandments Continued"),
                (307, "Lessons XXXVI–XXXVII: Precepts and Indulgences"),
            ]
        case "roman-catechism-donovan":
            anchors = [
                (0, "Part I: The Apostles' Creed"),
                (214, "Part II: The Sacraments"),
                (594, "Part III: The Commandments"),
                (806, "Part IV: Prayer"),
            ]
        case "aristotle-categories":
            anchors = [
                (0, "Chapters I–II: Terms and Things"),
                (8, "Chapters III–IV: Substance"),
                (16, "Chapters V–VI: Quantity"),
                (24, "Chapters VII–VIII: Relatives and Quality"),
                (32, "Chapters IX–X: Contraries"),
                (40, "Chapters XI–XII: Quality and Opposition"),
                (48, "Chapters XIII–XV: Motion and Possession"),
                (60, "Closing Distinctions"),
            ]
        case "aristotle-nicomachean-ethics":
            anchors = [
                (0, "Book I: The Good and Happiness"),
                (44, "Book II: Moral Virtue"),
                (71, "Book III: Choice and Courage"),
                (120, "Book IV: Particular Virtues"),
                (168, "Book V: Justice"),
                (224, "Book VI: Intellectual Virtue"),
                (258, "Book VII: Continence and Pleasure"),
                (309, "Book VIII: Friendship"),
                (350, "Book IX: Friendship Continued"),
                (394, "Book X: Pleasure and Contemplation"),
            ]
        case "aristotle-metaphysics":
            anchors = [
                (0, "Book I"),
                (53, "Book X"),
                (90, "Book XI"),
                (91, "Book XII"),
                (94, "Book XIII"),
                (99, "Book XIV"),
                (100, "Book II"),
                (109, "Book III"),
                (151, "Book IV"),
                (206, "Book V"),
                (270, "Book VI"),
                (288, "Book VII"),
                (301, "Book VIII"),
                (302, "Book IX"),
            ]
        case "boethius-consolation":
            anchors = [
                (0, "Book I: The Prisoner and Philosophy"),
                (50, "Book II: Fortune's Gifts"),
                (110, "Book III: The Highest Good"),
                (170, "Book IV: Providence and Fate"),
                (225, "Book V: Free Will and Foreknowledge"),
            ]
        case "magna-carta":
            anchors = [
                (0, "Preamble and Liberties of the Church"),
                (4, "Justice, Trade, and Local Government"),
                (9, "Royal Administration and Forests"),
                (14, "Enforcement and the Security Clause"),
            ]
        case "us-constitution":
            anchors = [
                (0, "Annotated Overview"),
                (6, "Bill of Rights"),
                (21, "Civil War Amendments"),
                (58, "Early Amendments"),
                (64, "Twentieth-Century Amendments"),
                (85, "Individual Rights"),
                (102, "Constitutional Interpretation"),
                (152, "Proposed Amendments"),
                (169, "Structure and Separation of Powers"),
                (209, "Article I: Congress"),
            ]
        case "machiavelli-the-prince":
            anchors = [
                (0, "Chapter 1"),
                (1, "Chapter 10"), (4, "Chapter 11"), (9, "Chapter 12"),
                (19, "Chapter 13"), (24, "Chapter 14"), (29, "Chapter 15"),
                (32, "Chapter 16"), (36, "Chapter 17"), (41, "Chapter 18"),
                (47, "Chapter 19"), (64, "Chapter 2"), (65, "Chapter 20"),
                (73, "Chapter 21"), (80, "Chapter 22"), (82, "Chapter 23"),
                (85, "Chapter 24"), (88, "Chapter 25"), (94, "Chapter 26"),
                (100, "Chapter 3"), (115, "Chapter 4"), (120, "Chapter 5"),
                (122, "Chapter 6"), (128, "Chapter 7"), (141, "Chapter 8"),
                (150, "Chapter 9"), (190, "Notes and End Matter"),
            ]
        case "adam-smith-wealth-of-nations":
            anchors = [
                (0, "Appendix and Introduction"),
                (3, "Book I: Productive Powers of Labour"),
                (536, "Book II: Nature of Stock"),
                (745, "Book III: Progress of Opulence"),
                (829, "Book IV: Systems of Political Economy"),
                (1372, "Book V: Revenue of the Sovereign"),
            ]
        case "bede-ecclesiastical-history":
            anchors = [
                (0, "Book I"), (114, "Book II"), (200, "Book III"),
                (316, "Book IV"), (457, "Book V"),
            ]
        case "eusebius-ecclesiastical-history":
            anchors = [
                (0, "Books I–II: Origins of the Church"),
                (18, "Books III–IV: Apostolic Succession"),
                (38, "Books V–VI: Persecution and Heresy"),
                (58, "Books VII–VIII: The Great Persecution"),
                (72, "Books IX–X: Constantine and Peace"),
            ]
        case "gibbon-decline-and-fall":
            anchors = [
                (0, "Introduction"),
                (4, "The Roman Empire"),
                (8, "Decline and Transformation"),
                (12, "Notes and References"),
            ]
        case "herodotus-histories":
            anchors = [
                (0, "Book I: Clio"), (203, "Book II: Euterpe"),
                (370, "Book III: Thalia"), (520, "Book IV: Melpomene"),
                (674, "Book V: Terpsichore"), (780, "Book VI: Erato"),
                (893, "Book VII: Polyhymnia"), (1071, "Book VIII: Urania"),
                (1182, "Book IX: Calliope"),
            ]
        case "josephus-antiquities":
            anchors = [
                (0, "Book I"), (106, "Book II"), (220, "Book III"),
                (326, "Book IV"), (441, "Book IX"), (539, "Book V"),
                (656, "Book VI"), (800, "Book VII"), (941, "Book VIII"),
                (1090, "Book X"), (1186, "Book XI"), (1286, "Book XII"),
                (1414, "Book XIII"), (1544, "Book XIV"), (1691, "Book XIX"),
                (1825, "Book XV"), (1961, "Book XVI"), (2080, "Book XVII"),
                (2200, "Book XVIII"), (2351, "Book XX"),
            ]
        case "livy-history-of-rome":
            anchors = [
                (0, "Founding of Rome"),
                (427, "Early Republic"),
                (838, "The Second Punic War"),
                (1563, "Rome's Mediterranean Expansion"),
                (2307, "The Mature Republic"),
                (3107, "Later Republican Rome"),
                (3916, "Roman Expansion Eastward"),
                (4698, "The Macedonian Settlement"),
                (5264, "Later Books and Epitomes"),
            ]
        case "plutarch-parallel-lives":
            anchors = [
                (0, "Greek Founders and Lawgivers"),
                (260, "Athenian and Spartan Lives"),
                (520, "The Persian Wars"),
                (780, "The Peloponnesian War"),
                (1040, "Theban and Macedonian Lives"),
                (1300, "Roman Republic"),
                (1560, "The Late Republic"),
                (1820, "Caesar and the Imperial Age"),
            ]
        case "tacitus-annals-histories":
            anchors = [
                (0, "Annals: Book I"), (98, "Annals: Book XI"),
                (135, "Annals: Book XII"), (197, "Annals: Book XIII"),
                (269, "Annals: Book XIV"), (339, "Annals: Book XV"),
                (418, "Annals: Book XVI"), (457, "Annals: Book II"),
                (551, "Annals: Book III"), (633, "Annals: Book IV"),
                (721, "Annals: Book V"), (730, "Annals: Book VI"),
            ]
        case "thucydides-peloponnesian-war":
            anchors = [
                (0, "Book I"), (167, "Book II"), (295, "Book III"),
                (415, "Book IV"), (561, "Book V"), (664, "Book VI"),
                (791, "Book VII"), (902, "Book VIII"),
            ]
        case "anselm-proslogion":
            anchors = [
                (0, "Preface and Chapters I–VIII"),
                (17, "Chapters IX–XVII"),
                (35, "Chapters XVIII–XXVI"),
            ]
        case "athanasius-on-incarnation":
            anchors = [
                (0, "Introduction and Creation"),
                (42, "The Fall and Divine Dilemma"),
                (84, "The Incarnation of the Word"),
                (126, "The Cross and Resurrection"),
                (168, "Defence and Conclusion"),
            ]
        case "augustine-city-of-god":
            anchors = [
                (0, "Book I"), (108, "Book II"), (215, "Book III"),
                (323, "Book IV"), (433, "Book V"), (563, "Book VI"),
                (633, "Book VII"), (757, "Book VIII"), (876, "Book IX"),
                (946, "Book X"), (1091, "Book XI"), (1216, "Book XII"),
                (1318, "Book XIII"), (1418, "Book XIV"), (1541, "Book XV"),
                (1682, "Book XVI"), (1839, "Book XVII"), (1969, "Book XVIII"),
                (2160, "Book XIX"), (2293, "Book XX"), (2477, "Book XXI"),
                (2619, "Book XXII"),
            ]
        case "didache":
            anchors = [
                (0, "The Two Ways"),
                (6, "Baptism, Fasting, and Prayer"),
                (11, "Eucharist, Ministry, and the End Times"),
            ]
        case "irenaeus-against-heresies":
            anchors = [
                (0, "Book I: The Gnostic Systems"),
                (450, "Book II: Refutation by Reason"),
                (900, "Book III: Apostolic Tradition"),
                (1350, "Book IV: God and Humanity"),
                (1800, "Book V: Resurrection and the Kingdom"),
            ]
        case "justin-martyr-first-apology":
            anchors = [
                (0, "Address to the Emperor"),
                (32, "Christian Worship and Ethics"),
                (64, "Christ and the Prophets"),
                (96, "Conclusion and Petition"),
            ]
        default:
            anchors = [(firstChunkIndex, "Chapter 1")]
        }

        let validAnchors = anchors
            .filter { $0.chunkIndex >= firstChunkIndex && $0.chunkIndex <= lastChunkIndex }
            .sorted { $0.chunkIndex < $1.chunkIndex }

        let flatSections = validAnchors.enumerated().map { index, anchor in
            let finalChunkIndex = index + 1 < validAnchors.count
                ? validAnchors[index + 1].chunkIndex - 1
                : lastChunkIndex
            return LibrarySection(
                id: "chapter-\(index + 1)",
                title: anchor.title,
                chunks: anchor.chunkIndex...finalChunkIndex
            )
        }
        return addingSubsections(to: flatSections, from: passages)
    }

    private static func bibleSections(from passages: [LibraryPassage]) -> [LibrarySection] {
        let starts = bibleBooks.compactMap { book in
            passages.first(where: { $0.text.hasPrefix("[\(book.marker)]") })
                .map { (chunkIndex: $0.chunkIndex, title: book.title, marker: book.marker) }
        }
        .sorted { $0.chunkIndex < $1.chunkIndex }

        return starts.enumerated().map { index, start in
            let finalChunkIndex = index + 1 < starts.count
                ? starts[index + 1].chunkIndex - 1
                : passages.last?.chunkIndex ?? start.chunkIndex
            let bookPassages = passages.filter { start.chunkIndex...finalChunkIndex ~= $0.chunkIndex }
            let chapterPrefix = start.marker == "PSA001" ? "PSA" : String(start.marker.dropLast(2))
            let chapterStarts = bookPassages.compactMap { passage -> (Int, Int)? in
                guard passage.text.hasPrefix("[\(chapterPrefix)"), let end = passage.text.firstIndex(of: "]") else { return nil }
                let marker = String(passage.text[passage.text.index(after: passage.text.startIndex)..<end])
                let suffix = String(marker.dropFirst(chapterPrefix.count))
                guard let chapter = Int(suffix) else { return nil }
                return (passage.chunkIndex, chapter)
            }
            let chapters = chapterStarts.enumerated().map { chapterIndex, chapterStart in
                let finalChapterChunk = chapterIndex + 1 < chapterStarts.count ? chapterStarts[chapterIndex + 1].0 - 1 : finalChunkIndex
                return LibrarySection(id: "chapter-\(index + 1)-sub-\(chapterStart.1)", title: "Chapter \(chapterStart.1)", chunks: chapterStart.0...finalChapterChunk)
            }
            return LibrarySection(
                id: "chapter-\(index + 1)",
                title: start.title,
                chunks: start.chunkIndex...finalChunkIndex,
                children: chapters
            )
        }
    }

    private static func summaTreatiseSections(from passages: [LibraryPassage]) -> [LibrarySection] {
        var starts: [(chunkIndex: Int, title: String)] = [
            (passages.first?.chunkIndex ?? 0, "Introduction")
        ]

        starts += passages.compactMap { passage in
            let prefix = String(passage.text.prefix(240))
            guard let range = prefix.range(of: "TREATISE ", options: .caseInsensitive) else {
                return nil
            }

            let heading = String(prefix[range.lowerBound...])
                .replacingOccurrences(of: "\n", with: " ")
                .components(separatedBy: "(QQ")
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let heading, !heading.isEmpty else { return nil }
            return (chunkIndex: passage.chunkIndex, title: heading.capitalized)
        }

        let orderedStarts = Dictionary(grouping: starts, by: \.chunkIndex)
            .compactMap { $0.value.first }
            .sorted { $0.chunkIndex < $1.chunkIndex }

        let flatSections = orderedStarts.enumerated().map { index, start in
            let finalChunkIndex = index + 1 < orderedStarts.count
                ? orderedStarts[index + 1].chunkIndex - 1
                : passages.last?.chunkIndex ?? start.chunkIndex
            return LibrarySection(
                id: "chapter-\(index + 1)",
                title: start.title,
                chunks: start.chunkIndex...finalChunkIndex
            )
        }
        return addingSubsections(to: flatSections, from: passages)
    }

    private static func addingSubsections(
        to sections: [LibrarySection],
        from passages: [LibraryPassage]
    ) -> [LibrarySection] {
        sections.map { section in
            let starts = passages.compactMap { passage -> (chunkIndex: Int, title: String, level: Int)? in
                guard section.chunks.contains(passage.chunkIndex),
                      let heading = subsectionHeading(in: passage.text),
                      passage.chunkIndex != section.chunks.lowerBound
                else { return nil }
                return (passage.chunkIndex, heading.title, heading.level)
            }
            return LibrarySection(
                id: section.id,
                title: section.title,
                chunks: section.chunks,
                children: subsectionTree(
                    starts: starts,
                    within: section.chunks,
                    parentLevel: 0,
                    parentID: section.id,
                    depth: 1
                )
            )
        }
    }

    private static func subsectionTree(
        starts: [(chunkIndex: Int, title: String, level: Int)],
        within chunks: ClosedRange<Int>,
        parentLevel: Int,
        parentID: String,
        depth: Int
    ) -> [LibrarySection] {
        guard depth <= 5 else { return [] }
        let eligible = starts.filter { $0.level > parentLevel }.sorted { $0.chunkIndex < $1.chunkIndex }
        guard let directLevel = eligible.map(\.level).min() else { return [] }
        let directStarts = eligible.filter { $0.level == directLevel }

        return directStarts.enumerated().map { index, start in
            let end = index + 1 < directStarts.count ? directStarts[index + 1].chunkIndex - 1 : chunks.upperBound
            let childChunks = start.chunkIndex...end
            let childStarts = eligible.filter { childChunks.contains($0.chunkIndex) && $0.chunkIndex != start.chunkIndex }
            return LibrarySection(
                id: "\(parentID)-sub-\(start.chunkIndex)",
                title: start.title,
                chunks: childChunks,
                children: subsectionTree(
                    starts: childStarts,
                    within: childChunks,
                    parentLevel: directLevel,
                    parentID: "\(parentID)-sub-\(start.chunkIndex)",
                    depth: depth + 1
                )
            )
        }
    }

    /// Checked against every passage when a work's outline is built, so it is compiled once.
    private static let subsectionHeadingPattern = try! NSRegularExpression(
        pattern: "(?i)^(?:\\[[^\\]]+\\]\\s*)?((?:book|part|treatise|session|chapter|question|article|section|lesson)\\s*(?:[IVXLCDM]+|\\d+)(?:\\s*[:.\\-]\\s*[^.]{0,110})?)"
    )

    private static func subsectionHeading(in text: String) -> (title: String, level: Int)? {
        let prefix = String(text.prefix(260))
            .replacingOccurrences(of: "\\r", with: " ")
            .replacingOccurrences(of: "\\n", with: " ")
        guard let match = subsectionHeadingPattern.firstMatch(in: prefix, range: NSRange(prefix.startIndex..., in: prefix)),
              let range = Range(match.range(at: 1), in: prefix)
        else { return nil }

        let title = String(prefix[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        let firstWord = title.split(separator: " ").first?.lowercased() ?? ""
        let level: Int
        switch firstWord {
        case "book", "part", "treatise", "session": level = 1
        case "chapter", "question": level = 2
        case "article", "section", "lesson": level = 3
        default: return nil
        }
        return (title, level)
    }

    static func bibleBookTitle(forCode code: String) -> String? {
        bibleBooks.first { $0.marker == code + (code == "PSA" ? "001" : "01") }?.title
    }

    private static let bibleBooks: [(marker: String, title: String)] = [
        ("1CH01", "1 Chronicles"), ("1CO01", "1 Corinthians"),
        ("1ES01", "1 Esdras"), ("1JN01", "1 John"),
        ("1KI01", "1 Kings"), ("1MA01", "1 Maccabees"),
        ("1PE01", "1 Peter"), ("1SA01", "1 Samuel"),
        ("1TH01", "1 Thessalonians"), ("1TI01", "1 Timothy"),
        ("2CH01", "2 Chronicles"), ("2CO01", "2 Corinthians"),
        ("2ES01", "2 Esdras"), ("2JN01", "2 John"),
        ("2KI01", "2 Kings"), ("2MA01", "2 Maccabees"),
        ("2PE01", "2 Peter"), ("2SA01", "2 Samuel"),
        ("2TH01", "2 Thessalonians"), ("2TI01", "2 Timothy"),
        ("3JN01", "3 John"), ("3MA01", "3 Maccabees"),
        ("4MA01", "4 Maccabees"), ("ACT01", "Acts"), ("AMO01", "Amos"),
        ("BAR01", "Baruch"), ("COL01", "Colossians"),
        ("DAG01", "Daniel (Greek)"), ("DAN01", "Daniel"),
        ("DEU01", "Deuteronomy"), ("ECC01", "Ecclesiastes"),
        ("EPH01", "Ephesians"), ("ESG01", "Esther (Greek)"),
        ("EST01", "Esther"), ("EXO01", "Exodus"), ("EZK01", "Ezekiel"),
        ("EZR01", "Ezra"), ("FRT01", "Preface"), ("GAL01", "Galatians"),
        ("GEN01", "Genesis"), ("GLO01", "Glossary"), ("HAB01", "Habakkuk"),
        ("HAG01", "Haggai"), ("HEB01", "Hebrews"), ("HOS01", "Hosea"),
        ("ISA01", "Isaiah"), ("JAS01", "James"), ("JDG01", "Judges"),
        ("JDT01", "Judith"), ("JER01", "Jeremiah"), ("JHN01", "John"),
        ("JOB01", "Job"), ("JOL01", "Joel"), ("JON01", "Jonah"),
        ("JOS01", "Joshua"), ("JUD01", "Jude"), ("LAM01", "Lamentations"),
        ("LEV01", "Leviticus"), ("LUK01", "Luke"), ("MAL01", "Malachi"),
        ("MAN01", "Prayer of Manasses"), ("MAT01", "Matthew"),
        ("MIC01", "Micah"), ("MRK01", "Mark"), ("NAM01", "Nahum"),
        ("NEH01", "Nehemiah"), ("NUM01", "Numbers"), ("OBA01", "Obadiah"),
        ("PHM01", "Philemon"), ("PHP01", "Philippians"),
        ("PRO01", "Proverbs"), ("PS2001", "Psalm 151"),
        ("PSA001", "Psalms"), ("REV01", "Revelation"), ("ROM01", "Romans"),
        ("RUT01", "Ruth"), ("SIR01", "Sirach"), ("SNG01", "Song of Songs"),
        ("TIT01", "Titus"), ("TOB01", "Tobit"),
        ("WIS01", "Wisdom of Solomon"), ("ZEC01", "Zechariah"),
        ("ZEP01", "Zephaniah"),
    ]
}

/// Mirrors `StudyTopicsView`: the homepage remains mounted below an opaque detail layer, while
/// the shared navigation button morphs in place as the detail transitions from the trailing edge.
struct LibraryView: View {
    let onOpenMenu: () -> Void
    let modelTasks: ModelTaskQueue
    let modelTasksPopupState: ModelTasksPopupState
    let onReaderVisibilityChange: (Bool) -> Void
    let navigationRequest: LibraryNavigationRequest?
    @State private var catalog: LibraryCatalog?
    @State private var searchText = ""
    @State private var selectedWorkID: String?
    @State private var targetChunkIndex: Int?
    @State private var targetScripture: LibraryTextFormatter.ScriptureTarget?
    @State private var pendingNavigationRequest: LibraryNavigationRequest?
    @AppStorage(LibraryRecents.storageKey) private var recentWorkIDsRaw = ""

    private var works: [LibraryWork] { catalog?.works ?? [] }

    private var selectedWork: LibraryWork? {
        works.first { $0.id == selectedWorkID }
    }

    var body: some View {
        ZStack {
            LibraryHomeView(
                catalog: catalog,
                recentWorkIDs: LibraryRecents.decode(recentWorkIDsRaw),
                searchText: $searchText,
                onOpenWork: { openWork(id: $0.id) },
                onOpenPassage: { openWork(id: $0.workID, atChunk: $0.chunkIndex) }
            )

            if let selectedWork {
                LibraryDocumentDetail(
                    work: selectedWork,
                    targetTitle: navigationRequest?.sourceTitle,
                    targetChunkIndex: targetChunkIndex,
                    targetScripture: targetScripture,
                    modelTasks: modelTasks,
                    modelTasksPopupState: modelTasksPopupState,
                    onOpenScripture: openScripture
                )
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }

            VStack {
                HStack(spacing: 8) {
                    AngroveNavButton(onMenuTap: onOpenMenu)
                    if selectedWorkID != nil {
                        NavBackCapsuleButton(title: "Library", action: closeDocument)
                            .transition(.studyExitGrow)
                    }
                    Spacer()
                }
                .animation(.springStandard, value: selectedWorkID)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .zIndex(20)
        }
        .animation(.springStandard, value: selectedWorkID)
        .onChange(of: selectedWorkID) { _, id in
            modelTasksPopupState.reset()
            onReaderVisibilityChange(id != nil)
            if let id {
                recentWorkIDsRaw = LibraryRecents.encode(
                    LibraryRecents.opening(id, in: LibraryRecents.decode(recentWorkIDsRaw))
                )
            }
        }
        .onDisappear { onReaderVisibilityChange(false) }
        .task {
            // The bundled corpus is tens of megabytes; decode it off the main actor so the
            // homepage chrome appears immediately.
            let loaded = await Task.detached(priority: .userInitiated) {
                LibraryCatalog.loadBundled()
            }.value
            withAnimation(.easeOut(duration: 0.25)) { catalog = loaded }
            // A request that opened the Library arrives as the initial value, which `onChange`
            // never reports; one that arrived while the catalog loaded is held as pending.
            if let request = pendingNavigationRequest ?? navigationRequest {
                pendingNavigationRequest = nil
                applyNavigationRequest(request)
            }
        }
        .onChange(of: navigationRequest) { _, request in
            guard let request else { return }
            if catalog == nil {
                pendingNavigationRequest = request
            } else {
                applyNavigationRequest(request)
            }
        }
    }

    private func applyNavigationRequest(_ request: LibraryNavigationRequest) {
        guard let work = works.first(where: {
            $0.id == request.sourceID
                || $0.title.caseInsensitiveCompare(request.sourceTitle) == .orderedSame
                || $0.title.caseInsensitiveCompare(request.sourceName) == .orderedSame
        }) else { return }
        targetScripture = nil
        targetChunkIndex = request.chunkIndex
        selectedWorkID = work.id
    }

    private func openScripture(_ target: LibraryTextFormatter.ScriptureTarget) {
        withAnimation(.springStandard) {
            targetChunkIndex = nil
            targetScripture = target
            selectedWorkID = "web-bible"
        }
    }

    private func openWork(id: String, atChunk chunkIndex: Int? = nil) {
        withAnimation(.springStandard) {
            targetScripture = nil
            targetChunkIndex = chunkIndex
            selectedWorkID = id
        }
    }

    private func closeDocument() {
        withAnimation(.springStandard) {
            selectedWorkID = nil
            targetChunkIndex = nil
            targetScripture = nil
        }
    }
}

private struct LibraryDocumentDetail: View {
    private static let readerTopID = "reader-top"
    let work: LibraryWork
    let targetTitle: String?
    var targetChunkIndex: Int?
    var targetScripture: LibraryTextFormatter.ScriptureTarget?
    let modelTasks: ModelTaskQueue
    let modelTasksPopupState: ModelTasksPopupState
    let onOpenScripture: (LibraryTextFormatter.ScriptureTarget) -> Void
    @State private var document: LibraryDocument?
    @State private var selectedSectionID = "chapter-1"
    @State private var selectedOutlineID = "chapter-1"
    @State private var isContentsOpen = false
    @State private var isPageTextVisible = true
    @State private var pageTransitionTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .top) {
            AngroveTheme.Colors.canvas.ignoresSafeArea()
            if let document {
                let selectedIndex = document.sections.firstIndex(where: { $0.id == selectedSectionID }) ?? 0
                let selectedSection = document.sections[selectedIndex]
                let selectedOutline = document.sections.node(withID: selectedOutlineID) ?? selectedSection
                let visibleChunks = selectedOutline.chunks
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 32) {
                            LibraryReaderHeader(
                                subject: LibrarySubject.of(workID: work.id).generalTitle,
                                title: document.title,
                                context: document.context
                            )
                            .id(Self.readerTopID)
                            LibraryTextSection(
                                title: selectedOutline.id == selectedSection.id || selectedOutline.title.contains(": ")
                                    ? selectedOutline.title
                                    : "\(selectedSection.title): \(selectedOutline.title)",
                                passages: document.passages.filter { visibleChunks.contains($0.chunkIndex) },
                                sourceID: work.id,
                                highlightedChunkIndex: targetChunkIndex,
                                isVisible: isPageTextVisible,
                                onOpenScripture: onOpenScripture
                            )
                            .id(selectedOutline.id)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 140)
                    }
                    // Clears the floating menu and back buttons, including for scroll-to-passage.
                    .safeAreaPadding(.top, 88)
                    .onChange(of: isPageTextVisible) { _, visible in
                        guard visible else { return }
                        if let targetChunkIndex, visibleChunks.contains(targetChunkIndex) {
                            withAnimation(.springStandard) {
                                proxy.scrollTo(targetChunkIndex, anchor: .top)
                            }
                        } else {
                            // A new page or work starts at its heading, not the prior scroll offset.
                            proxy.scrollTo(Self.readerTopID, anchor: .top)
                        }
                    }
                }
                // Keep the controls publisher mounted while chapter text changes (it publishes to
                // the shell's single Model Controls bar and renders nothing here). Giving the
                // ScrollView the outline ID would recreate it on every chapter navigation.
                .background {
                        LibraryModelControls(
                            modelTasks: modelTasks,
                            modelTasksPopupState: modelTasksPopupState,
                            isContentsOpen: $isContentsOpen,
                            previousChapterTitle: selectedIndex > 0 ? "\(document.navigationUnit) \(selectedIndex)" : nil,
                            nextChapterTitle: selectedIndex < document.sections.count - 1 ? "\(document.navigationUnit) \(selectedIndex + 2)" : nil,
                            onPreviousChapter: {
                                transitionToPage(
                                    sectionID: document.sections[selectedIndex - 1].id,
                                    outlineID: document.sections[selectedIndex - 1].firstReadableDescendant.id
                                )
                            },
                            onNextChapter: {
                                transitionToPage(
                                    sectionID: document.sections[selectedIndex + 1].id,
                                    outlineID: document.sections[selectedIndex + 1].firstReadableDescendant.id
                                )
                            }
                        ) {
                            LibraryContentsCard(
                                sections: document.sections,
                                selectedOutlineID: selectedOutlineID,
                                onSelectOutline: { outlineID in
                                    let sectionID = document.sections.first(where: { $0.id == outlineID })?.id
                                        ?? selectedSectionID
                                    transitionToPage(sectionID: sectionID, outlineID: outlineID)
                                    withAnimation(.springStandard) {
                                        isContentsOpen = true
                                    }
                                }
                            )
                        }
                    }
            } else {
                ProgressView()
            }
        }
        .onDisappear {
            pageTransitionTask?.cancel()
        }
        .task(id: work.id) {
            isPageTextVisible = false
            // Outlining a work walks every passage; keep it off the main actor.
            let work = work
            document = await Task.detached(priority: .userInitiated) {
                LibraryDocument.load(work)
            }.value
            guard !Task.isCancelled else { return }
            selectedSectionID = document?.sections.first?.id ?? "chapter-1"
            selectedOutlineID = document?.sections.first?.firstReadableDescendant.id ?? "chapter-1"
            if let targetTitle,
               let match = document?.sections.first(where: { $0.title.caseInsensitiveCompare(targetTitle) == .orderedSame }) {
                selectedSectionID = match.id
                selectedOutlineID = match.firstReadableDescendant.id
            }
            if let targetScripture,
               let bookTitle = LibraryDocument.bibleBookTitle(forCode: targetScripture.bookCode),
               let book = document?.sections.first(where: { $0.title == bookTitle }) {
                selectedSectionID = book.id
                selectedOutlineID = book.children.first(where: { $0.title == "Chapter \(targetScripture.chapter)" })?.id
                    ?? book.firstReadableDescendant.id
            }
            if let targetChunkIndex,
               let path = document?.sections.path(containingChunk: targetChunkIndex),
               let section = path.first, let outline = path.last {
                selectedSectionID = section.id
                selectedOutlineID = outline.id
            }
            await Task.yield()
            withAnimation(.easeIn(duration: 0.25)) {
                isPageTextVisible = true
            }
        }
    }

    private func transitionToPage(sectionID: String, outlineID: String) {
        pageTransitionTask?.cancel()
        withAnimation(.easeOut(duration: 0.25)) {
            isPageTextVisible = false
        }

        pageTransitionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }

            selectedSectionID = sectionID
            selectedOutlineID = outlineID
            await Task.yield()
            guard !Task.isCancelled else { return }

            withAnimation(.easeIn(duration: 0.2)) {
                isPageTextVisible = true
            }
        }
    }
}

private struct LibraryReaderHeader: View {
    let subject: String
    let title: String
    let context: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(subject.uppercased())
                .font(AngroveTheme.Typography.uiLabel)
                .foregroundStyle(AngroveTheme.Colors.lightGreen)
            Text(title)
                .font(.custom("LibreBaskerville-Regular", size: 34))
                .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Text(context)
                .font(.custom("LibreBaskerville-Italic", size: 16))
                .foregroundStyle(AngroveTheme.Colors.paragraphText)
                .lineSpacing(6)
            OrnamentRule()
                .padding(.top, 8)
        }
    }
}

private struct LibraryTextSection: View {
    let title: String
    let passages: [LibraryPassage]
    let sourceID: String
    var highlightedChunkIndex: Int?
    let isVisible: Bool
    let onOpenScripture: (LibraryTextFormatter.ScriptureTarget) -> Void
    @AppStorage("aquinas.settings.conversationFontSize")
    private var conversationFontSize: ConversationFontSizeOption = .medium
    @AppStorage("aquinas.settings.responseFont")
    private var responseFont: ConversationFontOption = .serif

    /// "Book II: Nature of Stock" reads as a small-caps kicker over a serif chapter title.
    private var titleParts: (kicker: String?, heading: String) {
        guard let range = title.range(of: ": ") else { return (nil, title) }
        return (String(title[..<range.lowerBound]), String(title[range.upperBound...]))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(spacing: 8) {
                if let kicker = titleParts.kicker {
                    Text(kicker.uppercased())
                        .font(AngroveTheme.Typography.uiLabel)
                        .tracking(1.5)
                        .foregroundStyle(AngroveTheme.Colors.placeholderText)
                }
                Text(titleParts.heading)
                    .font(.custom("LibreBaskerville-Italic", size: 24))
                    .foregroundStyle(AngroveTheme.Colors.headingText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity)

            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(passages) { passage in
                    LibraryParagraph(
                        text: LibraryTextFormatter.attributed(
                            passage.text,
                            sourceID: sourceID,
                            linkColor: AngroveTheme.Colors.lightGreen,
                            verseColor: AngroveTheme.Colors.lightGreen,
                            verseFont: .custom("Figtree-Bold", size: max(9, conversationFontSize.pointSize - 4))
                        ),
                        font: responseFont.textFont(size: conversationFontSize),
                        isHighlighted: passage.chunkIndex == highlightedChunkIndex
                    )
                    .id(passage.chunkIndex)
                }
            }
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                guard let target = LibraryTextFormatter.ScriptureTarget(url: url) else { return .discarded }
                onOpenScripture(target)
                return .handled
            })

            AppIconImage(size: 14)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .accessibilityHidden(true)
        }
        .opacity(isVisible ? 1 : 0)
    }
}

/// One corpus chunk. Rendering chunks separately keeps long sections within `Text`'s limits
/// and lets the reader scroll straight to a featured passage.
private struct LibraryParagraph: View {
    let text: AttributedString
    let font: Font
    let isHighlighted: Bool

    var body: some View {
        Text(text)
            .font(font)
            .lineSpacing(8)
            .foregroundStyle(isHighlighted ? AngroveTheme.Colors.primaryReadable : AngroveTheme.Colors.paragraphText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(isHighlighted ? 24 : 0)
            .background {
                if isHighlighted {
                    let shape = RoundedRectangle(cornerRadius: AngroveTheme.Spacing.cardRadius, style: .continuous)
                    shape
                        .fill(AngroveTheme.Colors.canvasSecondary)
                        .overlay(shape.stroke(AngroveTheme.Colors.quietBorder, lineWidth: 1))
                }
            }
    }
}

private struct LibraryContentsCard: View {
    let sections: [LibrarySection]
    let selectedOutlineID: String
    let onSelectOutline: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Table of Contents").font(.custom("Figtree-Bold", size: 18)).foregroundStyle(AngroveTheme.Colors.headingText)
            if let path = sections.path(to: selectedOutlineID), let selected = path.last {
                LibraryContentsBreadcrumb(path: path, onSelectOutline: onSelectOutline)
                let visibleNodes = selected.children.isEmpty ? (path.dropLast().last?.children ?? sections) : selected.children
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(visibleNodes) { node in
                            ContentsRow(title: node.title, isSelected: node.id == selectedOutlineID) {
                                onSelectOutline(node.id)
                            }
                        }
                    }
                }
                .frame(maxHeight: 186)
            } else {
                ForEach(sections) { section in
                    ContentsRow(title: section.title, isSelected: section.id == selectedOutlineID) { onSelectOutline(section.id) }
                }
            }
        }
        .padding(24).frame(width: 369, alignment: .leading).background(AngroveTheme.Colors.canvasSecondary).clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct LibraryContentsBreadcrumb: View {
    let path: [LibrarySection]
    let onSelectOutline: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(path.dropLast()) { node in
                Button { onSelectOutline(node.id) } label: {
                    Text(node.title)
                        .font(.custom("Figtree-SemiBold", size: 14))
                        .foregroundStyle(AngroveTheme.Colors.lightGreen)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                if node.id != path.dropLast().last?.id {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AngroveTheme.Colors.placeholderText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ContentsRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                HStack(spacing: 4) {
                    if isSelected {
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(AngroveTheme.Colors.lightGreen).transition(.scale.combined(with: .opacity))
                    }
                    Text(title).font(.custom(isSelected ? "Figtree-SemiBold" : "Figtree-Regular", size: 14)).foregroundStyle(isSelected ? AngroveTheme.Colors.lightGreen : AngroveTheme.Colors.paragraphText)
                }
                .fixedSize().animation(.springLively, value: isSelected)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Passage Locator

/// Short, human-readable locations for corpus passages ("John 14", "Nicomachean Ethics, Book V"),
/// drawn from the same outline the Library reader shows. Outlines are built once per work.
nonisolated enum LibraryPassageLocator {
    private static let outlines = OSAllocatedUnfairLock<[String: [LibrarySection]]>(initialState: [:])

    /// `nil` when the work is not in the bundled corpus.
    static func label(sourceID: String, chunkIndex: Int) -> String? {
        guard let corpus = BundledPassageCorpus.bundled(),
              let first = corpus.indicesBySource[sourceID]?.first
        else { return nil }
        return label(sourceID: sourceID, chunkIndex: chunkIndex, workTitle: corpus.passages[first].title)
    }

    static func label(sourceID: String, chunkIndex: Int, workTitle: String) -> String {
        guard let path = sections(for: sourceID, workTitle: workTitle)
            .path(containingChunk: chunkIndex),
              let leaf = path.last
        else { return workTitle }

        if sourceID == "web-bible", path.count > 1, leaf.title.hasPrefix("Chapter ") {
            return "\(path[path.count - 2].title) \(leaf.title.dropFirst("Chapter ".count))"
        }
        let section = shortened(leaf.title)
        guard !section.isEmpty, section != "Introduction" || path.count == 1 else { return workTitle }
        return "\(workTitle), \(section)"
    }

    /// Keeps the locator itself ("Book V") and drops descriptive subtitles and question ranges.
    private static func shortened(_ title: String) -> String {
        var result = title
        for separator in [":", " (", " —"] {
            if let range = result.range(of: separator) {
                result = String(result[..<range.lowerBound])
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func sections(for sourceID: String, workTitle: String) -> [LibrarySection] {
        if let cached = outlines.withLock({ $0[sourceID] }) { return cached }
        let sections = LibraryDocument.load(
            LibraryWork(id: sourceID, title: workTitle, passageCount: 0)
        )?.sections ?? []
        outlines.withLock { $0[sourceID] = sections }
        return sections
    }
}
