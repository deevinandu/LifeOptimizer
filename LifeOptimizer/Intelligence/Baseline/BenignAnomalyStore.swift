// BenignAnomalyStore.swift
// LifeOptimizer — User-Confirmed Benign Anomaly Memory
//
// When a user confirms "I'm okay" after a MEDIUM alert, the anomalous
// feature vector is stored here — NOT merged into the normal baseline.
//
// Future observations are compared against stored benign patterns to
// suppress repeated false positives.

import Foundation
import SwiftData

// MARK: - In-Memory Benign Anomaly

/// In-memory representation of one user-confirmed benign event.
public struct BenignAnomaly: Sendable, Identifiable {
    public let id: UUID
    /// Named feature values at the time of the benign event.
    public let featureValues: [String: Double]
    public let timestamp: Date
    /// Free-text context the user may have provided.
    public let context: String
    /// Euclidean distance threshold for matching (0–1 normalized space).
    public let similarityThreshold: Double

    public init(
        id: UUID = UUID(),
        featureValues: [String: Double],
        timestamp: Date = Date(),
        context: String = "",
        similarityThreshold: Double = 0.25
    ) {
        self.id                  = id
        self.featureValues       = featureValues
        self.timestamp           = timestamp
        self.context             = context
        self.similarityThreshold = similarityThreshold
    }
}

// MARK: - Benign Anomaly Store

public final class BenignAnomalyStore {

    private var anomalies: [BenignAnomaly] = []
    private let modelContext: ModelContext?

    /// Maximum number of stored benign anomalies (prevents unbounded growth).
    public var maxStored: Int = 50

    public init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
    }

    // MARK: - Store

    /// Record a user-confirmed benign observation.
    /// This does NOT modify the core baseline.
    public func store(_ anomaly: BenignAnomaly) {
        // Trim oldest if at capacity
        if anomalies.count >= maxStored {
            anomalies.removeFirst()
        }
        anomalies.append(anomaly)
        persist(anomaly)
        print("[BenignAnomalyStore] Stored benign anomaly '\(anomaly.context)' (total: \(anomalies.count)).")
    }

    public func store(featureValues: [String: Double], context: String = "") {
        let anomaly = BenignAnomaly(featureValues: featureValues, context: context)
        store(anomaly)
    }

    // MARK: - Matching

    /// Returns true if the given feature values are similar enough to a known
    /// benign anomaly (within its similarityThreshold).
    public func matches(_ values: [String: Double]) -> Bool {
        for known in anomalies {
            let distance = normalizedEuclideanDistance(values, known.featureValues)
            if distance <= known.similarityThreshold {
                return true
            }
        }
        return false
    }

    /// Find the closest benign anomaly and return it, or nil if no match.
    public func closest(to values: [String: Double]) -> BenignAnomaly? {
        anomalies.min(by: {
            normalizedEuclideanDistance(values, $0.featureValues) <
            normalizedEuclideanDistance(values, $1.featureValues)
        })
    }

    // MARK: - Euclidean Distance

    /// Normalized Euclidean distance between two named-value dictionaries.
    /// Features missing from either dict contribute 0 distance.
    /// Result is approximately 0–1 for typical feature ranges.
    public static func euclideanDistance(
        _ a: [String: Double], _ b: [String: Double]
    ) -> Double {
        let keys = Set(a.keys).union(b.keys)
        guard !keys.isEmpty else { return 0 }
        var sumSq = 0.0
        for key in keys {
            let av = a[key] ?? 0
            let bv = b[key] ?? 0
            let d = av - bv
            sumSq += d * d
        }
        return sqrt(sumSq / Double(keys.count))  // normalise by feature count
    }

    private func normalizedEuclideanDistance(
        _ a: [String: Double], _ b: [String: Double]
    ) -> Double {
        Self.euclideanDistance(a, b)
    }

    // MARK: - Persistence

    private func persist(_ anomaly: BenignAnomaly) {
        guard let ctx = modelContext else { return }
        do {
            let data = try JSONEncoder().encode(anomaly.featureValues)
            let model = PersistedBenignAnomaly(
                id:                anomaly.id,
                featureVectorJSON: data,
                timestamp:         anomaly.timestamp,
                context:           anomaly.context,
                userConfirmed:     true,
                similarityThreshold: anomaly.similarityThreshold
            )
            ctx.insert(model)
            try ctx.save()
        } catch {
            print("[BenignAnomalyStore] Persist error: \(error)")
        }
    }

    public func loadFromDisk() {
        guard let ctx = modelContext else { return }
        do {
            let descriptor = FetchDescriptor<PersistedBenignAnomaly>(
                sortBy: [SortDescriptor(\.timestamp)]
            )
            let records = try ctx.fetch(descriptor)
            anomalies = records.compactMap { record in
                guard let values = try? JSONDecoder().decode(
                    [String: Double].self, from: record.featureVectorJSON
                ) else { return nil }
                return BenignAnomaly(
                    id:                 record.id,
                    featureValues:      values,
                    timestamp:          record.timestamp,
                    context:            record.context,
                    similarityThreshold: record.similarityThreshold
                )
            }
            print("[BenignAnomalyStore] Loaded \(anomalies.count) benign anomalies.")
        } catch {
            print("[BenignAnomalyStore] Load error: \(error)")
        }
    }

    public var count: Int { anomalies.count }
    public var all:   [BenignAnomaly] { anomalies }
}
