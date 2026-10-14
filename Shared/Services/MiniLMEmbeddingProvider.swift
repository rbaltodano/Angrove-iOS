//
//  MiniLMEmbeddingProvider.swift
//  Angrove-iOS
//

import Foundation
import CoreML

/// The real relatedness signal for clustering Insights — on-device MiniLM
/// (`sentence-transformers/all-MiniLM-L6-v2` via Core ML), replacing `NLEmbeddingProvider`'s Apple
/// `NLEmbedding` space. `NLEmbedding`'s cosine similarity on short Insight text is dominated by
/// noise: empirically, unrelated pairs ("Quantum Entanglement" / "Photosynthesis") routinely score
/// *higher* than related ones, so any fixed membership threshold either merges everything into one
/// cluster or splits everything apart — there's no working cutoff in that space. MiniLM is the
/// same embedding space `MiniLMGroundingProvider` searches the grounding corpus with, so on-device
/// Insight Tree clustering compares apples to apples instead of noise to noise.
struct MiniLMEmbeddingProvider: EmbeddingProvider {
    static let version = "minilm-l6-v2.v1"
    var version: String { Self.version }

    let sharedEmbedder: MiniLMEmbedder
    private var embedder: MiniLMEmbedder { sharedEmbedder }

    init(embedder: MiniLMEmbedder) {
        self.sharedEmbedder = embedder
    }

    /// Standalone construction for tests and diagnostics. The live asset service shares this
    /// provider's embedder with grounding instead of loading a second Core ML model.
    init(bundle: Bundle = .main, computeUnits: MLComputeUnits? = nil) throws {
        guard let modelURL = LocalGroundingResource.url("MiniLM", "mlmodelc", in: bundle) else {
            throw MiniLMEmbeddingProviderError.resourceMissing("MiniLM.mlmodelc")
        }
        guard let vocabURL = LocalGroundingResource.url("vocab", "txt", in: bundle) else {
            throw MiniLMEmbeddingProviderError.resourceMissing("vocab.txt")
        }
        self.sharedEmbedder = try MiniLMEmbedder(
            modelURL: modelURL,
            vocabURL: vocabURL,
            computeUnits: computeUnits
        )
    }

    func embed(_ text: String) async -> [Double]? {
        let embedder = embedder
        return await Task.detached(priority: .userInitiated) {
            try? embedder.embed(text).map(Double.init)
        }.value
    }
}

enum MiniLMEmbeddingProviderError: LocalizedError {
    case resourceMissing(String)

    var errorDescription: String? {
        switch self {
        case .resourceMissing(let name):
            "The on-device embedding model is missing \(name)."
        }
    }
}
