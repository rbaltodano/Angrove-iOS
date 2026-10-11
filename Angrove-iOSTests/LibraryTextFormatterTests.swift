import Foundation
import SwiftUI
import Testing
@testable import Angrove_iOS

@Suite("Library reader text cleanup")
struct LibraryTextFormatterTests {
    @Test("Export dividers disappear without losing book headings or prose")
    func stripsExportDividers() {
        #expect(LibraryTextFormatter.cleaned("FIRST PART (FP: QQ 1-119) __________________________________________________________________") == "FIRST PART (FP: QQ 1-119)")
        #expect(LibraryTextFormatter.cleaned("___ Whether it is necessary? ___") == "Whether it is necessary?")
        #expect(LibraryTextFormatter.cleaned("The reply is clear. ___ Next question.") == "The reply is clear. Next question.")
        #expect(LibraryTextFormatter.cleaned("===1===") == "1")
        for debris in ["_", "* * *", "\\", "^", "}", "«", "■", "— — —"] {
            #expect(LibraryTextFormatter.cleaned(debris).isEmpty)
        }
    }

    @Test("Separate website navigation paragraphs disappear")
    func stripsStandaloneNavigation() {
        for navigation in [
            "Home Encyclopedia Summa Fathers Bible Library",
            "A B C D E F G H I J K L M N O P Q R S T U V W X Y Z",
            "Search:", "Submit Search", "NEW ADVENT: Home",
            "sister projects: Wikipedia article", "related portals: Calvinism",
            "information about this edition",
            "For other English-language translations of this work, see Categories.",
        ] {
            #expect(LibraryTextFormatter.cleaned(navigation).isEmpty)
        }
        #expect(LibraryTextFormatter.cleaned("Home is where the story begins.") == "Home is where the story begins.")
    }

    @Test("Real opening punctuation, verse numbers, and footnotes survive")
    func preservesBookText() {
        for text in ["“In the beginning.”", "'Gainst Venus and Minerva,", "(1) Whether it is necessary?", "1 In the beginning", "†1:1“Christ” means “Anointed One”.", "— The First Book, Entitled Clio", "∴ the conclusion follows."] {
            #expect(LibraryTextFormatter.cleaned(text) == text)
        }
    }

    @Test("Hidden debris leaves original reader identities and positions intact")
    func filtersEmptyReaderParagraphs() {
        let passages = ["___", "FIRST PART ___", "A B C D E F G H I J K L M N O P Q R S T U V W X Y Z", "Objection 1: It seems…"].enumerated().map {
            LibraryPassage(text: $0.element, title: "Book", sourceId: "summa-theologica", chunkIndex: $0.offset)
        }
        let visible = LibraryTextFormatter.readablePassages(passages)
        #expect(visible.map(\.chunkIndex) == [1, 3])
        #expect(visible.map(\.id) == [passages[1].id, passages[3].id])
        #expect(visible[0].text == passages[1].text)
    }

    @Test("Corpus markup, URLs, and footnote markers are removed")
    func stripsCorpusLitter() {
        let text = "[The Prince (Marriott)/Chapter 1] Dedication declared[1] to be good. "
            + "Online at https://constitution.congress.gov/browse/ now [edit] ↑ Digitized by Google done."
        let cleaned = LibraryTextFormatter.cleaned(text)
        #expect(cleaned == "Dedication declared to be good. Online at now done.")
    }

    @Test("Scanned hyphenation and fused words are repaired")
    func repairsBrokenWords() {
        #expect(LibraryTextFormatter.cleaned("Now be- cause Di- onysius says") == "Now because Dionysius says")
        #expect(LibraryTextFormatter.cleaned("Frequently Asked QuestionsThe Bible") == "Frequently Asked Questions The Bible")
        #expect(LibraryTextFormatter.cleaned("share it freely.Downloads") == "share it freely. Downloads")
        #expect(LibraryTextFormatter.cleaned("Gutenberg 4015778The Consolation") == "Gutenberg The Consolation")
    }

    @Test("Names with interior capitals are not split")
    func keepsCamelCaseNames() {
        #expect(LibraryTextFormatter.cleaned("Father DeGrassa and MacArthur") == "Father DeGrassa and MacArthur")
    }

    @Test("Summa cross-references read as plain question and article numbers")
    func formatsSummaReferences() {
        #expect(LibraryTextFormatter.cleaned("shown (Q[3], A[4]).") == "shown (Q. 3, A. 4).")
        #expect(LibraryTextFormatter.cleaned("(QQ[2-26]) and (QQ[2]-26)") == "(QQ. 2–26) and (QQ. 2–26)")
    }

    @Test("The WEB book banner and chapter tags are removed")
    func stripsBibleBanner() {
        let text = "[JHN01] \u{FEFF}World English Bible Classic John 1 John < 1 > The Good News According to John"
        #expect(LibraryTextFormatter.cleaned(text) == "The Good News According to John")
    }

    @Test("A chapter number before verse one is dropped")
    func dropsLeadingChapterNumber() {
        #expect(LibraryTextFormatter.cleaned("3 1 But know this") == "1 But know this")
        #expect(LibraryTextFormatter.cleaned("3 men came") == "3 men came")
    }

    @Test("The WEB book footer and note list are removed")
    func stripsBibleFooter() {
        let text = "for every good work. 2 Timothy †3:16 or, Every writing inspired by God is "
            + "This is the Classic World English Bible with the full ecumenical book set. Frequently Asked "
            + "Questions Downloads Donations Public Domain"
        #expect(LibraryTextFormatter.cleaned(text) == "for every good work.")
        #expect(LibraryTextFormatter.cleaned("and†or, Every writing") == "and†or, Every writing")
    }

    @Test("Scripture citations link to the cited chapter")
    func linksCitations() throws {
        let attributed = attributed("It is written (2 Tim. 3:16): and (Ecclus. 3:22).", sourceID: "summa-theologica")
        let links = attributed.runs.compactMap { run in run.link.flatMap(LibraryTextFormatter.ScriptureTarget.init(url:)) }
        #expect(links == [
            .init(bookCode: "2TI", chapter: 3),
            .init(bookCode: "SIR", chapter: 3),
        ])
    }

    @Test("Douay Kings numbering applies only to Douay sources")
    func douayKings() {
        #expect(LibraryTextFormatter.bookCode(for: "3 Kings", douay: true) == "1KI")
        #expect(LibraryTextFormatter.bookCode(for: "1 Kings", douay: true) == "1SA")
        #expect(LibraryTextFormatter.bookCode(for: "1 Kings", douay: false) == "1KI")
    }

    @Test("A stray number before a book name is not linked as an ordinal")
    func strayOrdinal() throws {
        let attributed = attributed("article 4 Proverbs 3:5 says", sourceID: "summa-theologica")
        let linked = attributed.runs.filter { $0.link != nil }.map { String(attributed[$0.range].characters) }
        #expect(linked == ["Proverbs 3:5"])
    }

    @Test("Bible verse numbers are styled, not linked")
    func bibleVerses() {
        let attributed = attributed("with God. 2 The same was", sourceID: "web-bible")
        #expect(attributed.runs.allSatisfy { $0.link == nil })
        let styled = attributed.runs.filter { $0.baselineOffset != nil }.map { String(attributed[$0.range].characters) }
        #expect(styled == ["2"])
    }

    @Test("Scripture link URLs round-trip")
    func targetRoundTrip() {
        let target = LibraryTextFormatter.ScriptureTarget(bookCode: "JHN", chapter: 14)
        #expect(LibraryTextFormatter.ScriptureTarget(url: target.url) == target)
        #expect(LibraryTextFormatter.ScriptureTarget(url: URL(string: "https://example.com")!) == nil)
    }

    private func attributed(_ text: String, sourceID: String) -> AttributedString {
        LibraryTextFormatter.attributed(
            text,
            sourceID: sourceID,
            linkColor: .green,
            verseColor: .green,
            verseFont: .body
        )
    }
}
