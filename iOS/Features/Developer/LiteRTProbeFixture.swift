//
//  LiteRTProbeFixture.swift
//  Angrove-iOS
//

import Foundation

nonisolated enum LiteRTProbeFixtureError: LocalizedError, Equatable {
    case malformed(String)
    case unknownRole(String)
    case emptyTurn(index: Int)
    case emptyQuestion
    case unknownPersonality(String)

    var errorDescription: String? {
        switch self {
        case let .malformed(detail):
            "The probe fixture is not valid JSON: \(detail)"
        case let .unknownRole(role):
            "Probe fixture turns must be \"user\" or \"assistant\", not \"\(role)\"."
        case let .emptyTurn(index):
            "Probe fixture turn \(index) has no text."
        case .emptyQuestion:
            "The probe fixture needs a non-empty final question."
        case let .unknownPersonality(value):
            "Unknown probe fixture personality \"\(value)\"."
        }
    }
}

/// A multi-turn conversation for `--litert-probe-fixture`: prior user/assistant turns plus the
/// final question, run through the production `LiteRTAngroveModel` path.
///
/// ```json
/// {
///   "turns": [
///     { "role": "user", "text": "Can mercy conflict with justice?" },
///     { "role": "assistant", "text": "…" }
///   ],
///   "question": "What's the capital of Portugal?",
///   "personality": "balanced",
///   "compactedContext": null
/// }
/// ```
struct LiteRTProbeFixture: Decodable, Equatable {
    struct Turn: Decodable, Equatable {
        let role: String
        let text: String
    }

    let turns: [Turn]
    let question: String
    let personality: String?
    let compactedContext: String?

    private enum CodingKeys: String, CodingKey {
        case turns, question, personality, compactedContext
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        turns = try container.decodeIfPresent([Turn].self, forKey: .turns) ?? []
        question = try container.decode(String.self, forKey: .question)
        personality = try container.decodeIfPresent(String.self, forKey: .personality)
        compactedContext = try container.decodeIfPresent(String.self, forKey: .compactedContext)
    }

    static func load(from url: URL) throws -> LiteRTProbeFixture {
        try parse(Data(contentsOf: url))
    }

    static func parse(_ data: Data) throws -> LiteRTProbeFixture {
        let fixture: LiteRTProbeFixture
        do {
            fixture = try JSONDecoder().decode(LiteRTProbeFixture.self, from: data)
        } catch {
            throw LiteRTProbeFixtureError.malformed(String(describing: error))
        }
        _ = try fixture.conversationContext()
        return fixture
    }

    /// The same transcript shape the app builds: prior turns in order, then the question.
    func conversationContext() throws -> ConversationContext {
        var transcript: [ChatBlock] = []
        for (index, turn) in turns.enumerated() {
            let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw LiteRTProbeFixtureError.emptyTurn(index: index)
            }
            switch turn.role {
            case "user":
                transcript.append(.user(text, nil, []))
            case "assistant":
                transcript.append(.text(text))
            default:
                throw LiteRTProbeFixtureError.unknownRole(turn.role)
            }
        }
        let finalQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalQuestion.isEmpty else {
            throw LiteRTProbeFixtureError.emptyQuestion
        }
        transcript.append(.user(finalQuestion, nil, []))

        let resolvedPersonality: ConversationPersonality
        if let personality {
            guard let value = ConversationPersonality(rawValue: personality) else {
                throw LiteRTProbeFixtureError.unknownPersonality(personality)
            }
            resolvedPersonality = value
        } else {
            resolvedPersonality = .default
        }
        return ConversationContext(
            compactedContext: compactedContext,
            transcript: transcript,
            personality: resolvedPersonality
        )
    }
}
