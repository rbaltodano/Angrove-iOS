import Foundation

public nonisolated enum DailyQuestionWidgetLink {
    public static let url = URL(string: "angrove://question-of-the-day")!

    public static func matches(_ candidate: URL) -> Bool {
        candidate == url
    }
}
