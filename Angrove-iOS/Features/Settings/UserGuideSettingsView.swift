import SwiftUI

struct UserGuideSettingsView: View {
    var onSelectTopic: (UserGuideTopic.ID) -> Void

    var body: some View {
        UserGuidePageScaffold(
            title: "User Guide",
            subtitle: "A little guidance for asking deeper questions, saving ideas, and making connections."
        ) {
            VStack(alignment: .leading, spacing: 48) {
                UserGuideQuickStart()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Using Angrove")
                        .font(AngroveTheme.Typography.settingsHeading)
                        .foregroundStyle(AngroveTheme.Colors.headingText)
                        .accessibilityAddTraits(.isHeader)

                    SettingsControlCard {
                        ForEach(UserGuideTopic.all) { topic in
                            UserGuideTopicRow(topic: topic) {
                                SettingsHaptics.playSelection()
                                onSelectTopic(topic.id)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// One guide topic on its own page, pushed from `UserGuideSettingsView`.
struct UserGuideTopicView: View {
    let topic: UserGuideTopic
    @Binding var collectedDefinitions: [ConceptDefinition]

    var body: some View {
        UserGuidePageScaffold(title: topic.title, subtitle: topic.intro) {
            // An example is the main point of the topics that have one, so it leads the page.
            if let demo = topic.demo {
                UserGuideExampleView(example: demo, collectedDefinitions: $collectedDefinitions)
            }
            // The explanation reads as page text; cards are kept for the hands-on examples.
            VStack(alignment: .leading, spacing: 32) {
                UserGuideParagraph(title: "What it does", text: topic.overview)
                UserGuideParagraph(title: "How to use it", text: topic.instructions)
                UserGuideParagraph(title: "When it helps", text: topic.example)
            }
            if let laterDemo = topic.laterDemo {
                UserGuideExampleView(example: laterDemo, collectedDefinitions: $collectedDefinitions)
            }
        }
    }
}

/// Guide pages use the Study Topic header: a large leading title, an optional description under
/// it, and the same spacing above, between, and below.
private struct UserGuidePageScaffold<Content: View>: View {
    let title: LocalizedStringResource
    /// Guide markup; see `UserGuideText`.
    var subtitle: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            AngroveTheme.Colors.canvas
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(title)
                            .font(AngroveTheme.Typography.settingsGuideTitle)
                            .foregroundStyle(AngroveTheme.Colors.primaryReadable)
                            .lineSpacing(18)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)

                        if let subtitle {
                            UserGuideText.text(subtitle)
                                .font(AngroveTheme.Typography.settingsBody)
                                .foregroundStyle(AngroveTheme.Colors.paragraphText)
                                .lineSpacing(FlowLayout.rowSpacing)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 48) {
                        content
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The intro is a paragraph of its own, so the first section gets the same
                    // 48pt of room as every section after it.
                    .padding(.top, subtitle == nil ? 20 : 48)

                    Spacer(minLength: 80)
                }
                .padding(.horizontal, 24)
                // Matches a Study Topic title: 24 + 72 above its text view, plus its 12pt inset.
                .padding(.top, 108)
            }
        }
    }
}

private struct UserGuideQuickStart: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Your First Five Minutes")
                .font(AngroveTheme.Typography.settingsHeading)
                .foregroundStyle(AngroveTheme.Colors.headingText)
                .accessibilityAddTraits(.isHeader)
            UserGuideParagraph(title: "1. Ask a question", text: "Tap {plus|New Conversation} and type something you want to understand, like “What makes an action virtuous?” Then ask a follow-up as the idea develops.")
            UserGuideParagraph(title: "2. Save an idea", text: "Some words in an answer are underlined. Tap one to see what it means in your conversation, then tap {bookmark|Save} to keep it as an Insight.")
            UserGuideParagraph(title: "3. See the connections", text: "Tap {point.3.connected.trianglepath.dotted|Insight Tree} at the top of the conversation, or swipe left, to see your saved ideas mapped out together.")
        }
    }
}

private struct UserGuideTopicRow: View {
    let topic: UserGuideTopic
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: topic.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(topic.title)
                    .font(AngroveTheme.Typography.settingsBody)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(AngroveTheme.Colors.paragraphText)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens this guide")
    }
}

private struct UserGuideParagraph: View {
    let title: LocalizedStringResource
    /// Guide markup; see `UserGuideText`.
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AngroveTheme.Typography.settingsLabel)
                .foregroundStyle(AngroveTheme.Colors.headingText)
                .accessibilityAddTraits(.isHeader)
            UserGuideText.text(text)
                .font(AngroveTheme.Typography.settingsBody)
                .foregroundStyle(AngroveTheme.Colors.paragraphText)
                .lineSpacing(FlowLayout.rowSpacing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Guide copy names on-screen buttons as `{sf.symbol|Label}`. Each renders as the button's icon
/// followed by its name, both in light green, so readers can match the text to the screen.
enum UserGuideText {
    private static let buttonPattern = try! NSRegularExpression(pattern: #"\{([^|}]+)\|([^}]+)\}"#)

    static func text(_ markup: String) -> Text {
        var result = Text(verbatim: "")
        var cursor = markup.startIndex
        let range = NSRange(markup.startIndex..., in: markup)
        for match in buttonPattern.matches(in: markup, range: range) {
            guard let whole = Range(match.range, in: markup),
                  let icon = Range(match.range(at: 1), in: markup),
                  let label = Range(match.range(at: 2), in: markup) else { continue }
            result = result + Text(verbatim: String(markup[cursor..<whole.lowerBound]))
            result = result
                + Text(Image(systemName: String(markup[icon])))
                    .foregroundColor(AngroveTheme.Colors.lightGreen)
                + Text(verbatim: "\u{00A0}" + String(markup[label]))
                    .foregroundColor(AngroveTheme.Colors.lightGreen)
            cursor = whole.upperBound
        }
        return result + Text(verbatim: String(markup[cursor...]))
    }
}

/// Guide copy describes shipped behavior only. When a feature in
/// `Aquinas-Foundations/FUNCTIONALITY.md` changes, update the matching topic here. Body strings
/// use `UserGuideText` markup for buttons.
struct UserGuideTopic: Identifiable, Hashable {
    let id: String
    let title: LocalizedStringResource
    let icon: String
    /// Plain-language opener under the title: where the tool lives and why it's worth using.
    let intro: String
    let overview: String
    let instructions: String
    let example: String
    /// A hands-on example, for the few tools that are hidden or hard to picture from text.
    var demo: UserGuideExample? = nil
    /// A second example shown after the explanation, further down the page.
    var laterDemo: UserGuideExample? = nil

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static func topic(id: ID) -> Self? { all.first { $0.id == id } }

    static let all: [Self] = [
        .init(
            id: "conversation", title: "Starting a Conversation", icon: "bubble.left.and.bubble.right",
            intro: "A conversation is where you ask Angrove a question and talk it through. Tap {plus|New Conversation} on Home or at the bottom of the menu to begin. Think of it as a patient study partner: you can ask anything, push back, and keep going.",
            overview: "Angrove answers your question in plain prose, and you can keep the discussion going with follow-ups for as long as you like.",
            instructions: "Type your question and send it. Beneath each answer, {doc.on.doc|Copy} copies the text and {arrow.trianglehead.2.clockwise|Regenerate} asks for a fresh answer. Follow up by asking for a clarification, an example, or an objection. Type /rename to name this conversation, or /rename followed by a name to set it immediately. In a very long conversation, type /compact to summarize older parts so Angrove can keep going (you still see everything), or /clear to start the conversation over.",
            example: "Ask “How does habit shape character?”, then ask for an everyday example. Answers can make mistakes, so check important claims against their sources."
        ),
        .init(
            id: "definitions", title: "Definitions & Saved Insights", icon: "bookmark",
            intro: "When Angrove uses a word that matters, it underlines it. Tap it and you get a short explanation of what that word means in your conversation, not a dictionary entry. If it’s worth keeping, save it. A saved definition is called an Insight, and your Insights become the building blocks of everything else in the app: the Insight Tree, Midpoints, and your Insight Library.",
            overview: "An Insight is a definition you chose to keep. It explains a term in the context of the discussion where you found it, so it still makes sense when you come back to it later.",
            instructions: "Tap an underlined term in an answer. When its definition opens, tap {bookmark|Save} to keep it, or {arrow.turn.down.right|Quote} to ask about it in your next question. Saved Insights appear in {brain.head.profile|Insights} in the menu and in the conversation’s tree. Saving the same word from a different discussion adds its new meaning to the same card.",
            example: "Save “grace” while discussing theology, then return to it later without searching through the whole conversation.",
            demo: .definitions
        ),
        .init(
            id: "tree", title: "Understanding the Insight Tree", icon: "point.3.connected.trianglepath.dotted",
            intro: "Every conversation has an Insight Tree: a map of the ideas you’ve explored. Open it with {point.3.connected.trianglepath.dotted|Insight Tree} at the top of a conversation, or by swiping left. It shows how your saved Insights relate to one another, so you can see the shape of a subject instead of scrolling back through a long discussion.",
            overview: "The tree gathers your Insights around broader subjects called Node Concepts. Angrove adds a Node Concept when an answer opens up a new subject; Insights are only ever added by you.",
            instructions: "Drag to move around, pinch to zoom, and tap anything to read its card. Lines show which ideas are connected, and shorter lines mean the ideas are closer in meaning. {brain.head.profile|Insights} in the menu has a larger tree that brings together everything you’ve saved; accept its update prompt to add your latest bookmarks.",
            example: "Use the map to spot how several definitions belong to one larger question. Distance shows how related two ideas are, not whether they’re true or important."
        ),
        .init(
            id: "midpoint", title: "Finding a Midpoint", icon: "graph.2d",
            intro: "Midpoint helps you find the idea that sits between two or more ideas you already have. It’s in the Insight Tree: select a few Insights and Angrove proposes a concept that connects them. It’s a good way to discover how two ideas relate when you can’t quite put it into words.",
            overview: "Midpoint finds a concept between the ideas you select, leaning toward the ones you give more weight.",
            instructions: "In the tree, tap {circle.dashed|Select}, choose two to eight Insights or Node Concepts, then tap {graph.2d|Midpoint}. Change the percentages to lean toward the ideas that matter most, then tap {arrow.down|Place} to add the result to your tree.",
            example: "Try a Midpoint between “justice” and “mercy” to see how they meet. The result depends on the ideas you choose and how you balance them.",
            demo: .midpoint,
            laterDemo: .midpointThree
        ),
        .init(
            id: "study", title: "Studying a Concept in 3D", icon: "graph.3d",
            intro: "Study lifts one subject out of the Insight Tree so you can look at it on its own. In the tree, tap a Node Concept or an Insight, then tap {graph.3d|Study}. Its Insights spread out around it in 3D, which makes it easy to read them one at a time without the rest of the tree in the way.",
            overview: "Study shows one Node Concept and its Insights in 3D, and returns you to the same spot in the tree when you’re done.",
            instructions: "Drag the ring under the concept to spin it, drag anywhere else to move, and pinch to zoom. Tap an Insight to bring it forward and read its card, or tap the concept to go back to it. Tap {xmark|Exit} to return to the tree.",
            example: "Use Study when a subject has gathered several Insights and you want to read them together.",
            demo: .study
        ),
        .init(
            id: "organization", title: "Organizing Your Work", icon: "folder",
            intro: "As your conversations add up, two places help you keep them in order. {text.word.spacing|Conversations} in the menu lists everything you’ve discussed, and {square.stack|Study Topics} lets you group conversations about the same subject, like chapters of a notebook.",
            overview: "Conversations helps you find and tidy past discussions. Study Topics collects related conversations, and their saved Insights, in one place.",
            instructions: "Open {text.word.spacing|Conversations} to search, rename, pin, move to a Study Topic, or delete a conversation. Open {square.stack|Study Topics} to create a topic, give it a short description, and add conversations to it.",
            example: "Create a Study Topic called “Ethics” and collect conversations about virtue, conscience, and responsibility. Pin a discussion you want to come back to soon."
        ),
        .init(
            id: "library", title: "Using the Library", icon: "books.vertical",
            intro: "The Library holds the original texts Angrove draws on when it answers, like Scripture and the writings of the Church Fathers. Open {books.vertical|Library} from the menu to read them yourself. It’s separate from your Insights, which are the definitions you saved.",
            overview: "The Library lets you read the sources behind Angrove’s answers in their own words.",
            instructions: "Open {books.vertical|Library} from the menu. Browse the works or search by title or subject, then open a work to read it. The Passage of the Day is an easy place to start.",
            example: "Read a source passage alongside a discussion to check the author’s own wording and context."
        ),
        .init(
            id: "home", title: "Home & Question of the Day", icon: "sun.max",
            intro: "Home is the first page you see. Open it anytime with {house|Home} in the menu. It gathers ideas worth coming back to from your recent conversations, including a daily question to think about, so you can pick up where you left off.",
            overview: "The Question of the Day invites you to reflect on something unresolved from your recent conversations. Other cards appear when there’s something worth revisiting.",
            instructions: "Answer the Question of the Day to start a conversation about it; a new one appears later. Today in History offers a historical prompt, Loose Thread points to a subject in your tree that hasn’t connected to anything yet, Terms You Glossed Over shows a definition you looked up but never saved, and Quote From You shows something you wrote that stood out. Set a daily reminder in {gearshape|Settings} → Notifications.",
            example: "Tap Loose Thread to jump straight to that subject in its tree, or save a glossed-over term from its card. It’s normal for Home to show only a few cards when you’re just starting out."
        ),
        .init(
            id: "model-tasks", title: "Model Tasks", icon: "waveform",
            intro: "Angrove runs entirely on your phone, so it works on one thing at a time: answering a question, defining a word, updating your tree. Anything else you ask for waits in line. Model Tasks shows that line, so you can see what Angrove is doing and change what happens next. Open it by tapping the status button at the bottom of a conversation, which reads Idle or Thinking.",
            overview: "Model Tasks lists what Angrove has finished, what it’s working on now, and what’s waiting.",
            instructions: "Tap the status button to open Model Tasks. Tap {stop.circle.fill|Stop} on the running task to cancel it, tap {xmark|Remove} on a waiting task to take it out of line, or press and drag a waiting task to move it up or down. Finished tasks clear on their own shortly after everything is done.",
            example: "If you asked for several definitions and now want an answer first, drag your question to the front of the line. Stopping or removing a task never deletes anything you’ve already saved.",
            demo: .modelTasks
        ),
        .init(
            id: "personalization", title: "Personalizing Angrove", icon: "slider.horizontal.3",
            intro: "You can make Angrove more comfortable to read and tell it what to call you. Everything is in {gearshape|Settings}, at the bottom of the menu.",
            overview: "Settings controls how the app looks and how conversations read.",
            instructions: "Appearance switches between light and dark. Text & Display changes fonts, text size, and alignment. Model Behavior sets your name. App Experience sets your start screen and haptics, and Notifications sets reminders.",
            example: "Choose larger text for long reading sessions, or a serif font for responses."
        ),
        .init(
            id: "privacy", title: "Privacy & Your Data", icon: "lock.shield",
            intro: "Everything you do in Angrove stays on your phone. Your conversations, saved Insights, and the model that answers you are never sent to a server. {gearshape|Settings} → Privacy & Data is where you lock the app and back up or clear your data.",
            overview: "Your conversations and Insights are stored only on this device, and the model runs on it too.",
            instructions: "Turn on App Lock to require Face ID, and choose how soon it locks. Export Conversations saves your conversations to a file, and Import Conversations reads one back. Clear Insight Tree removes saved Insights and tree data but keeps your conversations.",
            example: "Export before importing: importing replaces your current conversations. An export holds conversations only, not Insights or settings, and it contains your discussion text, so keep it somewhere safe."
        )
    ]
}

#Preview("User Guide · Light") {
    UserGuideSettingsView(onSelectTopic: { _ in })
        .preferredColorScheme(.light)
}

#Preview("User Guide Topic · Dark") {
    UserGuideTopicView(topic: UserGuideTopic.all[0], collectedDefinitions: .constant([]))
        .preferredColorScheme(.dark)
}
