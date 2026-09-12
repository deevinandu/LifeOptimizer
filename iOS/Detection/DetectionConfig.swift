import Foundation

/// Fusion weights and classification thresholds, centralized so they are
/// never scattered as magic numbers. These are HACKATHON DEMO thresholds
/// only -- not clinically validated.
enum DetectionConfig {
    static let facialWeight = 0.55
    static let depthWeight = 0.15
    static let motionWeight = 0.20
    static let temporalWeight = 0.10

    static let mediumThreshold = 0.35
    static let highThreshold = 0.70

    static func finalScore(facial: Double, depth: Double, motion: Double, temporal: Double) -> Double {
        facial * facialWeight + depth * depthWeight + motion * motionWeight + temporal * temporalWeight
    }

    static func classify(_ score: Double) -> DetectionClassification {
        if score > highThreshold { return .high }
        if score >= mediumThreshold { return .medium }
        return .normal
    }
}
