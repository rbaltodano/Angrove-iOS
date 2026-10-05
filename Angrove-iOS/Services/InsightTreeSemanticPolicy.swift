//
//  InsightTreeSemanticPolicy.swift
//  Angrove-iOS
//

import Foundation

/// Tunable semantic decisions, deliberately separate from visual distance mapping. Similarity is
/// cosine similarity in the bundled MiniLM space; it is not a probability.
enum InsightTreeSemanticPolicy {
    /// Carried over from the retired development backend's `DEFAULT_MEMBERSHIP_THRESHOLD` until a
    /// labeled conversation set provides a better calibrated value.
    static let membershipSimilarity = 0.40

    /// A conversation turn below this similarity to every existing subject seeds a new Node.
    /// Kept stricter than Insight membership so normal follow-ups do not grow duplicate subjects.
    static let newSubjectSimilarity = 0.60

    /// Two Nodes at or above this similarity are one subject and fold together. Set just above
    /// the highest "related but separate" calibration pair (0.64, Creation / Providence), so
    /// distinct neighbors stay apart while near-duplicates like "Ancient Greek States" and
    /// "Ancient Greek City-States" (0.89) merge.
    static let nodeMergeSimilarity = 0.65

    /// Two Nodes whose subjects ("label. definition") reach this similarity also fold together,
    /// even when their members are loosely related. Higher than the member bar because a shared
    /// subject word inflates the score: "Ancient Greek States" / "Ancient Greek Politics" (0.80)
    /// merge, "Divine Human Nature" / "Divine Essence" (0.70) do not.
    static let nodeSubjectMergeSimilarity = 0.75
}
