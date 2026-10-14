import SwiftUI

nonisolated enum LibrarySubject: String, CaseIterable, Identifiable, Sendable {
    case scripture
    case earlyChristianity
    case councilsAndCreeds
    case catechismsAndConfessions
    case philosophy
    case history
    case politicalThought

    var id: Self { self }

    var title: String {
        switch self {
        case .scripture: "Sacred Scripture"
        case .earlyChristianity: "Early & Medieval Christianity"
        case .councilsAndCreeds: "Councils & Creeds"
        case .catechismsAndConfessions: "Catechisms & Confessions"
        case .philosophy: "Philosophy"
        case .history: "World History"
        case .politicalThought: "Political & Economic Thought"
        }
    }

    /// The broad discipline shown above a work's title in the reader.
    var generalTitle: String {
        switch self {
        case .scripture: "Scripture"
        case .earlyChristianity, .councilsAndCreeds, .catechismsAndConfessions: "Theology"
        case .philosophy: "Philosophy"
        case .history: "World History"
        case .politicalThought: "Political Thought"
        }
    }

    var systemImage: String {
        switch self {
        case .scripture: "book.closed"
        case .earlyChristianity: "building.columns"
        case .councilsAndCreeds: "person.3.sequence"
        case .catechismsAndConfessions: "list.bullet.rectangle"
        case .philosophy: "lightbulb"
        case .history: "hourglass"
        case .politicalThought: "scroll"
        }
    }

    static func of(workID: String) -> LibrarySubject {
        switch workID {
        case "web-bible":
            .scripture
        case "summa-theologica":
            .earlyChristianity
        case "council-of-trent", "ecumenical-creeds-schaff", "seven-ecumenical-councils":
            .councilsAndCreeds
        case "baltimore-catechism-3", "roman-catechism-donovan", "augsburg-confession",
             "belgic-confession", "heidelberg-catechism", "thirty-nine-articles",
             "westminster-confession":
            .catechismsAndConfessions
        case "aristotle-categories", "aristotle-metaphysics", "aristotle-nicomachean-ethics",
             "boethius-consolation":
            .philosophy
        case "bede-ecclesiastical-history", "eusebius-ecclesiastical-history",
             "gibbon-decline-and-fall", "herodotus-histories", "josephus-antiquities",
             "livy-history-of-rome", "plutarch-parallel-lives", "tacitus-annals-histories",
             "thucydides-peloponnesian-war":
            .history
        case "adam-smith-wealth-of-nations", "machiavelli-the-prince", "magna-carta",
             "us-constitution", "us-declaration-of-independence":
            .politicalThought
        default:
            .earlyChristianity
        }
    }
}
