import Foundation

nonisolated enum DailyQuestionWidgetLink {
    static let url = URL(string: "angrove://question-of-the-day")!

    static func matches(_ candidate: URL) -> Bool {
        candidate == url
    }
}
