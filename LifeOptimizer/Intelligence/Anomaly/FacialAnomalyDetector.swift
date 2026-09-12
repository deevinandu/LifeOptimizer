// FacialAnomalyDetector.swift
// LifeOptimizer — Facial Anomaly Detection via Personalized Z-Score
//
// Computes per-feature z-scores against the personal baseline.
// Asymmetry features are weighted heavily because they are the primary
// stroke-like indicator (matching RMIT / Mohamed et al. findings).

import Foundation

public final class FacialAnomalyDetector {

    // MARK: - Feature Weights
    //
    // Asymmetry features get higher weight because they are the primary
    // stroke-like signal. Raw blend shapes provide supporting evidence.

    private static let weights: [String: Double] = [
        // Asymmetry features — primary signals
        "smileAsymmetry":   3.0,
        "frownAsymmetry":   2.5,
        "blinkAsymmetry":   2.5,
        "stretchAsymmetry": 2.0,
        "squintAsymmetry":  1.5,

        // Raw mouth features — supporting
        "mouthSmileLeft":   1.0,
        "mouthSmileRight":  1.0,
        "mouthFrownLeft":   1.0,
        "mouthFrownRight":  1.0,
        "jawOpen":          0.8,
        "mouthPucker":      0.5,
        "mouthFunnel":      0.5,
        "mouthStretchLeft": 0.8,
        "mouthStretchRight":0.8,

        // Eye features
        "eyeBlinkLeft":     0.8,
        "eyeBlinkRight":    0.8,
        "eyeSquintLeft":    0.6,
        "eyeSquintRight":   0.6,

        // Head pose — lower weight
        "headPitch": 0.4,
        "headYaw":   0.4,
        "headRoll":  0.6,
    ]

    private let epsilon: Double = 1e-6

    // MARK: - Score

    /// Compute facial anomaly scores from a feature vector against the baseline engine.
    ///
    /// - Parameters:
    ///   - vector: Current facial feature vector.
    ///   - baseline: The personal baseline engine.
    /// - Returns: FacialScore with sub-scores and a total normalized 0–1 score.
    public func score(
        _ vector: FacialFeatureVector,
        baseline: BaselineEngine
    ) -> FacialScore {
        let values = vector.namedValues
        var weightedSum = 0.0
        var totalWeight = 0.0

        var smileSum   = 0.0; var smileW   = 0.0
        var blinkSum   = 0.0; var blinkW   = 0.0
        var mouthSum   = 0.0; var mouthW   = 0.0
        var poseSum    = 0.0; var poseW    = 0.0

        for (name, value) in values {
            let w = Self.weights[name] ?? 1.0
            let (z, _) = baseline.score(name: name, value: value)
            // Normalize z to ~0–1 using sigmoid-like clamping
            let normalized = normalizeZ(z)

            weightedSum += normalized * w
            totalWeight += w

            // Attribute to sub-score buckets
            switch name {
            case "smileAsymmetry", "mouthSmileLeft", "mouthSmileRight",
                 "frownAsymmetry", "mouthFrownLeft", "mouthFrownRight",
                 "stretchAsymmetry", "mouthStretchLeft", "mouthStretchRight":
                smileSum += normalized * w; smileW += w
            case "blinkAsymmetry", "eyeBlinkLeft", "eyeBlinkRight",
                 "squintAsymmetry", "eyeSquintLeft", "eyeSquintRight":
                blinkSum += normalized * w; blinkW += w
            case "jawOpen", "mouthPucker", "mouthFunnel":
                mouthSum += normalized * w; mouthW += w
            case "headPitch", "headYaw", "headRoll":
                poseSum += normalized * w; poseW += w
            default:
                break
            }
        }

        let total      = totalWeight > 0 ? weightedSum / totalWeight : 0
        let smileScore = smileW > 0 ? smileSum / smileW : 0
        let blinkScore = blinkW > 0 ? blinkSum / blinkW : 0
        let mouthScore = mouthW > 0 ? mouthSum / mouthW : 0
        let poseScore  = poseW  > 0 ? poseSum  / poseW  : 0

        return FacialScore(
            totalScore:    clamp01(total),
            smileScore:    clamp01(smileScore),
            blinkScore:    clamp01(blinkScore),
            mouthScore:    clamp01(mouthScore),
            headPoseScore: clamp01(poseScore)
        )
    }

    // MARK: - Helpers

    /// Map z-score (0→∞) to normalized score (0→1).
    /// Uses a soft clamping: z=3 → 0.75, z=5 → ~0.95
    private func normalizeZ(_ z: Double) -> Double {
        // 1 - exp(-z/3) gives a smooth curve that saturates near 1
        1.0 - exp(-z / 3.0)
    }

    private func clamp01(_ v: Double) -> Double {
        min(max(v, 0), 1)
    }
}
