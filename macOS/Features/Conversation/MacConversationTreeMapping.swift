import CryptoKit
import Foundation

/// A completed turn's stable location and content, independent of a mounted conversation view.
struct MacConversationMappingTurn: Equatable {
    let branchID: UUID
    let responseIndex: Int
    let question: String
    let answer: String

    var key: String { "\(branchID):\(responseIndex)" }
    var fingerprint: String {
        let data = (try? JSONEncoder().encode([question, answer])) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func completed(in branches: [ChatBranch]) -> [Self] {
        branches.flatMap { branch -> [Self] in
            guard branch.topQuestionSubmitted else { return [] }
            var question = branch.topQuestionText
            var result: [Self] = []
            for (index, block) in branch.activeChatBlocks.enumerated() {
                switch block {
                case .user(let text, _, _): question = text
                case .text(let text):
                    let answer = InlineInsightMarkup.plainText(from: text).trimmingCharacters(in: .whitespacesAndNewlines)
                    let presentation = branch.responsePresentation(at: index)
                    guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          !answer.isEmpty, answer != questionCanceledResponseText,
                          (presentation?.outcome ?? .completed) == .completed,
                          presentation?.evidenceBasis?.canSeedInsightTree ?? true,
                          !LiteRTAngroveModel.isCorpusScopeAbstention(answer) else { continue }
                    result.append(Self(branchID: branch.id, responseIndex: index, question: question, answer: answer))
                }
            }
            return result
        }
    }

    static func fingerprints(in branches: [ChatBranch]) -> [String: String] {
        Dictionary(completed(in: branches).map { ($0.key, $0.fingerprint) }, uniquingKeysWith: { _, last in last })
    }
}

/// Checkpoints include turns already covered by an existing subject, not just accepted seeds.
/// The encrypted ledger shares the tree's reset lifecycle; no canvas layout is replaced here.
@MainActor final class MacConversationTreeMapping {
    struct Storage {
        var conversation: (UUID) -> InquiryConversation?
        var seeds: (UUID) -> [LocalInsightTreeSeed]
        var saveSeeds: (UUID, [LocalInsightTreeSeed]) -> Void
        var checkpoints: (UUID) -> [String: String]
        var saveCheckpoints: (UUID, [String: String]) -> Void
        var didAddSeed: (UUID) -> Void

        static var live: Self {
            Self(conversation: { id in CurrentConversationsStore.load()?.conversations.first { $0.id == id } },
                 seeds: { LocalInsightTreeSeedStore.seeds(for: $0) },
                 saveSeeds: { LocalInsightTreeSeedStore.replaceSeeds($1, for: $0) },
                 checkpoints: { InsightTreeLocalStateStore.load([String: String].self, key: ledgerKey($0)) ?? [:] },
                 saveCheckpoints: { InsightTreeLocalStateStore.save($1, key: ledgerKey($0)) },
                 didAddSeed: { id in
                     InsightDiscoveryStore.markNodesUndiscovered([id])
                     InsightDiscoveryStore.markPendingTreePresentation(insightIDs: [], nodeIDs: [id])
                 })
        }
    }

    private let storage: Storage
    private var reservations: Set<String> = []

    init(storage: Storage = .live) { self.storage = storage }

    nonisolated private static func ledgerKey(_ id: UUID) -> String { "aquinas.insight-tree.mac-mapped-turns.v1.\(id)" }
    private func reservation(_ turn: MacConversationMappingTurn, _ id: UUID) -> String {
        "\(id):\(turn.key):\(turn.fingerprint)"
    }

    /// Transfer mapping runs before subsequently submitted questions. Ordinary completed-turn
    /// mapping retains its background priority and never backfills unrelated historical turns.
    func enqueue(conversationID: UUID, turns: [MacConversationMappingTurn], baseline: [String: String] = [:],
                 runtime: MacApplicationRuntime, priority: ModelTaskPriority = .foreground, onFailure: @escaping () -> Void = {}) {
        guard !PersonalDataProtection.isBlocked else { return }
        var checkpoints = storage.checkpoints(conversationID)
        let previous = checkpoints
        // Conversations brought out of the sidebar already have an accepted history. Only
        // acknowledge an unchanged turn, and never suppress its still-running analysis job.
        for turn in turns where checkpoints[turn.key] == nil && baseline[turn.key] == turn.fingerprint
            && !reservations.contains(reservation(turn, conversationID)) {
            checkpoints[turn.key] = turn.fingerprint
        }
        if checkpoints != previous { storage.saveCheckpoints(conversationID, checkpoints) }
        let pending = turns.filter {
            checkpoints[$0.key] != $0.fingerprint && !reservations.contains(reservation($0, conversationID))
        }
        guard !pending.isEmpty else { return }
        let keys = Set(pending.map { reservation($0, conversationID) })
        reservations.formUnion(keys)
        runtime.modelTasks.enqueue(kind: .updateInsightTree, originPage: .conversation,
            conversationID: conversationID, priority: priority,
            onCancel: { [self] in reservations.subtract(keys) },
            onCompletion: { [self] in reservations.subtract(keys) }) { [self] in
                var hasFailure = false
                for turn in pending {
                    guard !Task.isCancelled else { return }
                    do {
                        try await map(turn, conversationID: conversationID, model: runtime.model,
                                      embeddings: runtime.embeddingProvider)
                    } catch {
                        guard !Task.isCancelled else { return }
                        // Failed extraction/embedding is not acknowledged; a later transfer can retry.
                        hasFailure = true
                        runtime.modelTasks.reportCurrentFailure()
                    }
                }
                if hasFailure, !Task.isCancelled { onFailure() }
            }
    }

    private func isCurrent(_ turn: MacConversationMappingTurn, in id: UUID) -> Bool {
        guard !Task.isCancelled, !PersonalDataProtection.isBlocked,
              let conversation = storage.conversation(id) else { return false }
        return MacConversationMappingTurn.completed(in: conversation.branches).contains(turn)
    }

    private func acknowledge(_ turn: MacConversationMappingTurn, in id: UUID) {
        var checkpoints = storage.checkpoints(id)
        checkpoints[turn.key] = turn.fingerprint
        storage.saveCheckpoints(id, checkpoints)
    }

    private func map(_ turn: MacConversationMappingTurn, conversationID: UUID,
                     model: any AngroveModel, embeddings: any EmbeddingProvider) async throws {
        guard isCurrent(turn, in: conversationID), storage.checkpoints(conversationID)[turn.key] != turn.fingerprint else { return }
        let seedID = stableUUID(from: "conversation-seed:\(conversationID):\(turn.key):\(turn.fingerprint)")
        if storage.seeds(conversationID).contains(where: { $0.id == seedID }) {
            acknowledge(turn, in: conversationID)
            return
        }
        guard let candidate = try await model.insightTreeSeedCandidate(question: turn.question, response: turn.answer),
              let vector = await embeddings.embed(candidate.label + " " + candidate.summary) else {
            throw AngroveModelActionError.unavailable
        }
        guard isCurrent(turn, in: conversationID) else { return }
        // Refresh old vectors without changing IDs, labels, creation times or canvas positions.
        for seed in storage.seeds(conversationID) where seed.embeddingVersion != embeddings.version || seed.embedding == nil {
            guard let refreshed = await embeddings.embed(seed.label + " " + seed.summary) else {
                throw AngroveModelActionError.unavailable
            }
            guard isCurrent(turn, in: conversationID) else { return }
            var latest = storage.seeds(conversationID)
            if let index = latest.firstIndex(of: seed) {
                latest[index] = LocalInsightTreeSeed(id: seed.id, label: seed.label, summary: seed.summary,
                    embedding: refreshed, embeddingVersion: embeddings.version, createdAt: seed.createdAt)
                storage.saveSeeds(conversationID, latest)
            }
        }
        guard isCurrent(turn, in: conversationID) else { return }
        var seeds = storage.seeds(conversationID)
        let isCovered = seeds.contains {
            $0.embeddingVersion == embeddings.version && $0.embedding.map {
                cosineSimilarity(vector, $0) >= InsightTreeSemanticPolicy.newSubjectSimilarity
            } == true
        }
        if !isCovered && !seeds.contains(where: { $0.id == seedID }) {
            seeds.append(LocalInsightTreeSeed(id: seedID, label: candidate.label, summary: candidate.summary,
                embedding: vector, embeddingVersion: embeddings.version, createdAt: Date()))
            storage.saveSeeds(conversationID, seeds)
            storage.didAddSeed(seedID)
        }
        acknowledge(turn, in: conversationID)
    }
}
