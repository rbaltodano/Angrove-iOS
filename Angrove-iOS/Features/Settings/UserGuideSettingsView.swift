import SwiftUI

struct UserGuideSettingsView: View {
    var onSelectTopic: (UserGuideTopic.ID) -> Void
    var savedTerms: Binding<[String]> = .constant([])

    var body: some View {
        UserGuideWebsiteView(savedTerms: savedTerms, onSelectTopic: onSelectTopic)
            .ignoresSafeArea()
    }
}

/// One guide topic on its own page, pushed from `UserGuideSettingsView`.
struct UserGuideTopicView: View {
    let topic: UserGuideTopic
    @Binding var collectedDefinitions: [ConceptDefinition]
    var savedTerms: Binding<[String]> = .constant([])

    var body: some View {
        UserGuideWebsiteView(topicID: topic.id, savedTerms: savedTerms)
            .ignoresSafeArea()
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
                                .settingsText(.paragraph)
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

/// One block of a topic's technical details: a heading, then any of a paragraph, numbered steps,
/// a formula line, a small table, and a closing note.
struct UserGuideTechSection {
    var title: String
    var body: String? = nil
    var steps: [(label: String, text: String)] = []
    var formula: String? = nil
    var table: [[String]] = []
    var note: String? = nil
}

/// The collapsed "Show Technical Details" block under a topic.
private struct UserGuideTechnicalDetails: View {
    let sections: [UserGuideTechSection]
    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Button {
                SettingsHaptics.playSelection()
                withAnimation(.springStandard) { isOpen.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text(isOpen ? "Hide Technical Details" : "Show Technical Details")
                        .settingsText(.label)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .foregroundStyle(AngroveTheme.Colors.lightGreen)
                .frame(minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")

            if isOpen {
                VStack(alignment: .leading, spacing: 32) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        sectionView(section)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func sectionView(_ section: UserGuideTechSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .settingsText(.label)
                .foregroundStyle(AngroveTheme.Colors.headingText)
                .accessibilityAddTraits(.isHeader)
            if let body = section.body { paragraph(body) }
            if !section.steps.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(section.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.custom("Figtree-Bold", size: 12))
                                .foregroundStyle(AngroveTheme.Colors.lightGreen)
                                .frame(width: 24, height: 24)
                                .background(AngroveTheme.Colors.canvasSecondary, in: Circle())
                            paragraph("\(step.label). \(step.text)")
                        }
                    }
                }
            }
            if let formula = section.formula {
                Text(formula)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(AngroveTheme.Colors.headingText)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AngroveTheme.Colors.canvasSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            if !section.table.isEmpty { tableView(section.table) }
            if let note = section.note { paragraph(note) }
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(verbatim: text)
            .settingsText(.paragraph)
            .foregroundStyle(AngroveTheme.Colors.paragraphText)
            .lineSpacing(FlowLayout.rowSpacing)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func tableView(_ rows: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                        Text(verbatim: cell)
                            .font(.custom(index == 0 ? "Figtree-Bold" : "Figtree-Regular", size: 13))
                            .foregroundStyle(index == 0 ? AngroveTheme.Colors.headingText : AngroveTheme.Colors.paragraphText)
                            .frame(maxWidth: column == row.count - 1 ? .infinity : 64, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 10)
                if index < rows.count - 1 {
                    Divider().overlay(AngroveTheme.Colors.brownBorder)
                }
            }
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
                    .settingsText(.control)
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
                .settingsText(.label)
                .foregroundStyle(AngroveTheme.Colors.headingText)
                .accessibilityAddTraits(.isHeader)
            UserGuideText.text(text)
                .settingsText(.paragraph)
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
    /// Optional deeper explanation, collapsed under "Show Technical Details".
    var technical: [UserGuideTechSection] = []

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static func topic(id: ID) -> Self? { all.first { $0.id == id } }

    static let all: [Self] = [
        .init(
            id: "conversation", title: "Starting a Conversation", icon: "bubble.left.and.bubble.right",
            intro: "A conversation is where you ask Angrove a question and talk it through. Tap {plus|New Conversation} on Home or at the bottom of the menu to begin. Think of it as a patient study partner: you can ask anything, push back, and keep going.",
            overview: "Angrove answers your question in plain prose, and you can keep the discussion going with follow-ups for as long as you like.",
            instructions: "Type your question and send it. Beneath each answer, {doc.on.doc|Copy} copies the text and {arrow.trianglehead.2.clockwise|Regenerate} asks for a fresh answer. Follow up by asking for a clarification, an example, or an objection. Type /rename to name the conversation you’re in, or /rename followed by a name to set it immediately. In a very long conversation, type /compact to summarize older parts so Angrove can keep going (you still see everything), or /clear to start the conversation over.",
            example: "Ask “How does habit shape character?”, then ask for an everyday example. Answers can make mistakes, so check important claims against their sources."
        ),
        .init(
            id: "definitions", title: "Definitions & Saved Insights", icon: "bookmark",
            intro: "When Angrove uses a word that matters, it underlines it. Tap it and you get a short explanation of what that word means in your conversation, not a dictionary entry. If it’s worth keeping, save it. A saved definition is called an Insight, and your Insights become the building blocks of everything else in the app: the Insight Tree, Study, and Midpoints.",
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
            example: "Use the map to spot how several definitions belong to one larger question. Distance shows how related two ideas are, not whether they’re true or important.",
            demo: .tree,
            technical: [
                .init(title: "Meaning as numbers", body: "To compare ideas, Angrove turns each one into an embedding: a list of 384 numbers that describes what the text means rather than which words it uses. It embeds an Insight’s title and definition together with all-MiniLM-L6-v2, a small transformer that runs on your phone through Core ML. Texts that mean similar things get similar numbers, so “mercy” and “forgiveness” land close together even though they share no letters."),
                .init(title: "Cosine similarity", body: "Think of each embedding as an arrow in 384-dimensional space. Cosine similarity measures the angle between two arrows and ignores their length:", formula: "sim(a, b) = (a · b) / (‖a‖ ‖b‖)\nd(a, b) = 1 − sim(a, b)", note: "Arrows pointing the same way score 1, and unrelated ideas land near 0. Angrove uses d as the distance between two ideas. It ranks relatedness; it is not a probability."),
                .init(title: "Building the tree", steps: [
                    ("Seed", "After each answer, Gemma names the subject of that turn with a short label and summary. Angrove embeds “label. summary”, and the subject becomes a new Node Concept only if its similarity to every existing subject is below 0.60, so ordinary follow-ups don’t create duplicates."),
                    ("Attach", "A saved Insight is compared with each Node Concept, using the higher of its similarity to the Node’s members (their mean embedding) and to the Node’s seeded subject. It joins the best match at 0.40 or above; otherwise it starts a Node of its own. Membership is sticky: once placed, an Insight keeps its Node as others come and go."),
                    ("Merge", "Node Concepts found separately fold together when their members reach 0.65 similarity, or their subjects (“label. definition”) reach 0.75. The subject bar is higher because a shared word inflates the score. The pair that clears its bar by the widest margin merges first, and the larger Node keeps its name and place."),
                    ("Name", "Gemma names each automatic Node Concept with the nearest broader concept, in one to five words. A name that repeats a member’s title, wraps it (“About…”, “Study of…”), or is a catch-all like “Philosophy” or “Ideas” is rejected, and the model gets one corrective retry."),
                    ("Lay out", "Classical multidimensional scaling turns the table of distances between Node Concepts into positions, at 900 points of canvas per unit of distance. The third axis becomes depth. Each new layout is rotated to line up with the last one (a Procrustes fit), so adding a Node doesn’t spin the whole map; overlapping Nodes are then nudged apart."),
                    ("Connect", "An Insight’s connector is 150 + 180·n points long, where n is its distance to the Node’s centroid rescaled from 0 to 1 within that Node, so the closest member always sits nearest."),
                ], note: "Cutoffs at a glance: 0.40 an Insight joins a Node; below 0.60 a subject is new; 0.65 members merge; 0.75 subjects merge."),
                .init(title: "From distances to a map", body: "Multidimensional scaling squares the distance table, centers it, and keeps its largest eigenvectors as coordinates. When the distances are consistent with a flat map, the result reproduces them exactly; real embeddings rarely are, so the map is the closest fit and the third axis carries part of the rest as depth."),
            ]
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
            id: "midpoint", title: "Finding a Midpoint", icon: "graph.2d",
            intro: "Midpoint helps you find the idea that sits between two or more ideas you already have. It’s in the Insight Tree: select a few Insights and Angrove proposes a concept that connects them. It’s a good way to discover how two ideas relate when you can’t quite put it into words.",
            overview: "Midpoint finds a concept between the ideas you select, leaning toward the ones you give more weight.",
            instructions: "In the tree, tap {circle.dashed|Select}, choose two to eight Insights or Node Concepts, then tap {graph.2d|Midpoint}. Change the percentages to lean toward the ideas that matter most, then tap {arrow.down|Place} to add the result to your tree.",
            example: "Try a Midpoint between “justice” and “mercy” to see how they meet. The result depends on the ideas you choose and how you balance them.",
            demo: .midpoint,
            technical: [
                .init(title: "The computation", body: "This is what the app actually computes when you tap Place.", steps: [
                    ("Embed", "Each source’s title and definition are joined, split into WordPiece tokens (up to 128), and run through all-MiniLM-L6-v2, a six-layer transformer running on device through Core ML. Its token outputs are mean-pooled into one 384-dimensional vector v. An Insight’s stored embedding is reused when it came from the same model version."),
                    ("Normalize", "âᵢ = vᵢ / ‖vᵢ‖, so every source lies on the unit sphere and only its direction counts."),
                    ("Weight", "Your percentages become wᵢ = pᵢ / Σp, with negatives clipped to zero, across two to eight sources."),
                    ("Center", "s = Σ wᵢâᵢ, then ĉ = s / ‖s‖."),
                    ("Generate", "Gemma 4 E4B, on device, receives each source’s title, definition, and weight, and returns five candidate Insights as JSON."),
                    ("Select", "Each candidate is embedded the same way, giving êⱼ, and Angrove keeps the one that minimizes dⱼ = 1 − ĉ · êⱼ. If any embedding fails, it falls back to the model’s first candidate."),
                ], formula: "ĉ = Σ wᵢâᵢ / ‖Σ wᵢâᵢ‖\nj* = argminⱼ (1 − ĉ · êⱼ)"),
                .init(title: "Why ‖s‖ is less than 1", body: "A weighted sum of unit vectors lands inside the sphere, on the chord between them. Its length measures how much the sources agree: identical sources give ‖s‖ = 1, and two sources at angle φ, weighted 50/50, give ‖s‖ = cos(φ/2). Normalizing throws that length away and keeps only the direction."),
                .init(title: "Not quite linear in the weights", body: "Normalizing a weighted sum (nlerp) is not the same as moving along the arc in proportion to the weights (slerp). For example, 30% of the way from â₁ to â₂ lands at 27.0° rather than 28°. The two agree exactly at 50/50, and the gap grows as the sources move apart."),
                .init(title: "Cosine is a dot product here", body: "Because ĉ and every êⱼ have length 1, cos θ = ĉ · êⱼ, so ranking by cosine distance is ranking by angle. No single one of the 384 dimensions means anything on its own; only the angles between vectors do."),
                .init(title: "Why the model writes first", body: "ĉ is a direction, not text, and there is no decoder from MiniLM’s space back into language. So Angrove asks the language model to propose wording and uses the embedding space to judge which proposal lands closest."),
            ]
        ),
        .init(
            id: "organization", title: "Organizing Your Work", icon: "folder",
            intro: "As your conversations add up, two places help you keep them in order. {text.word.spacing|Conversations} in the menu lists everything you’ve discussed, and {square.stack|Study Topics} lets you group conversations about the same subject, like chapters of a notebook.",
            overview: "Conversations helps you find and tidy past discussions. Study Topics collects related conversations, and their saved Insights, in one place. Each Study Topic also has its own Insight Tree that gathers every Insight you saved in any of its conversations, clustered and laid out just like a conversation’s tree, so you can see a whole subject across many discussions.",
            instructions: "Open {text.word.spacing|Conversations} to search, rename, pin, move to a Study Topic, or delete a conversation. Open {square.stack|Study Topics} to create a topic, give it a short description, and add conversations to it. Inside a topic, tap {point.3.connected.trianglepath.dotted|Insight Tree} at the top right, or swipe left, to open its tree; swipe right to return.",
            example: "Create a Study Topic called “Ethics” and collect conversations about virtue, conscience, and responsibility; its Insight Tree then shows how the terms you saved in each one connect. Pin a discussion you want to come back to soon."
        ),
        .init(
            id: "library", title: "Using the Library", icon: "books.vertical",
            intro: "The Library holds the original texts Angrove draws on when it answers, like Scripture and the writings of the Church Fathers. Open {books.vertical|Library} from the menu to read them yourself. It’s separate from your Insights, which are the definitions you saved.",
            overview: "The Library lets you read the sources behind Angrove’s answers in their own words.",
            instructions: "Open {books.vertical|Library} from the menu. Browse the works or search by title or subject, then open a work to read it. The Passage of the Day is an easy place to start.",
            example: "Read a source passage alongside a discussion to check the author’s own wording and context.",
            technical: [
                .init(title: "Finding the right passage", body: "The Library holds 51,836 passages from 37 works, averaging about 970 characters each. Every passage was embedded ahead of time with the same MiniLM model, and the vectors ship with the app as a 79.6 MB file of 384-number rows that is memory-mapped rather than loaded. When you ask a question, Angrove embeds it and takes its dot product with every row, using Apple’s Accelerate library. Because the vectors are normalized, that dot product is the cosine similarity. Scanning all of them takes less time than writing the answer, so no approximate index is needed."),
                .init(title: "Layers before search", steps: [
                    ("Citations", "A named chapter like “John 14” is a lookup, not a search: the corpus is indexed by its own chapter tags, and one passage is taken from each cited chapter before a second from any."),
                    ("Known sections", "Questions that name a known section, or ask what a term means, go first to that section or to the Summa article that defines the term."),
                    ("Named works", "When a question names a work, such as the Didache, ranking happens inside that work, and passages that contain the question’s key terms rank first."),
                    ("Search", "Any slots still open, of the three references an answer can carry, go to semantic search across the whole Library. It ranks four candidates per open slot, because several chunks of one Summa article count only once and are replaced by Aquinas’s own answer from that article."),
                ]),
                .init(title: "Two cutoffs, not one", body: "A passage from semantic search is used only if its distance from your question is small enough. One cutoff can’t do both jobs: a bar loose enough to find the Good Samaritan also admits Livy on the Greek city of Nicaea when you ask about the Council of Nicaea, at 0.446. So the bar depends on what earlier layers found. Searching on its own, a passage needs a distance of 0.45 or less. Next to a citation or known section that already answered, extra passages must reach 0.38, so weak matches can’t pad a confident answer."),
                .init(title: "How 0.45 was chosen", body: "The cutoff was swept against 56 test questions, including ones the Library shouldn’t answer at all:", table: [
                    ["Cutoff", "Correct", "None found", "Note"],
                    ["0.38", "61%", "17", "Tuned on doctrinal questions only; missed the Lord’s Prayer and the prodigal son"],
                    ["0.45", "75%", "7", "Still screens every out-of-scope question"],
                    ["0.50", "Higher", "—", "Starts grounding “how do I bake sourdough bread”"],
                ], note: "When nothing clears the bar, Angrove answers without sources. That is the safer failure: an answer with no citation is better than one grounded in the wrong text."),
            ]
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
            overview: "Your conversations and Insights are stored only on your phone, and the model runs on it too.",
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
