//
//  ResponseSpeechPlayer.swift
//  Angrove-iOS
//

import AVFoundation
import Observation
import os

/// Reads one model response aloud at a time. Each sentence is scheduled as soon as it is
/// synthesized, so playback starts after the first sentence rather than the whole answer.
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

    @ObservationIgnored private var engine: ParadeeSpeechEngine?
    @ObservationIgnored private var playback: Task<Void, Never>?
    @ObservationIgnored private var runID = UUID()
    @ObservationIgnored private var pendingBuffers = 0
    @ObservationIgnored private var isDoneScheduling = false
    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private let playerNode = AVAudioPlayerNode()
    @ObservationIgnored private let format = AVAudioFormat(
        standardFormatWithSampleRate: ParadeeSpeechEngine.sampleRate, channels: 1
    )!
    @ObservationIgnored private let logger = Logger(subsystem: "com.ryanbaltodano.Aquinas-iOS", category: "Speech")

    private init() {
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
    }

    func phase(for text: String) -> Phase {
        activeText == text ? phase : .idle
    }

    /// Starts reading `text`, or stops if it is already being read.
    func toggle(_ text: String) {
        if activeText == text {
            stop()
        } else {
            speak(text)
        }
    }

    func stop() {
        runID = UUID()
        playback?.cancel()
        playback = nil
        playerNode.stop()
        audioEngine.stop()
        activeText = nil
        phase = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func speak(_ text: String) {
        stop()
        let id = runID
        activeText = text
        phase = .preparing
        pendingBuffers = 0
        isDoneScheduling = false
        playback = Task { [weak self] in
            await self?.run(text, id: id)
        }
    }

    private func run(_ text: String, id: UUID) async {
        do {
            let engine = try await loadedEngine()
            let chunks = await engine.phonemeChunks(for: text)
            try Task.checkCancellation()

            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            try audioEngine.start()
            playerNode.play()

            for chunk in chunks {
                let samples = try await engine.synthesize(phonemes: chunk)
                try Task.checkCancellation()
                guard let buffer = makeBuffer(samples) else { continue }
                pendingBuffers += 1
                playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
                    Task { @MainActor [weak self] in self?.bufferFinished(id) }
                }
                phase = .speaking
            }
            isDoneScheduling = true
            finishIfDone(id)
        } catch is CancellationError {
            // Stopped, or replaced by another response.
        } catch {
            logger.error("Speech failed: \(error.localizedDescription, privacy: .public)")
            if runID == id { stop() }
        }
    }

    private func bufferFinished(_ id: UUID) {
        guard runID == id else { return }
        pendingBuffers -= 1
        finishIfDone(id)
    }

    private func finishIfDone(_ id: UUID) {
        if runID == id, isDoneScheduling, pendingBuffers <= 0 { stop() }
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
