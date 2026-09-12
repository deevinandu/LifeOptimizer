// ConfidenceEngine.swift
// LifeOptimizer — Multimodal Weighted Fusion
//
// Combines facial, depth, motion, temporal, and optional speech scores
// into a single DetectionResult using configurable weights.

import Foundation

// MARK: - Fusion Weights (configurable)

public struct FusionWeights {
    public var facial:   Double
    public var depth:    Double
    public var motion:   Double
    public var temporal: Double
    public var speech:   Double

    /// Default weights matching the spec.
    /// Speech weight = 0 until the speech pipeline is implemented.
    public static let `default` = FusionWeights(
        facial:   0.55,
        depth:    0.15,
        motion:   0.20,
        temporal: 0.10,
        speech:   0.00
    )

    public init(facial: Double, depth: Double, motion: Double,
                temporal: Double, speech: Double) {
        self.facial   = facial
        self.depth    = depth
        self.motion   = motion
        self.temporal = temporal
        self.speech   = speech
    }

    /// Validate that weights are non-negative. Normalises them to sum to 1.
    public func normalized() -> FusionWeights {
        var f = max(facial, 0)
        var d = max(depth, 0)
        var m = max(motion, 0)
        var t = max(temporal, 0)
        var s = max(speech, 0)
        let total = f + d + m + t + s
        guard total > 0 else { return .default }
        f /= total; d /= total; m /= total; t /= total; s /= total
        return FusionWeights(facial: f, depth: d, motion: m, temporal: t, speech: s)
    }
}

// MARK: - Confidence Engine

public final class ConfidenceEngine {

    public var weights: FusionWeights

    public init(weights: FusionWeights = .default) {
        self.weights = weights
    }

    // MARK: - Evaluate

    /// Produce a DetectionResult by fusing all available modality scores.
    ///
    /// - Parameters:
    ///   - facial: Facial anomaly score.
    ///   - depth: Depth anomaly score (nil → weight redistributed to facial).
    ///   - motion: Motion anomaly score.
    ///   - temporal: Temporal persistence score.
    ///   - speech: Optional speech score (nil → weight = 0).
    /// - Returns: Fully populated DetectionResult.
    public func evaluate(
        facial:   FacialScore,
        depth:    DepthScore?,
        motion:   MotionScore,
        temporal: Double,
        speech:   SpeechScore? = nil
    ) -> DetectionResult {
        let w = effectiveWeights(depthAvailable: depth != nil, speechAvailable: speech != nil)

        let facialVal   = facial.totalScore
        let depthVal    = depth?.totalScore   ?? 0
        let motionVal   = motion.totalScore
        let temporalVal = min(max(temporal, 0), 1)
        let speechVal   = speech?.totalScore  ?? 0

        let finalScore = w.facial   * facialVal
                       + w.depth    * depthVal
                       + w.motion   * motionVal
                       + w.temporal * temporalVal
                       + w.speech   * speechVal

        let clamped        = min(max(finalScore, 0), 1)
        let classification = classify(score: clamped)

        return DetectionResult(
            facialScore:    facialVal,
            depthScore:     depthVal,
            motionScore:    motionVal,
            temporalScore:  temporalVal,
            speechScore:    speech != nil ? speechVal : nil,
            finalScore:     clamped,
            classification: classification,
            timestamp:      Date()
        )
    }

    // MARK: - Classification

    /// Apply configurable thresholds to produce a DetectionClassification.
    /// Uses DetectionConfig (Laptop B) as the single source of threshold truth.
    public func classify(score: Double) -> DetectionClassification {
        if score < DetectionConfig.mediumThreshold {
            return .normal
        } else if score < DetectionConfig.highThreshold {
            return .medium
        } else {
            return .high
        }
    }

    // MARK: - Weight Adjustment

    /// If depth is unavailable, redistribute depth weight to facial.
    /// If speech is unavailable, its weight goes to facial.
    private func effectiveWeights(depthAvailable: Bool, speechAvailable: Bool) -> FusionWeights {
        var w = weights
        if !depthAvailable {
            w.facial += w.depth
            w.depth   = 0
        }
        if !speechAvailable {
            w.facial += w.speech
            w.speech  = 0
        }
        return w.normalized()
    }
}
