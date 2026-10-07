import CoreML
import Foundation

/// One serial worker owns the live MiniLM model, tokenizer, corpus and bounded caches. Preparing
/// these assets never blocks shell construction, and concurrent first callers share one load.
nonisolated final class SemanticAssetService: @unchecked Sendable {
    static let shared = SemanticAssetService()
    private let queue = DispatchQueue(label: "com.angrove.semantic-assets", qos: .userInitiated)
    private let versionLock = NSLock()
    enum PreparationState: Equatable, Sendable { case preparing, ready, embeddingFallback, groundingFallback }
    private var preparationState: PreparationState = .preparing
    var state: PreparationState { versionLock.withLock { preparationState } }
    private var resolvedVersion = "minilm-l6-v2.v1"
    private var embedder: MiniLMEmbedder?
    private var grounding: any AngroveGroundingProviding = LocalAngroveGroundingProvider()
    private var embeddings: [String: [Double]] = [:]
    private var embeddingOrder: [String] = []
    private var referencesCache: [Query: [AngroveGroundingReference]] = [:]
    private var queryOrder: [Query] = []

    private struct Query: Hashable { let text: String; let limit: Int }

    var version: String { versionLock.withLock { resolvedVersion } }

    init(bundle: Bundle = .main) {
        queue.async { [self] in
            PerformanceTrace.measure("Semantic Asset Preparation") {
                do {
                    let provider = try MiniLMEmbeddingProvider(bundle: bundle)
                    embedder = provider.sharedEmbedder
                    grounding = try MiniLMGroundingProvider(bundle: bundle, embedder: provider.sharedEmbedder)
                    versionLock.withLock { preparationState = .ready }
                } catch {
                    // Preserve the existing degraded fallback and tag every vector with its space.
                    versionLock.withLock {
                        if embedder == nil { resolvedVersion = "nl.en.v1"; preparationState = .embeddingFallback }
                        else { preparationState = .groundingFallback }
                    }
                }
            }
        }
    }

    func embed(_ text: String) async -> [Double]? {
        guard !Task.isCancelled else { return nil }
        let request = SemanticWorkerRequest()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard !request.isCancelled else { continuation.resume(returning: nil); return }
                if let cached = embeddings[text] { continuation.resume(returning: cached); return }
                let result = PerformanceTrace.measure("Semantic Embedding") {
                    embedder.flatMap { try? $0.embed(text).map(Double.init) } ?? (embedder == nil ? computeEmbedding(for: text) : nil)
                }
                if let result {
                    if embeddingOrder.count >= 256 { embeddings.removeValue(forKey: embeddingOrder.removeFirst()) }
                    embeddings[text] = result
                    embeddingOrder.append(text)
                }
                continuation.resume(returning: request.isCancelled ? nil : result)
            }
            }
        } onCancel: { request.cancel() }
    }

    func references(for question: String, limit: Int) async -> [AngroveGroundingReference] {
        guard !Task.isCancelled else { return [] }
        let request = SemanticWorkerRequest()
        return await withTaskCancellationHandler {
              await withCheckedContinuation { continuation in
                queue.async { [self] in
                    guard !request.isCancelled else { continuation.resume(returning: []); return }
                    let result = cachedReferences(for: question, limit: limit)
                    continuation.resume(returning: request.isCancelled ? [] : result)
                }
              }
        } onCancel: { request.cancel() }
    }

    /// Compatibility for synchronous diagnostic callers. Live requests use the async boundary.
    func synchronousReferences(for question: String, limit: Int) -> [AngroveGroundingReference] {
        queue.sync { cachedReferences(for: question, limit: limit) }
    }

    private func cachedReferences(for question: String, limit: Int) -> [AngroveGroundingReference] {
        let query = Query(text: question, limit: limit)
        if let result = referencesCache[query] { return result }
        let result = PerformanceTrace.measure("Grounding Retrieval") { grounding.references(for: question, limit: limit) }
        if queryOrder.count >= 32 { referencesCache.removeValue(forKey: queryOrder.removeFirst()) }
        referencesCache[query] = result
        queryOrder.append(query)
        return result
    }
}

struct LazySemanticEmbeddingProvider: EmbeddingProvider {
    private let service: SemanticAssetService
    init(service: SemanticAssetService = .shared) { self.service = service }
    var version: String { service.version }
    func embed(_ text: String) async -> [Double]? { await service.embed(text) }
}

nonisolated struct LazyGroundingProvider: AngroveGroundingProviding {
    let service: SemanticAssetService
    init(service: SemanticAssetService = .shared) { self.service = service }
    func references(for question: String, limit: Int) -> [AngroveGroundingReference] {
        service.synchronousReferences(for: question, limit: limit)
    }
    func referencesAsync(for question: String, limit: Int) async -> [AngroveGroundingReference] {
        await service.references(for: question, limit: limit)
    }
}

private nonisolated final class SemanticWorkerRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}
