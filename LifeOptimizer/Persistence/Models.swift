// Models.swift
// LifeOptimizer — SwiftData Persistence Models
//
// SwiftData requires iOS 17+.
// All models are deliberately minimal — no raw sensor data stored.

import Foundation
import SwiftData

// MARK: - Persisted Baseline Feature

/// SwiftData model for one feature's statistical summary.
/// Mirrors BaselineFeatureStat but is stored on disk.
@Model
public final class PersistedBaselineFeature {
    @Attribute(.unique) public var name: String
    public var mean: Double
    public var variance: Double
    public var sampleCount: Int
    public var lastUpdated: Date

    public init(name: String, mean: Double, variance: Double,
                sampleCount: Int, lastUpdated: Date) {
        self.name        = name
        self.mean        = mean
        self.variance    = variance
        self.sampleCount = sampleCount
        self.lastUpdated = lastUpdated
    }

    /// Convert to in-memory struct used by BaselineEngine.
    public func toStat() -> BaselineFeatureStat {
        BaselineFeatureStat(name: name, mean: mean, variance: variance,
                            sampleCount: sampleCount, lastUpdated: lastUpdated)
    }

    /// Update this model from an in-memory stat.
    public func apply(_ stat: BaselineFeatureStat) {
        mean        = stat.mean
        variance    = stat.variance
        sampleCount = stat.sampleCount
        lastUpdated = stat.lastUpdated
    }
}

// MARK: - Persisted Benign Anomaly

/// User-confirmed harmless deviation stored to suppress future false positives.
@Model
public final class PersistedBenignAnomaly {
    public var id: UUID
    /// JSON-encoded [featureName: Double] dictionary
    public var featureVectorJSON: Data
    public var timestamp: Date
    /// Free-text context label (e.g. "yawning", "laughing")
    public var context: String
    public var userConfirmed: Bool
    /// Euclidean distance threshold for matching future observations
    public var similarityThreshold: Double

    public init(id: UUID = UUID(),
                featureVectorJSON: Data,
                timestamp: Date = Date(),
                context: String = "",
                userConfirmed: Bool = true,
                similarityThreshold: Double = 0.25) {
        self.id                  = id
        self.featureVectorJSON   = featureVectorJSON
        self.timestamp           = timestamp
        self.context             = context
        self.userConfirmed       = userConfirmed
        self.similarityThreshold = similarityThreshold
    }
}

// MARK: - Persisted Detection Event

/// History record of a detection event (for incident log / Laptop B review).
@Model
public final class PersistedDetectionEvent {
    public var id: UUID
    public var timestamp: Date
    public var classification: String    // DetectionClassification.rawValue
    public var facialScore: Double
    public var depthScore: Double
    public var motionScore: Double
    public var temporalScore: Double
    public var speechScore: Double       // -1 means nil/not evaluated
    public var finalScore: Double
    public var latitude: Double          // 0 if unavailable
    public var longitude: Double         // 0 if unavailable
    public var userResponse: String      // "okay" | "needsHelp" | "timeout" | "none"
    public var emergencyTriggered: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        classification: String,
        facialScore: Double, depthScore: Double,
        motionScore: Double, temporalScore: Double,
        speechScore: Double = -1,
        finalScore: Double,
        latitude: Double = 0, longitude: Double = 0,
        userResponse: String = "none",
        emergencyTriggered: Bool = false
    ) {
        self.id                 = id
        self.timestamp          = timestamp
        self.classification     = classification
        self.facialScore        = facialScore
        self.depthScore         = depthScore
        self.motionScore        = motionScore
        self.temporalScore      = temporalScore
        self.speechScore        = speechScore
        self.finalScore         = finalScore
        self.latitude           = latitude
        self.longitude          = longitude
        self.userResponse       = userResponse
        self.emergencyTriggered = emergencyTriggered
    }

    public func toDetectionResult() -> DetectionResult {
        DetectionResult(
            facialScore:    facialScore,
            depthScore:     depthScore,
            motionScore:    motionScore,
            temporalScore:  temporalScore,
            speechScore:    speechScore < 0 ? nil : speechScore,
            finalScore:     finalScore,
            classification: DetectionClassification(rawValue: classification) ?? .normal,
            timestamp:      timestamp
        )
    }
}

// MARK: - User Profile

/// Basic user profile (used by Laptop B for emergency contacts etc.)
@Model
public final class UserProfile {
    @Attribute(.unique) public var id: UUID
    public var displayName: String
    public var emergencyContactName: String
    public var emergencyContactPhone: String
    public var monitoringEnabled: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String = "",
        emergencyContactName: String = "",
        emergencyContactPhone: String = "",
        monitoringEnabled: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id                    = id
        self.displayName           = displayName
        self.emergencyContactName  = emergencyContactName
        self.emergencyContactPhone = emergencyContactPhone
        self.monitoringEnabled     = monitoringEnabled
        self.createdAt             = createdAt
    }
}

// MARK: - Schema

public extension ModelConfiguration {
    /// Shared SwiftData configuration for the LifeOptimizer container.
    static var lifeOptimizer: ModelConfiguration {
        ModelConfiguration(
            schema: Schema([
                PersistedBaselineFeature.self,
                PersistedBenignAnomaly.self,
                PersistedDetectionEvent.self,
                UserProfile.self
            ]),
            isStoredInMemoryOnly: false
        )
    }
}
