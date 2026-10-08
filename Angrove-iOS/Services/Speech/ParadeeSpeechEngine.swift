//
//  ParadeeSpeechEngine.swift
//  Angrove-iOS
//

import Foundation
import MisakiSwift
import OnnxRuntimeBindings

/// On-device text-to-speech with Paradee, an 8M-parameter distillation of Kokoro-82M
/// (`sahilmahendrakar/Paradee-8M-v1.0`, Apache-2.0). Text becomes misaki phonemes through the
/// vendored MisakiSwift G2P, then one int8 ONNX graph turns phoneme ids into 24 kHz audio.
///
/// This runs on ONNX Runtime's CPU provider, separate from the LiteRT generation runtime, and is
/// only used to read finished responses aloud.
actor ParadeeSpeechEngine {
    static let sampleRate = 24_000.0
    /// The text side has 512 positions, two of which are the pad tokens at each end.
    static let maxPhonemes = 510

    enum EngineError: Error {
        case missingResource(String)
        case unexpectedOutput
    }

    private let session: ORTSession
    private let vocab: [Character: Int64]
    private let g2p: EnglishG2P
    private let unknownWords = UnknownWordLog()

    init(bundle: Bundle = .main) throws {
        guard let modelURL = bundle.url(forResource: "paradee_int8", withExtension: "onnx") else {
            throw EngineError.missingResource("paradee_int8.onnx")
        }
        guard let configURL = bundle.url(forResource: "paradee_config", withExtension: "json") else {
            throw EngineError.missingResource("paradee_config.json")
        }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: configURL))
        vocab = Dictionary(uniqueKeysWithValues: config.vocab.compactMap { key, id in
            key.count == 1 ? (key.first!, id) : nil
        })

        let env = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        // One thread already runs ~20x faster than real time and leaves the generation runtime alone.
        try options.setIntraOpNumThreads(1)
        try options.setGraphOptimizationLevel(.all)
        session = try ORTSession(env: env, modelPath: modelURL.path, sessionOptions: options)

        let log = unknownWords
        g2p = EnglishG2P(british: false, unk: "", fallback: { word in
            let phonemes = SpeechPronunciations.phonemes(for: word)
            log.record(word, phonemes: phonemes)
            return phonemes
        })
    }

    /// The spoken sentences of `text`, each as phoneme strings short enough for one model call.
    func sentences(for text: String) -> [SpeechSentence] {
        SpeechTextNormalizer.sentences(in: text).map { sentence in
            SpeechSentence(text: sentence, chunks: Self.split(g2p.phonemize(text: sentence).0))
        }
    }

    /// Mono float samples at `sampleRate` for one phoneme chunk.
    func synthesize(phonemes: String, speed: Float = 1) throws -> [Float] {
        var ids: [Int64] = [0]
        ids += phonemes.compactMap { vocab[$0] }.prefix(Self.maxPhonemes)
        ids.append(0)
        guard ids.count > 2 else { return [] }

        let idData = ids.withUnsafeBufferPointer { NSMutableData(bytes: $0.baseAddress, length: $0.count * MemoryLayout<Int64>.size) }
        var speedValue = speed
        let speedData = NSMutableData(bytes: &speedValue, length: MemoryLayout<Float>.size)
        let outputs = try session.run(
            withInputs: [
                "input_ids": try ORTValue(tensorData: idData, elementType: .int64, shape: [1, NSNumber(value: ids.count)]),
                "speed": try ORTValue(tensorData: speedData, elementType: .float, shape: [1]),
            ],
            outputNames: ["waveform"],
            runOptions: nil
        )
        guard let waveform = outputs["waveform"] else { throw EngineError.unexpectedOutput }
        let data = try waveform.tensorData() as Data
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    /// Cuts an over-long sentence at the last space that fits, as the reference implementation does.
    static func split(_ phonemes: String) -> [String] {
        var remaining = Substring(phonemes.trimmingCharacters(in: .whitespaces))
        var chunks: [String] = []
        while remaining.count > maxPhonemes {
            let limit = remaining.index(remaining.startIndex, offsetBy: maxPhonemes)
            let cut = remaining[..<limit].lastIndex(of: " ") ?? limit
            chunks.append(String(remaining[..<cut]))
            remaining = remaining[cut...].drop(while: { $0 == " " })
        }
        if !remaining.isEmpty { chunks.append(String(remaining)) }
        return chunks
    }

    private struct Config: Decodable {
        let vocab: [String: Int64]
    }
}

/// Debug visibility into words the lexicon and pronunciation list both miss.
nonisolated private final class UnknownWordLog: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: Set<String> = []

    func record(_ word: String, phonemes: String?) {
        #if DEBUG
        let isNew = lock.withLock { seen.insert(word).inserted }
        if isNew { print("[Speech] G2P fallback: \(word) -> \(phonemes ?? "(skipped)")") }
        #endif
    }
}

/// One normalized sentence and the phoneme chunks it is synthesized from.
nonisolated struct SpeechSentence: Sendable {
    let text: String
    let chunks: [String]
}
