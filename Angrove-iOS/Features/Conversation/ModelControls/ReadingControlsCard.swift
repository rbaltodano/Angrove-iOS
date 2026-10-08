//
//  ReadingControlsCard.swift
//  Angrove-iOS
//

import SwiftUI

/// The card opened from the Model Controls speaker button while a response is read aloud:
/// the conversation's name over a single line of the text that scrolls with the reading.
struct ReadingControlsCard: View {
    private var speech = ResponseSpeechPlayer.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openReadingConversation) private var openReadingConversation
    @AppStorage("aquinas.settings.responseFont") private var responseFont: ConversationFontOption = .serif
    @AppStorage("aquinas.settings.conversationFontSize") private var fontSize: ConversationFontSizeOption = .medium
    @State private var isUserScrolling = false
    @State private var resumeFollowing: Task<Void, Never>?

    init() {}

    private var title: String {
        speech.nowPlayingTitle.isEmpty ? "Angrove" : speech.nowPlayingTitle
    }

    /// Words with something to say; citation chips have no place in a line of text.
    private var words: [SpokenUnit.Word] {
        speech.readingWords.filter { word in
            if let link = ParsedInsightLink(token: word.token), link.isCitation { return false }
            return SpokenUnit.weight(of: word.token) > 0
        }
    }

    var body: some View {
        Group {
            if speech.isReadingCardCollapsed { collapsedCard } else { expandedCard }
        }
        .accessibilityElement(children: .contain)
    }

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("READING")
                        .font(.custom("Figtree-Bold", size: 10))
                        .tracking(1.2)
                        .foregroundStyle(AngroveTheme.Colors.accentGreen)

                    Button {
                        guard let id = speech.activeConversationID else { return }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.65)
                        openReadingConversation(id)
                    } label: {
                        Text(title)
                            .font(.custom("LibreBaskerville-Regular", size: 20))
                            .foregroundStyle(AngroveTheme.Colors.headingText)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens this conversation")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 0) {
                    playPauseButton
                    stopButton
                    sizeButton
                }
            }

            transcript(masksTrailingEdge: true)
                .padding(.horizontal, -32)
        }
        .padding(32)
        .frame(width: 355)
        .background(AngroveTheme.Colors.canvasSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(AngroveTheme.Colors.darkBrown.opacity(0.08), lineWidth: 1)
        )
    }

    /// Just the line of text, with the buttons laid over its trailing end on a strong fade.
    private var collapsedCard: some View {
        ZStack(alignment: .trailing) {
            transcript(masksTrailingEdge: false)

            LinearGradient(
                stops: [
                    .init(color: AngroveTheme.Colors.canvasSecondary.opacity(0), location: 0),
                    .init(color: AngroveTheme.Colors.canvasSecondary, location: 0.34),
                    .init(color: AngroveTheme.Colors.canvasSecondary, location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 190)
            .allowsHitTesting(false)

            HStack(spacing: 0) {
                playPauseButton
                stopButton
                sizeButton
            }
            .padding(.trailing, 10)
        }
        .padding(.vertical, 12)
        .frame(width: 355)
        .background(AngroveTheme.Colors.canvasSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(AngroveTheme.Colors.controlBorder, lineWidth: 1)
        )
    }

    /// Shrinks to the strip, or expands back; the choice is kept for later readings.
    private var sizeButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.65)
            let collapses = !speech.isReadingCardCollapsed
            withAnimation(.springStandard) { speech.setReadingCardCollapsed(collapses) }
        } label: {
            Image(systemName: speech.isReadingCardCollapsed
                  ? "arrow.up.left.and.arrow.down.right"
                  : "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AngroveTheme.Colors.placeholderText)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(speech.isReadingCardCollapsed ? "Expand reading card" : "Collapse reading card")
    }

    private var playPauseButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.65)
            if speech.isPaused { speech.resume() } else { speech.pause() }
        } label: {
            Image(systemName: speech.isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AngroveTheme.Colors.accentGreen)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(speech.isPaused ? "Resume reading" : "Pause reading")
    }

    private var stopButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.65)
            withAnimation(.springStandard) { speech.stop() }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AngroveTheme.Colors.placeholderText)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop reading")
    }

    /// One line of the response, scrolled sideways. It follows the reading until the reader
    /// takes hold of it, and resumes following a moment after they let go.
    private func transcript(masksTrailingEdge: Bool) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 7) {
                    ForEach(words, id: \.index) { word in
                        wordView(word).id(word.index)
                    }
                }
                .padding(.horizontal, 140)
            }
            .onScrollPhaseChange { _, phase in
                switch phase {
                case .interacting, .decelerating:
                    isUserScrolling = true
                    resumeFollowing?.cancel()
                case .idle:
                    guard isUserScrolling else { return }
                    resumeFollowing = Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        guard !Task.isCancelled else { return }
                        isUserScrolling = false
                        follow(speech.activeWord, with: proxy)
                    }
                default:
                    break
                }
            }
            .onChange(of: speech.activeWord) { _, word in
                follow(word, with: proxy)
            }
            .onAppear {
                follow(speech.activeWord, with: proxy, animated: false)
            }
        }
        .frame(height: fontSize.pointSize + 14)
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.24),
                    .init(color: .black, location: masksTrailingEdge ? 0.76 : 1),
                    .init(color: masksTrailingEdge ? .clear : .black, location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            )
        }
    }

    private func wordView(_ word: SpokenUnit.Word) -> some View {
        let text = Text(Self.displayText(word.token))
            .font(responseFont.textFont(size: fontSize))
        let speechText = speech.activeText ?? ""
        return text
            .foregroundColor(AngroveTheme.Colors.bodyText)
            .fixedSize()
            .spokenWordFill(index: word.index, speechText: speechText, fill: text)
            .spokenWordLift(index: word.index, speechText: speechText)
            .contentShape(Rectangle())
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
                resumeFollowing?.cancel()
                isUserScrolling = false
                speech.seek(toWord: word.index)
            }
    }

    private func follow(_ word: Int?, with proxy: ScrollViewProxy, animated: Bool = true) {
        guard !isUserScrolling, let word else { return }
        withAnimation(animated && !reduceMotion ? .easeOut(duration: 0.3) : nil) {
            proxy.scrollTo(word, anchor: .center)
        }
    }

    /// The token as it reads: Insight links show their title, emphasis marks are dropped.
    private static func displayText(_ token: String) -> String {
        token
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "*", with: "")
    }
}

/// The Reading card's speaker button for pages whose own controls do not carry one. Opening the
/// card closes any other card the page has open.
struct ReadingSpeakerButton: View {
    var closeOthers: () -> Void = {}

    private var speech = ResponseSpeechPlayer.shared

    init(closeOthers: @escaping () -> Void = {}) {
        self.closeOthers = closeOthers
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.7)
            withAnimation(.springStandard) {
                if !speech.isReadingCardOpen, !speech.isReadingCardCollapsed { closeOthers() }
                speech.isReadingCardOpen.toggle()
            }
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AngroveTheme.Colors.accentGreen)
                .symbolEffect(
                    .variableColor.iterative,
                    isActive: speech.phase == .speaking && !speech.isPaused
                )
                .frame(height: 16, alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reading controls")
    }
}
