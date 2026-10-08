//
//  ResponseSpeechPlayer.swift
//  Angrove-iOS
//

import AVFoundation
import Observation
import os

/// Reads one model response aloud at a time. Each sentence is scheduled as soon as it is
/// synthesized, so playback starts after the first sentence rather than the whole answer.
///
/// Synthesized audio is kept for the length of the reading so the listener can scrub: the
/// player knows when each displayed word is spoken and can resume from any of them.
@Observable
final class ResponseSpeechPlayer {
    static let shared = ResponseSpeechPlayer()

    enum Phase: Equatable {
        case idle
        case preparing
        case speaking
    }

    /// The text currently being read, which identifies the response whose button is active.
    private(set) var activeText: String?
    private(set) var phase: Phase = .idle
    /// The displayed word (flat index within the response) being spoken, or scrubbed to.
    private(set) var activeWord: Int?
    /// The first displayed word of this reading; words before it were not read.
    private(set) var firstWord: Int?
    /// The conversation whose response is being read, for marking it in the sidebar.
    private(set) var activeConversationID: UUID?
    private(set) var isScrubbing = false
    private(set) var isPaused = false

    /// Seconds of audio a point of horizontal drag moves while scrubbing.
    static let scrubSecondsPerPoint = 0.04

    private struct Part {
        let unit: Int
        let weight: Double
        let phonemes: String
        var samples: [Float] = []
        var startFrame = 0
    }

    private struct PendingWord {
        let index: Int
        let unit: Int
        let startTarget: Double
        let endTarget: Double
    }

    private struct TimedWord {
        let index: Int
        let start: Double
        let end: Double
    }

    @ObservationIgnored private var engine: ParadeeSpeechEngine?
    @ObservationIgnored private var playback: Task<Void, Never>?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var runID = UUID()
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pendingBuffers = 0
    @ObservationIgnored private var isDoneScheduling = false

    @ObservationIgnored private var parts: [Part] = []
    @ObservationIgnored private var unitParts: [[Int]] = []
    @ObservationIgnored private var pendingWords: [PendingWord] = []
    @ObservationIgnored private var timedWords: [TimedWord] = []
    @ObservationIgnored private var spans: [Int: (start: Double, end: Double)] = [:]
    @ObservationIgnored private var synthesizedParts = 0
    @ObservationIgnored private var scheduledParts = 0
    @ObservationIgnored private var synthesizedFrames = 0
    @ObservationIgnored private var baseFrame = 0
    @ObservationIgnored private var lastFrame = 0
    @ObservationIgnored private var scrubFrame = 0
    @ObservationIgnored private var scrubOriginFrame = 0
    @ObservationIgnored private var nowPlayingTitle = ""
    @ObservationIgnored private var pendingConversationID: UUID?
    @ObservationIgnored private var lastNowPlayingUpdate = Date.distantPast

    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private let playerNode = AVAudioPlayerNode()
    @ObservationIgnored private let sampleRate = ParadeeSpeechEngine.sampleRate
    @ObservationIgnored private let format = AVAudioFormat(
        standardFormatWithSampleRate: ParadeeSpeechEngine.sampleRate, channels: 1
    )!
    @ObservationIgnored private let logger = Logger(subsystem: "com.ryanbaltodano.Aquinas-iOS", category: "Speech")

    private init() {
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            let shouldResume = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? false
            MainActor.assumeIsolated {
                if type == .began { self?.pause() } else if shouldResume { self?.resume() }
            }
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
            MainActor.assumeIsolated { self?.pause() }
        }
    }

    func phase(for text: String) -> Phase {
        activeText == text ? phase : .idle
    }

    /// Starts reading `text`, or stops if it is already being read. `units` carries the displayed
    /// words so they can be highlighted; without them `text` is read with no highlight.
    func toggle(_ text: String, units: [SpokenUnit] = [], source: SpeechSource = SpeechSource()) {
        if activeText == text {
            stop()
        } else {
            nowPlayingTitle = source.title
            pendingConversationID = source.conversationID
            speak(text, units: units.isEmpty ? [SpokenUnit(unhighlightedText: text)] : units)
        }
    }

    /// Starts reading `text` unless it is already being read.
    func toggleStarting(_ text: String, units: [SpokenUnit], source: SpeechSource = SpeechSource()) {
        guard activeText != text else { return }
        toggle(text, units: units, source: source)
    }

    /// Starts reading `text` at displayed word `index`, replacing any reading in progress.
    func read(_ text: String, units: [SpokenUnit], fromWord index: Int, source: SpeechSource = SpeechSource()) {
        let remaining = SpokenUnit.units(units, fromWord: index)
        guard !remaining.isEmpty else { return }
        nowPlayingTitle = source.title
        pendingConversationID = source.conversationID
        speak(text, units: remaining, firstWord: index)
    }

    func stop() {
        runID = UUID()
        generation += 1
        playback?.cancel()
        playback = nil
        ticker?.cancel()
        ticker = nil
        playerNode.stop()
        audioEngine.stop()
        parts = []
        unitParts = []
        pendingWords = []
        timedWords = []
        spans = [:]
        synthesizedParts = 0
        scheduledParts = 0
        synthesizedFrames = 0
        baseFrame = 0
        lastFrame = 0
        activeText = nil
        activeWord = nil
        firstWord = nil
        activeConversationID = nil
        isScrubbing = false
        isPaused = false
        phase = .idle
        SpeechNowPlaying.shared.clear()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Position

    /// Seconds into the reading, following the finger while scrubbing.
    var currentTime: Double { Double(currentFrame) / sampleRate }

    /// How far through `index` the reading is, 0...1, or nil if the word has no timing yet.
    func progress(ofWord index: Int) -> Double? {
        guard let span = spans[index] else { return nil }
        return min(1, max(0, (currentTime - span.start) / max(span.end - span.start, 0.01)))
    }

    private var currentFrame: Int {
        if isScrubbing { return scrubFrame }
        guard let nodeTime = playerNode.lastRenderTime, nodeTime.isSampleTimeValid,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return lastFrame }
        let played = Int(Double(playerTime.sampleTime) * sampleRate / max(playerTime.sampleRate, 1))
        lastFrame = min(max(baseFrame + played, 0), synthesizedFrames)
        return lastFrame
    }

    private func word(at time: Double) -> Int? {
        guard !timedWords.isEmpty else { return nil }
        var low = 0, high = timedWords.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if timedWords[mid].start <= time { low = mid } else { high = mid - 1 }
        }
        return timedWords[low].index
    }

    private func refreshActiveWord() {
        let next = word(at: currentTime)
        if next != activeWord { activeWord = next }
    }

    // MARK: - Scrubbing

    func beginScrub() {
        guard phase == .speaking, !isScrubbing else { return }
        scrubFrame = currentFrame
        scrubOriginFrame = scrubFrame
        playerNode.pause()
        isScrubbing = true
        refreshNowPlaying()
    }

    // MARK: - Transport

    func pause() {
        guard phase == .speaking, !isPaused else { return }
        isPaused = true
        if !isScrubbing { playerNode.pause() }
        refreshNowPlaying()
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        if !isScrubbing { playerNode.play() }
        refreshNowPlaying()
    }

    func skip(by seconds: Double) {
        guard phase == .speaking, !isScrubbing else { return }
        seek(toTime: currentTime + seconds)
    }

    func seek(toTime seconds: Double) {
        guard phase == .speaking, !isScrubbing, synthesizedFrames > 0 else { return }
        let frame = Int(seconds * sampleRate)
        seek(to: min(max(frame, 0), synthesizedFrames - 1))
        refreshActiveWord()
    }

    /// Publishes position to the Lock Screen when playing in the background is allowed.
    private func refreshNowPlaying() {
        guard AudioSettings.playsInBackground, activeText != nil, phase == .speaking else {
            SpeechNowPlaying.shared.clear()
            return
        }
        lastNowPlayingUpdate = Date()
        SpeechNowPlaying.shared.update(
            title: nowPlayingTitle.isEmpty ? "Angrove" : nowPlayingTitle,
            elapsed: currentTime,
            duration: Double(synthesizedFrames) / sampleRate,
            isPlaying: !isPaused && !isScrubbing
        )
    }

    func updateScrub(translation: CGFloat) {
        guard isScrubbing else { return }
        let delta = Int(Double(translation) * Self.scrubSecondsPerPoint * sampleRate)
        scrubFrame = min(max(scrubOriginFrame + delta, 0), max(synthesizedFrames - 1, 0))
        refreshActiveWord()
    }

    /// Resumes from the start of the word the cursor is on.
    func endScrub() {
        guard isScrubbing else { return }
        var frame = scrubFrame
        if let index = word(at: Double(frame) / sampleRate), let span = spans[index] {
            frame = Int(span.start * sampleRate)
        }
        isScrubbing = false
        seek(to: frame)
        refreshActiveWord()
        refreshNowPlaying()
    }

    private func seek(to frame: Int) {
        generation += 1
        let gen = generation
        playerNode.stop()
        baseFrame = frame
        lastFrame = frame
        pendingBuffers = 0
        let first = parts[..<synthesizedParts].lastIndex { $0.startFrame <= frame } ?? 0
        for index in first..<synthesizedParts {
            let offset = index == first ? max(0, frame - parts[index].startFrame) : 0
            enqueue(Array(parts[index].samples.dropFirst(offset)), generation: gen)
        }
        scheduledParts = synthesizedParts
        if !isPaused { playerNode.play() }
        finishIfDone()
    }

    // MARK: - Playback

    private func speak(_ text: String, units: [SpokenUnit], firstWord: Int? = nil) {
        stop()
        let id = runID
        activeText = text
        activeConversationID = pendingConversationID
        self.firstWord = firstWord
        phase = .preparing
        pendingBuffers = 0
        isDoneScheduling = false
        playback = Task { [weak self] in
            await self?.run(units, id: id)
        }
    }

    private func run(_ units: [SpokenUnit], id: UUID) async {
        do {
            let engine = try await loadedEngine()
            try await prepare(units, engine: engine)
            try Task.checkCancellation()

            let session = AVAudioSession.sharedInstance()
            // Ducking marks audio as transient, like a navigation prompt, which keeps it off the Lock
            // Screen. With background playback on, the reading behaves like a podcast instead.
            let options: AVAudioSession.CategoryOptions = AudioSettings.playsInBackground ? [] : [.duckOthers]
            try session.setCategory(.playback, mode: .spokenAudio, options: options)
            try session.setActive(true)
            try audioEngine.start()
            playerNode.play()
            startTicker(id)

            for index in parts.indices {
                let samples = try await engine.synthesize(phonemes: parts[index].phonemes)
                try Task.checkCancellation()
                parts[index].samples = samples
                parts[index].startFrame = synthesizedFrames
                synthesizedFrames += samples.count
                synthesizedParts = index + 1
                resolveWords()
                if !isScrubbing, scheduledParts == index {
                    enqueue(samples, generation: generation)
                    scheduledParts = index + 1
                }
                let isFirst = phase != .speaking
                phase = .speaking
                if isFirst || Date().timeIntervalSince(lastNowPlayingUpdate) > 1.5 { refreshNowPlaying() }
            }
            isDoneScheduling = true
            refreshNowPlaying()
            finishIfDone()
        } catch is CancellationError {
            // Stopped, or replaced by another response.
        } catch {
            logger.error("Speech failed: \(error.localizedDescription, privacy: .public)")
            if runID == id { stop() }
        }
    }

    /// Phonemizes every unit up front and lays out which parts of the audio each displayed word
    /// occupies, in the weighted space shared by the displayed and the normalized text.
    private func prepare(_ units: [SpokenUnit], engine: ParadeeSpeechEngine) async throws {
        for (unitIndex, unit) in units.enumerated() {
            var indices: [Int] = []
            var total = 0.0
            for sentence in await engine.sentences(for: unit.text) {
                let sentenceWeight = sentence.text.split(whereSeparator: \.isWhitespace)
                    .reduce(0.0) { $0 + SpokenUnit.weight(of: String($1)) }
                let phonemeCount = max(sentence.chunks.reduce(0) { $0 + $1.count }, 1)
                for chunk in sentence.chunks {
                    let weight = sentenceWeight * Double(chunk.count) / Double(phonemeCount)
                    indices.append(parts.count)
                    parts.append(Part(unit: unitIndex, weight: weight, phonemes: chunk))
                    total += weight
                }
            }
            unitParts.append(indices)

            let displayWeights = unit.words.map { SpokenUnit.weight(of: $0.token) }
            let displayTotal = displayWeights.reduce(0, +)
            guard total > 0, displayTotal > 0 else { continue }
            var cumulative = 0.0
            for (word, weight) in zip(unit.words, displayWeights) where weight > 0 {
                pendingWords.append(PendingWord(
                    index: word.index, unit: unitIndex,
                    startTarget: cumulative / displayTotal * total,
                    endTarget: (cumulative + weight) / displayTotal * total
                ))
                cumulative += weight
            }
        }
    }

    private func seconds(at target: Double, unit: Int) -> Double? {
        var cumulative = 0.0
        let indices = unitParts[unit]
        for index in indices {
            let weight = parts[index].weight
            if target <= cumulative + weight + 1e-9 || index == indices.last {
                guard index < synthesizedParts else { return nil }
                let fraction = weight > 0 ? min(1, max(0, (target - cumulative) / weight)) : 0
                let frame = Double(parts[index].startFrame) + fraction * Double(parts[index].samples.count)
                return frame / sampleRate
            }
            cumulative += weight
        }
        return nil
    }

    /// Words become timed in order, as soon as the audio they fall in has been synthesized.
    private func resolveWords() {
        while timedWords.count < pendingWords.count {
            let word = pendingWords[timedWords.count]
            guard let start = seconds(at: word.startTarget, unit: word.unit),
                  let end = seconds(at: word.endTarget, unit: word.unit) else { return }
            let timed = TimedWord(index: word.index, start: start, end: max(end, start + 0.05))
            timedWords.append(timed)
            spans[word.index] = (timed.start, timed.end)
        }
    }

    private func startTicker(_ id: UUID) {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.runID == id else { return }
                if self.phase == .speaking { self.refreshActiveWord() }
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
    }

    private func enqueue(_ samples: [Float], generation gen: Int) {
        guard let buffer = makeBuffer(samples) else { return }
        pendingBuffers += 1
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
            Task { @MainActor [weak self] in self?.bufferFinished(gen) }
        }
    }

    private func bufferFinished(_ gen: Int) {
        guard generation == gen else { return }
        pendingBuffers -= 1
        finishIfDone()
    }

    private func finishIfDone() {
        if isDoneScheduling, pendingBuffers <= 0, !isScrubbing, !isPaused, activeText != nil { stop() }
    }

    private func loadedEngine() async throws -> ParadeeSpeechEngine {
        if let engine { return engine }
        let loaded = try await Task.detached(priority: .userInitiated) { try ParadeeSpeechEngine() }.value
        engine = loaded
        return loaded
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }
}
