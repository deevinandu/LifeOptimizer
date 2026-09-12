// TemporalAnalyzer.swift
// LifeOptimizer — Rolling Window Temporal Persistence Analysis
//
// Single-frame anomaly scores are noisy. This analyzer maintains a short
// rolling window (~2–5 seconds) and computes a persistence score that
// suppresses transient spikes while confirming sustained anomalies.

import Foundation

public final class TemporalAnalyzer {

    // MARK: - Configuration

    /// Duration of the rolling window in seconds.
    public var windowDuration: TimeInterval

    /// Minimum fraction of window samples that must be anomalous for
    /// the persistence score to be high.
    public var anomalyFraction: Double

    /// Score threshold above which a frame is considered "anomalous".
    public var frameAnomalyThreshold: Double

    // MARK: - State

    private struct FrameRecord {
        let score: Double
        let timestamp: Date
    }

    private var window: [FrameRecord] = []

    // MARK: - Init

    public init(
        windowDuration: TimeInterval = 3.0,
        anomalyFraction: Double = 0.6,
        frameAnomalyThreshold: Double = 0.40
    ) {
        self.windowDuration         = windowDuration
        self.anomalyFraction        = anomalyFraction
        self.frameAnomalyThreshold  = frameAnomalyThreshold
    }

    // MARK: - Update + Score

    /// Feed in the current frame's combined score and receive the temporal persistence score.
    ///
    /// - Parameter frameScore: Combined anomaly score for this frame (0–1).
    /// - Returns: Temporal persistence score (0–1).
    ///            High = anomaly has been sustained; Low = probably transient.
    @discardableResult
    public func update(frameScore: Double) -> Double {
        let now = Date()
        window.append(FrameRecord(score: frameScore, timestamp: now))
        purgeExpired(before: now.addingTimeInterval(-windowDuration))
        return persistenceScore()
    }

    /// Compute persistence score from current window contents (without adding a new sample).
    public func currentPersistenceScore() -> Double {
        persistenceScore()
    }

    // MARK: - Reset

    /// Clear the rolling window (call when monitoring is paused/stopped).
    public func reset() {
        window.removeAll()
    }

    // MARK: - Private

    private func purgeExpired(before cutoff: Date) {
        window.removeAll { $0.timestamp < cutoff }
    }

    private func persistenceScore() -> Double {
        guard !window.isEmpty else { return 0 }

        let count   = Double(window.count)
        let anomalousCount = window.filter { $0.score >= frameAnomalyThreshold }.count
        let fraction = Double(anomalousCount) / count

        // Average score of anomalous frames (or 0 if none)
        let anomalousScores = window
            .filter { $0.score >= frameAnomalyThreshold }
            .map { $0.score }
        let avgAnomScore = anomalousScores.isEmpty ? 0.0
            : anomalousScores.reduce(0, +) / Double(anomalousScores.count)

        // Persistence score = fraction × average anomaly score
        // This is high only if BOTH fraction and individual scores are high
        return min(fraction * avgAnomScore * 1.5, 1.0)
    }

    // MARK: - Diagnostics

    public var windowSize: Int { window.count }
    public var windowScores: [Double] { window.map { $0.score } }

    /// True if the current window contains enough samples to be meaningful.
    public var hasEnoughData: Bool { window.count >= 3 }
}
