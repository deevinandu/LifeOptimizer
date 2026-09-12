// BaselineEngine.swift
// LifeOptimizer — Personal Baseline with EMA Update and Anomaly Gate
//
// CRITICAL DESIGN RULE:
//   Anomalous observations MUST NOT update the core baseline.
//   Only observations classified as NORMAL are fed into the EMA.
//
// Thread safety: All public methods must be called from the same actor/queue.
// Caller (DetectionStateMachine) is responsible for serialization.

import Foundation

// MARK: - Statistical Feature State

/// Statistical summary of one named feature.
/// Stored in-memory and persisted via BaselineStore.
public struct BaselineFeatureStat: Sendable {
    public var name: String
    public var mean: Double
    public var variance: Double   // rolling variance estimate
    public var sampleCount: Int
    public var lastUpdated: Date

    /// Confidence in this feature's baseline (0–1).
    /// Increases as sample count grows; saturates at ~200 samples.
    public var confidence: Double {
        min(Double(sampleCount) / 200.0, 1.0)
    }

    public var standardDeviation: Double {
        sqrt(max(variance, 0))
    }

    public init(name: String,
                mean: Double = 0,
                variance: Double = 0.01,
                sampleCount: Int = 0,
                lastUpdated: Date = Date()) {
        self.name        = name
        self.mean        = mean
        self.variance    = variance
        self.sampleCount = sampleCount
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Baseline Engine

/// The personal baseline engine.
///
/// Maintains per-feature statistics using an exponential moving average.
/// Anomalous observations are rejected — they never modify the baseline.
public final class BaselineEngine {

    // MARK: - Configuration

    /// EMA alpha for mean update. Lower = slower adaptation.
    /// Suggested range: 0.05–0.10
    public var alpha: Double

    /// EMA alpha for variance. Slightly faster than mean to track spread.
    public var varianceAlpha: Double

    /// z-score threshold above which an observation is considered anomalous.
    /// Observations with z > anomalyZThreshold are NOT fed back into the baseline.
    public var anomalyZThreshold: Double

    /// Minimum samples before we trust the baseline for anomaly gating.
    /// Below this count all observations are accepted to bootstrap the baseline.
    public var bootstrapThreshold: Int

    private let epsilon: Double = 1e-6

    // MARK: - State

    /// Per-feature statistics. Key = feature name.
    public private(set) var features: [String: BaselineFeatureStat] = [:]

    // MARK: - Init

    public init(
        alpha: Double = 0.05,
        varianceAlpha: Double = 0.08,
        anomalyZThreshold: Double = 3.0,
        bootstrapThreshold: Int = 30
    ) {
        self.alpha              = alpha
        self.varianceAlpha      = varianceAlpha
        self.anomalyZThreshold  = anomalyZThreshold
        self.bootstrapThreshold = bootstrapThreshold
    }

    // MARK: - Load from Persistence

    /// Restore persisted stats (called by BaselineStore on startup).
    public func restore(stats: [BaselineFeatureStat]) {
        for stat in stats {
            features[stat.name] = stat
        }
    }

    // MARK: - Scoring

    /// Compute a z-score for a single feature value against its baseline.
    /// Returns (zScore, isNormal).
    public func score(name: String, value: Double) -> (zScore: Double, isNormal: Bool) {
        guard let stat = features[name] else {
            // No baseline yet — treat as normal to bootstrap
            return (0.0, true)
        }
        let std = stat.standardDeviation
        let z   = abs(value - stat.mean) / (std + epsilon)
        let isBootstrapping = stat.sampleCount < bootstrapThreshold
        let isNormal = isBootstrapping || z <= anomalyZThreshold
        return (z, isNormal)
    }

    /// Score an entire named-values dictionary.
    /// Returns average z-score and whether ALL features are normal.
    public func scoreAll(named values: [String: Double]) -> (averageZ: Double, allNormal: Bool) {
        guard !values.isEmpty else { return (0, true) }
        var totalZ = 0.0
        var allNormal = true
        for (name, value) in values {
            let (z, normal) = score(name: name, value: value)
            totalZ += z
            if !normal { allNormal = false }
        }
        return (totalZ / Double(values.count), allNormal)
    }

    // MARK: - Update  (ANOMALY GATE — see docstring above)

    /// Update baseline with a new observation IF it passes the anomaly gate.
    ///
    /// - Returns: `true` if the observation was accepted into the baseline;
    ///            `false` if it was rejected as anomalous.
    @discardableResult
    public func update(name: String, value: Double) -> Bool {
        let (_, isNormal) = score(name: name, value: value)
        guard isNormal else {
            // ANOMALY GATE: do not pollute baseline
            return false
        }
        applyEMA(name: name, value: value)
        return true
    }

    /// Update all features in a named dictionary, subject to per-feature anomaly gating.
    ///
    /// - Returns: Set of feature names that were accepted.
    @discardableResult
    public func updateAll(named values: [String: Double]) -> Set<String> {
        var accepted = Set<String>()
        for (name, value) in values {
            if update(name: name, value: value) {
                accepted.insert(name)
            }
        }
        return accepted
    }

    // MARK: - Private EMA

    private func applyEMA(name: String, value: Double) {
        if var stat = features[name] {
            // Update mean with EMA
            let newMean = (1 - alpha) * stat.mean + alpha * value
            // Update variance with EMA of squared deviation from OLD mean
            let deviation  = value - stat.mean
            let newVariance = (1 - varianceAlpha) * stat.variance
                            + varianceAlpha * deviation * deviation
            stat.mean        = newMean
            stat.variance    = max(newVariance, epsilon)
            stat.sampleCount += 1
            stat.lastUpdated = Date()
            features[name]   = stat
        } else {
            // First observation — initialize
            features[name] = BaselineFeatureStat(
                name:        name,
                mean:        value,
                variance:    0.01,
                sampleCount: 1,
                lastUpdated: Date()
            )
        }
    }

    // MARK: - Snapshot for Persistence

    public var allStats: [BaselineFeatureStat] {
        Array(features.values)
    }

    /// Total number of samples across all features (proxy for baseline maturity).
    public var totalSamples: Int {
        features.values.reduce(0) { $0 + $1.sampleCount }
    }

    /// Whether baseline has enough samples to be trusted.
    public var isCalibrated: Bool {
        features.values.allSatisfy { $0.sampleCount >= bootstrapThreshold }
    }
}
