// MotionAnomalyDetector.swift
// LifeOptimizer — Motion Anomaly Detection via Personalized Z-Score
//
// IMPORTANT: Motion anomaly does NOT imply paralysis.
// We are detecting deviation from the PERSON'S OWN normal motion pattern.

import Foundation

public final class MotionAnomalyDetector {

    // MARK: - Feature Weights

    private static let weights: [String: Double] = [
        // Jerk is the strongest sudden-event indicator
        "jerk":                  3.0,
        // Sudden large acceleration
        "accelerationMagnitude": 2.0,
        "motionEnergy":          1.5,
        // Individual axes
        "accelerationX":         1.0,
        "accelerationY":         1.0,
        "accelerationZ":         1.0,
        // Rotation
        "rotationMagnitude":     2.0,
        "rotationRateX":         1.0,
        "rotationRateY":         1.0,
        "rotationRateZ":         1.0,
        // Attitude change
        "pitchChange":           0.8,
        "rollChange":            0.8,
        "yawChange":             0.6,
    ]

    // MARK: - Score

    /// Compute motion anomaly scores against the personal baseline engine.
    public func score(
        _ vector: MotionFeatureVector,
        baseline: BaselineEngine
    ) -> MotionScore {
        let values = vector.namedValues
        var weightedSum    = 0.0
        var totalWeight    = 0.0

        var accelSum = 0.0; var accelW = 0.0
        var jerkSum  = 0.0; var jerkW  = 0.0
        var gyroSum  = 0.0; var gyroW  = 0.0

        for (name, value) in values {
            let w = Self.weights[name] ?? 1.0
            let (z, _) = baseline.score(name: "motion.\(name)", value: value)
            let normalized = normalizeZ(z)

            weightedSum += normalized * w
            totalWeight += w

            switch name {
            case "accelerationMagnitude", "accelerationX",
                 "accelerationY", "accelerationZ", "motionEnergy":
                accelSum += normalized * w; accelW += w
            case "jerk":
                jerkSum += normalized * w; jerkW += w
            case "rotationRateX", "rotationRateY", "rotationRateZ",
                 "rotationMagnitude", "pitchChange", "rollChange", "yawChange":
                gyroSum += normalized * w; gyroW += w
            default:
                break
            }
        }

        let total      = totalWeight > 0 ? weightedSum / totalWeight : 0
        let accelScore = accelW > 0 ? accelSum / accelW : 0
        let jerkScore  = jerkW  > 0 ? jerkSum  / jerkW  : 0
        let gyroScore  = gyroW  > 0 ? gyroSum  / gyroW  : 0

        return MotionScore(
            totalScore:        clamp01(total),
            accelerationScore: clamp01(accelScore),
            jerkScore:         clamp01(jerkScore),
            gyroScore:         clamp01(gyroScore)
        )
    }

    // MARK: - Helpers

    private func normalizeZ(_ z: Double) -> Double {
        1.0 - exp(-z / 3.0)
    }

    private func clamp01(_ v: Double) -> Double {
        min(max(v, 0), 1)
    }
}
