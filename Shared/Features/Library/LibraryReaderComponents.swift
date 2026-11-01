import SwiftUI

/// How far a reading aloud has reached into a paragraph: words before `readBefore` are read
/// and `active`, if any, is being said.
struct LibrarySpeechState: Equatable {
    var readBefore = 0
    var active: Int?
    static let none = LibrarySpeechState()
}

// Reader pieces shared by the iPhone and Mac Library. Each platform supplies its own
// `LibrarySelectionText` for native selection menus.

struct LibraryReaderHeader: View {
    let subject: String
    let title: String
    let context: String
    let isListening: Bool
    let onListen: () -> Void

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
            Button(action: onListen) {
                HStack(spacing: 8) {
                    Image(systemName: isListening ? "pause.fill" : "speaker.wave.2.fill")
                        .angroveIcon(.small)
                    Text(isListening ? "Pause" : "Listen")
                        .font(.custom("Figtree-Bold", size: 14))
                }
                .foregroundStyle(AngroveTheme.Colors.lightGreen)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(AngroveTheme.Colors.canvasSecondary, in: Capsule())
                .overlay(Capsule().stroke(AngroveTheme.Colors.controlBorder, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isListening ? "Pause listening" : "Listen to this page")
            OrnamentRule()
                .padding(.top, 8)
        }
    }
}

struct LibraryTextSection: View {
    let title: String
    let passages: [LibraryPassage]
    let sourceID: String
    var speechKey = ""
    var highlightedChunkIndex: Int?
    let isVisible: Bool
    let onOpenScripture: (LibraryTextFormatter.ScriptureTarget) -> Void
    let onAsk: (String) -> Void
    let onClip: (String) -> Void
    var onReadFromHere: (Int, Int) -> Void = { _, _ in }
    @AppStorage("aquinas.settings.conversationFontSize")
    private var conversationFontSize: ConversationFontSizeOption = .small
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
                ForEach(LibraryTextFormatter.readablePassages(passages)) { passage in
                    VStack(alignment: .leading, spacing: 8) {
                    if let bookmark = LibraryListeningStore.shared.bookmark(for: sourceID),
                       bookmark.progress < 1, bookmark.readerChunkIndex == passage.chunkIndex,
                       ResponseSpeechPlayer.shared.activeLibraryWorkID != sourceID || ResponseSpeechPlayer.shared.isPaused {
                        Label("Last listened here", systemImage: "bookmark.fill")
                            .font(AngroveTheme.Typography.uiLabel)
                            .foregroundStyle(AngroveTheme.Colors.lightGreen)
                    }
                    LibraryParagraph(
                        text: LibraryTextFormatter.attributed(
                            passage.text,
                            sourceID: sourceID,
                            linkColor: AngroveTheme.Colors.lightGreen,
                            verseColor: AngroveTheme.Colors.lightGreen,
                            verseFont: .custom("Figtree-Bold", size: max(9, conversationFontSize.pointSize - 4))
                        ),
                        fontName: responseFont == .sans ? "Figtree-Regular" : "LibreBaskerville-Regular",
                        fontSize: conversationFontSize.pointSize,
                        isHighlighted: passage.chunkIndex == highlightedChunkIndex,
                        speechKey: speechKey,
                        chunkIndex: passage.chunkIndex,
                        sourceID: sourceID,
                        onAsk: onAsk,
                        onClip: onClip,
                        onReadFromHere: { onReadFromHere(passage.chunkIndex, $0) },
                        onOpenURL: { url in
                            guard let target = LibraryTextFormatter.ScriptureTarget(url: url) else { return false }
                            onOpenScripture(target)
                            return true
                        }
                    )
                    }
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
struct LibraryParagraph: View {
    let text: AttributedString
    let fontName: String
    let fontSize: CGFloat
    let isHighlighted: Bool
    var speechKey = ""
    var chunkIndex = 0
    var sourceID = ""
    let onAsk: (String) -> Void
    let onClip: (String) -> Void
    let onReadFromHere: (Int) -> Void
    let onOpenURL: (URL) -> Bool
    private var speech: ResponseSpeechPlayer { .shared }
    @State private var activeWordRect: CGRect?

    init(
        text: AttributedString, fontName: String, fontSize: CGFloat, isHighlighted: Bool,
        speechKey: String, chunkIndex: Int, sourceID: String,
        onAsk: @escaping (String) -> Void, onClip: @escaping (String) -> Void,
        onReadFromHere: @escaping (Int) -> Void,
        onOpenURL: @escaping (URL) -> Bool
    ) {
        self.onReadFromHere = onReadFromHere
        self.text = text
        self.fontName = fontName
        self.fontSize = fontSize
        self.isHighlighted = isHighlighted
        self.speechKey = speechKey
        self.chunkIndex = chunkIndex
        self.sourceID = sourceID
        self.onAsk = onAsk
        self.onClip = onClip
        self.onOpenURL = onOpenURL
    }

    /// Highlights belong to live listening; saved positions only supply the bookmark marker.
    private var speechState: LibrarySpeechState {
        guard speech.activeLibraryWorkID == sourceID,
              speech.phase != .idle, !speech.isPaused,
              let active = speech.activeWord ?? speech.firstWord else { return .none }
        let base = chunkIndex * LibrarySpeech.wordsPerChunk
        if active < base { return .none }
        if active >= base + LibrarySpeech.wordsPerChunk { return .init(readBefore: Int.max, active: nil) }
        return .init(readBefore: active - base, active: active - base)
    }

    var body: some View {
        LibrarySelectionText(
            text: text,
            onAsk: onAsk,
            onClip: onClip,
            onOpenURL: onOpenURL,
            textColor: isHighlighted ? AngroveTheme.Colors.primaryReadable : AngroveTheme.Colors.paragraphText,
            fontName: fontName,
            fontSize: fontSize,
            speechState: speechState,
            speechChunkIndex: chunkIndex,
            sourceID: sourceID,
            onReadFromHere: onReadFromHere,
            onActiveWordRect: { rect in
                if activeWordRect != rect { activeWordRect = rect }
            }
        )
        .overlay(alignment: .topLeading) {
            // Marks where the word being read sits, so the page can scroll to it.
            if speechState.active != nil, let rect = activeWordRect {
                Color.clear
                    .frame(width: 1, height: max(rect.height, 1))
                    .offset(y: rect.minY)
                    .id(ReadingScroll.activeWordID)
            }
        }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(isHighlighted ? 24 : 0)
            .background {
                if isHighlighted {
                    let shape = RoundedRectangle(cornerRadius: AngroveTheme.Spacing.cardRadius, style: .continuous)
                    shape.fill(AngroveTheme.Colors.canvasSecondary).overlay(shape.stroke(AngroveTheme.Colors.quietBorder, lineWidth: 1))
                }
            }
    }
}

struct LibraryContentsCard: View {
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

struct LibraryContentsBreadcrumb: View {
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
                        .angroveIcon(.xSmall)
                        .foregroundStyle(AngroveTheme.Colors.placeholderText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ContentsRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                HStack(spacing: 4) {
                    if isSelected {
                        Image(systemName: "chevron.right").angroveIcon(.xSmall, .strong).foregroundStyle(AngroveTheme.Colors.lightGreen).transition(.scale.combined(with: .opacity))
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
