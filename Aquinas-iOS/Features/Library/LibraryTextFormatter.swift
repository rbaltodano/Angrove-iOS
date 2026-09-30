//
//  LibraryTextFormatter.swift
//  Aquinas-iOS
//

import SwiftUI

/// Tidies corpus text for reading. The bundled `passages.json` stays untouched because its
/// order and wording back the precomputed retrieval embeddings; cleanup happens only on display.
nonisolated enum LibraryTextFormatter {
    static let scriptureScheme = "aquinas-library"

    /// A scripture chapter a reader link points at, e.g. `aquinas-library://scripture/JHN/3`.
    struct ScriptureTarget: Equatable {
        let bookCode: String
        let chapter: Int

        var url: URL {
            URL(string: "\(LibraryTextFormatter.scriptureScheme)://scripture/\(bookCode)/\(chapter)")!
        }

        init(bookCode: String, chapter: Int) {
            self.bookCode = bookCode
            self.chapter = chapter
        }

        init?(url: URL) {
            guard url.scheme == LibraryTextFormatter.scriptureScheme, url.host() == "scripture" else { return nil }
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count == 2, let chapter = Int(parts[1]) else { return nil }
            self.init(bookCode: parts[0], chapter: chapter)
        }
    }

    // MARK: - Cleanup

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

    /// Ordered cleanup rules; each pattern is compiled once.
    private static let cleanupRules: [(NSRegularExpression, String)] = [
        (regex("[\\u200B-\\u200D\\uFEFF]"), ""),
        // Bible chapter tags ("[JHN01]") and Wikisource paths ("[The Prince (Marriott)/Chapter 1]").
        (regex("\\[[0-9A-Z]{3}\\d{2,3}\\]"), ""),
        (regex("\\[[^\\]\\[]{1,120}/[^\\]\\[]{1,120}\\]"), ""),
        // The WEB export repeats its banner at each book: "World English Bible Classic John 1 John < 1 >".
        (regex("World English Bible Classic .{0,80}?< ?\\d+ ?>"), ""),
        (regex("< ?\\d{1,3} ?>"), ""),
        // A chapter number left before verse one: "3 1 But know this".
        (regex("^\\d{1,3} (?=1 \\p{L})"), ""),
        // The WEB closes each book with its note list ("2 Timothy †3:16 or, …") and a site footer.
        (regex("(?s)\\b(?:[1-4] )?[A-Z][a-z]+(?: of [A-Z][a-z]+)? [†‡§]\\d{1,3}:\\d{1,3}.*$"), ""),
        (regex("This is the Classic World English Bible with the full ecumenical book set\\..*?Donations(?: Public Domain)?"), ""),
        (regex("^Public Domain$"), ""),
        (regex("<?https?://[^\\s>]+>?\\.?"), ""),
        (regex("\\bDigitized by \\S+"), ""),
        // New Advent site chrome captured with the Church Fathers pages.
        (regex("CHURCH FATHERS:[^()]{0,120}\\([^)]{0,60}\\)"), ""),
        (regex("Search:\\s*Submit\\s+Search\\s+Home\\s+Encyclopedia\\s+Summa\\s+Fathers\\s+Bible\\s+Library(?:\\s+[A-Z]\\b)*"), ""),
        (regex("Please help support the mission of New Advent.{0,200}?\\$19\\.99\\.{0,3}"), ""),
        // Wikipedia/Wikisource editing marks.
        (regex("\\[(?:edit|new \\d+|[A-Za-z])\\]|↑"), ""),
        // Catalogue IDs fused onto the next word: "4015778The Consolation".
        (regex("\\b\\d{5,}(?=\\p{Lu})"), ""),
        // Section numbers fused onto the next word: "2For instance".
        (regex("\\b(\\d{1,3})(?=\\p{Lu}\\p{Ll})"), "$1 "),
        (regex("(\\w) ([;,])"), "$1$2"),
        // Summa cross-references: "Q[3], A[4]" reads as "Q. 3, A. 4"; "QQ[2-26]" as "QQ. 2–26".
        (regex("\\b(QQ?)\\[(\\d+)\\]-(\\d+)"), "$1. $2–$3"),
        (regex("\\b(QQ?)\\[(\\d+)-(\\d+)\\]"), "$1. $2–$3"),
        (regex("\\b(QQ?|A|Obj)\\[(\\d+)\\]"), "$1. $2"),
        // Numeric footnote markers whose notes the corpus does not carry: "declared[1] to be".
        (regex("\\[\\d{1,3}\\]"), ""),
        // Line-end hyphenation from scanned editions: "be- cause", "Di- onysius".
        (regex("(\\p{Ll})- (\\p{Ll})"), "$1$2"),
        // Words fused where a line or heading break was lost: "Questions" + "The".
        (regex("([a-z][.!?;:])([A-Z][a-z])"), "$1 $2"),
        (regex("(\\p{Ll}{4,})(\\p{Lu}\\p{Ll})"), "$1 $2"),
        (regex("[ \\t]{2,}"), " "),
    ]

    static func cleaned(_ text: String) -> String {
        var result = text
        for (pattern, template) in cleanupRules {
            result = pattern.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: template
            )
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Styling

    /// Verse numbers in the WEB text: "…with God. 2 The same was…".
    private static let versePattern = regex("(?<=^|\\s)(\\d{1,3}) (?=[\\p{L}“‘\"(])")
    /// "2 Tim. 3:16", "Ecclus. 3:22", "Rom 8:28", "3 Kings 19:8".
    private static let citationPattern = regex("\\b((?:[1-4] )?[A-Z][a-z]{1,11})\\.? (\\d{1,3}):\\d{1,3}")

    /// Works citing the Douay-Rheims, where "1-4 Kings" are Samuel and Kings.
    private static let douaySources: Set<String> = [
        "summa-theologica", "roman-catechism-donovan", "council-of-trent", "baltimore-catechism-3",
    ]

    static func attributed(
        _ text: String,
        sourceID: String,
        linkColor: Color,
        verseColor: Color,
        verseFont: Font
    ) -> AttributedString {
        let clean = cleaned(text)
        var attributed = AttributedString(clean)
        let nsText = clean as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        if sourceID == "web-bible" {
            for match in versePattern.matches(in: clean, range: fullRange) {
                guard let range = Range(match.range(at: 1), in: clean),
                      let attributedRange = Range(range, in: attributed)
                else { continue }
                attributed[attributedRange].font = verseFont
                attributed[attributedRange].foregroundColor = verseColor
                attributed[attributedRange].baselineOffset = 4
            }
            return attributed
        }

        let douay = douaySources.contains(sourceID)
        for match in citationPattern.matches(in: clean, range: fullRange) {
            guard let bookRange = Range(match.range(at: 1), in: clean),
                  let chapterRange = Range(match.range(at: 2), in: clean),
                  let chapter = Int(clean[chapterRange]),
                  let whole = Range(match.range, in: clean)
            else { continue }
            let book = String(clean[bookRange])
            var linkStart = whole.lowerBound
            var code = bookCode(for: book, douay: douay)
            // "…article 4 Proverbs 3:5": a stray number read as a book ordinal.
            if code == nil, let space = book.firstIndex(of: " ") {
                code = bookCode(for: String(book[book.index(after: space)...]), douay: douay)
                linkStart = clean.index(bookRange.lowerBound, offsetBy: book.distance(from: book.startIndex, to: space) + 1)
            }
            guard let code, let attributedRange = Range(linkStart..<whole.upperBound, in: attributed) else { continue }
            attributed[attributedRange].link = ScriptureTarget(bookCode: code, chapter: chapter).url
            attributed[attributedRange].foregroundColor = linkColor
            attributed[attributedRange].underlineStyle = .single
        }
        return attributed
    }

    // MARK: - Book abbreviations

    static func bookCode(for name: String, douay: Bool) -> String? {
        let key = name.lowercased()
        if douay, let code = douayOnly[key] { return code }
        return abbreviations[key]
    }

    /// Douay numbering where it disagrees with modern names.
    private static let douayOnly: [String: String] = [
        "1 kings": "1SA", "2 kings": "2SA", "3 kings": "1KI", "4 kings": "2KI",
    ]

    private static let abbreviations: [String: String] = {
        let groups: [(String, [String])] = [
            ("GEN", ["gen", "gn", "genesis"]), ("EXO", ["ex", "exod", "exodus"]),
            ("LEV", ["lev", "levit", "leviticus"]), ("NUM", ["num", "numbers"]),
            ("DEU", ["deut", "dt", "deuteronomy"]), ("JOS", ["jos", "josh", "joshua", "josue"]),
            ("JDG", ["judg", "judges"]), ("RUT", ["ruth"]),
            ("1SA", ["1 sam", "1 samuel", "1 kgdms"]), ("2SA", ["2 sam", "2 samuel"]),
            ("1KI", ["1 kings", "1 kgs"]), ("2KI", ["2 kings", "2 kgs"]),
            ("1CH", ["1 chron", "1 chronicles", "1 paral", "1 paralip", "1 par"]),
            ("2CH", ["2 chron", "2 chronicles", "2 paral", "2 paralip", "2 par"]),
            ("EZR", ["ezra", "esdr", "esd"]), ("NEH", ["neh", "nehemiah"]),
            ("TOB", ["tob", "tobit", "tobias"]), ("JDT", ["judith", "jdt"]),
            ("EST", ["esth", "esther"]), ("JOB", ["job"]),
            ("PSA", ["ps", "psa", "psalm", "psalms"]), ("PRO", ["prov", "proverbs"]),
            ("ECC", ["eccles", "eccl", "ecclesiastes"]), ("SNG", ["cant", "canticle", "canticles", "song", "songs"]),
            ("WIS", ["wis", "wisd", "wisdom"]), ("SIR", ["ecclus", "sirach", "sir"]),
            ("ISA", ["is", "isa", "isaiah", "isaias"]), ("JER", ["jer", "jerem", "jeremiah", "jeremias"]),
            ("LAM", ["lam", "lamentations"]), ("BAR", ["bar", "baruch"]),
            ("EZK", ["ezech", "ezek", "ezekiel", "ezechiel"]), ("DAN", ["dan", "daniel"]),
            ("HOS", ["osee", "hos", "hosea"]), ("JOL", ["joel"]), ("AMO", ["amos"]),
            ("OBA", ["abdias", "obad", "obadiah"]), ("JON", ["jonas", "jonah"]),
            ("MIC", ["mic", "mich", "micah", "micheas"]), ("NAM", ["nahum", "nah"]),
            ("HAB", ["hab", "habac", "habakkuk"]), ("ZEP", ["soph", "zeph", "zephaniah"]),
            ("HAG", ["agg", "hag", "haggai"]), ("ZEC", ["zach", "zech", "zechariah"]),
            ("MAL", ["mal", "malach", "malachi", "malachias"]),
            ("1MA", ["1 mac", "1 mach", "1 macc", "1 maccabees"]), ("2MA", ["2 mac", "2 mach", "2 macc", "2 maccabees"]),
            ("1ES", ["3 esdras", "3 esdra"]), ("2ES", ["4 esdras", "4 esdra"]),
            ("MAT", ["mt", "mat", "matt", "matth", "matthew"]), ("MRK", ["mk", "mark", "marc"]),
            ("LUK", ["lk", "luke", "luc"]), ("JHN", ["jn", "john", "joan"]),
            ("ACT", ["acts"]), ("ROM", ["rom", "romans"]),
            ("1CO", ["1 cor", "1 corinthians"]), ("2CO", ["2 cor", "2 corinthians"]),
            ("GAL", ["gal", "galatians"]), ("EPH", ["eph", "ephes", "ephesians"]),
            ("PHP", ["phil", "philip", "philippians"]), ("COL", ["col", "coloss", "colossians"]),
            ("1TH", ["1 thess", "1 thes", "1 thessalonians"]), ("2TH", ["2 thess", "2 thes", "2 thessalonians"]),
            ("1TI", ["1 tim", "1 timothy"]), ("2TI", ["2 tim", "2 timothy"]),
            ("TIT", ["tit", "titus"]), ("PHM", ["philem", "philemon"]),
            ("HEB", ["heb", "hebr", "hebrews"]), ("JAS", ["james", "jas", "jam", "jac"]),
            ("1PE", ["1 pet", "1 peter"]), ("2PE", ["2 pet", "2 peter"]),
            ("1JN", ["1 jn", "1 john", "1 joan"]), ("2JN", ["2 jn", "2 john"]), ("3JN", ["3 jn", "3 john"]),
            ("JUD", ["jude"]), ("REV", ["apoc", "apocalypse", "rev", "revelation"]),
        ]
        var table: [String: String] = [:]
        for (code, names) in groups {
            for name in names { table[name] = code }
        }
        return table
    }()
}
