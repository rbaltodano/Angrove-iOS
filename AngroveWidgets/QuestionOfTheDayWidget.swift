import SwiftUI
import WidgetKit

struct DailyQuestionEntry: TimelineEntry {
    let date: Date
    let question: String?
}

struct DailyQuestionProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyQuestionEntry {
        DailyQuestionEntry(date: .now, question: "What makes a life meaningful?")
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyQuestionEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyQuestionEntry>) -> Void) {
        // The app requests a reload whenever it publishes a newer question.
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    private func currentEntry() -> DailyQuestionEntry {
        DailyQuestionEntry(date: .now, question: DailyQuestionWidgetStore.load())
    }
}

struct DailyQuestionWidgetView: View {
    let entry: DailyQuestionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Question of the Day:")
                .font(AngroveTheme.WidgetTypography.heading)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if let question = entry.question {
                Text(question)
                    .font(AngroveTheme.WidgetTypography.question)
                    .lineLimit(2)
                    .truncationMode(.tail)
            } else {
                Text("Open Angrove for your question.")
                    .font(AngroveTheme.WidgetTypography.question)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
        .accessibilityElement(children: .combine)
        .widgetURL(DailyQuestionWidgetLink.url)
    }
}

@main
struct QuestionOfTheDayWidget: Widget {
    let kind = DailyQuestionWidgetStore.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyQuestionProvider()) { entry in
            DailyQuestionWidgetView(entry: entry)
        }
        .configurationDisplayName("Question of the Day")
        .description("The latest question from Angrove.")
        .supportedFamilies([.accessoryRectangular])
    }
}

#Preview(as: .accessoryRectangular) {
    QuestionOfTheDayWidget()
} timeline: {
    DailyQuestionEntry(date: .now, question: "What makes a life meaningful?")
    DailyQuestionEntry(date: .now, question: "How does your understanding of a meaningful life change when you consider your responsibilities to other people?")
    DailyQuestionEntry(date: .now, question: nil)
}
