// FeatureVector.swift
// LifeOptimizer — Shared Contracts (Laptop A ↔ Laptop B integration surface)
//
// IMPORTANT: Laptop B should ONLY import these types — never ARKit or CoreMotion directly.
// All sensing types are behind protocols that conform to these contracts.

import Foundation

// MARK: - Classification

/// Anomaly classification levels.
/// Thresholds are configurable demo values — NOT clinical values.
public enum DetectionClassification: String, Codable, Sendable, CaseIterable {
    case normal = "NORMAL"
    case medium = "MEDIUM"
    case high   = "HIGH"
}

/// Configurable threshold constants. Change these to tune sensitivity.
public enum DetectionThresholds {
    /// Below this → NORMAL
    public static let normalUpperBound: Double = 0.35
    /// Below this → MEDIUM; above this → HIGH
    public static let mediumUpperBound: Double = 0.70
}

// MARK: - Facial Feature Vector

/// All ARKit-derived facial features plus computed asymmetry scores.
/// Raw blend-shape coefficients are 0.0–1.0 (ARFaceAnchor scale).
public struct FacialFeatureVector: Sendable {

    // ── Raw blend shapes ─────────────────────────────────────────────
    public var mouthSmileLeft:   Double
    public var mouthSmileRight:  Double
    public var mouthFrownLeft:   Double
    public var mouthFrownRight:  Double
    public var mouthStretchLeft: Double
    public var mouthStretchRight: Double
    public var mouthPucker:      Double
    public var mouthFunnel:      Double
    public var jawOpen:          Double

    public var eyeBlinkLeft:     Double
    public var eyeBlinkRight:    Double
    public var eyeSquintLeft:    Double
    public var eyeSquintRight:   Double

    // ── Head pose (radians from ARFaceAnchor transform) ──────────────
    public var headPitch: Double
    public var headYaw:   Double
    public var headRoll:  Double

    // ── Derived asymmetry features ───────────────────────────────────
    /// abs(L − R) / max(L + R, ε)  — emphasises one-sided drooping
    public var smileAsymmetry:   Double
    public var frownAsymmetry:   Double
    public var stretchAsymmetry: Double
    /// abs(blinkL − blinkR)
    public var blinkAsymmetry:   Double
    public var squintAsymmetry:  Double

    public var timestamp: Date

    public init(
        mouthSmileLeft:    Double = 0, mouthSmileRight:   Double = 0,
        mouthFrownLeft:    Double = 0, mouthFrownRight:   Double = 0,
        mouthStretchLeft:  Double = 0, mouthStretchRight: Double = 0,
        mouthPucker:       Double = 0, mouthFunnel:       Double = 0,
        jawOpen:           Double = 0,
        eyeBlinkLeft:      Double = 0, eyeBlinkRight:     Double = 0,
        eyeSquintLeft:     Double = 0, eyeSquintRight:    Double = 0,
        headPitch:         Double = 0, headYaw:           Double = 0,
        headRoll:          Double = 0,
        smileAsymmetry:    Double = 0, frownAsymmetry:    Double = 0,
        stretchAsymmetry:  Double = 0, blinkAsymmetry:    Double = 0,
        squintAsymmetry:   Double = 0,
        timestamp:         Date   = Date()
    ) {
        self.mouthSmileLeft    = mouthSmileLeft
        self.mouthSmileRight   = mouthSmileRight
        self.mouthFrownLeft    = mouthFrownLeft
        self.mouthFrownRight   = mouthFrownRight
        self.mouthStretchLeft  = mouthStretchLeft
        self.mouthStretchRight = mouthStretchRight
        self.mouthPucker       = mouthPucker
        self.mouthFunnel       = mouthFunnel
        self.jawOpen           = jawOpen
        self.eyeBlinkLeft      = eyeBlinkLeft
        self.eyeBlinkRight     = eyeBlinkRight
        self.eyeSquintLeft     = eyeSquintLeft
        self.eyeSquintRight    = eyeSquintRight
        self.headPitch         = headPitch
        self.headYaw           = headYaw
        self.headRoll          = headRoll
        self.smileAsymmetry    = smileAsymmetry
        self.frownAsymmetry    = frownAsymmetry
        self.stretchAsymmetry  = stretchAsymmetry
        self.blinkAsymmetry    = blinkAsymmetry
        self.squintAsymmetry   = squintAsymmetry
        self.timestamp         = timestamp
    }

    /// Returns a flat [name: value] dictionary useful for baseline keying.
    public var namedValues: [String: Double] {
        [
            "mouthSmileLeft":    mouthSmileLeft,
            "mouthSmileRight":   mouthSmileRight,
            "mouthFrownLeft":    mouthFrownLeft,
            "mouthFrownRight":   mouthFrownRight,
            "mouthStretchLeft":  mouthStretchLeft,
            "mouthStretchRight": mouthStretchRight,
            "mouthPucker":       mouthPucker,
            "mouthFunnel":       mouthFunnel,
            "jawOpen":           jawOpen,
            "eyeBlinkLeft":      eyeBlinkLeft,
            "eyeBlinkRight":     eyeBlinkRight,
            "eyeSquintLeft":     eyeSquintLeft,
            "eyeSquintRight":    eyeSquintRight,
            "headPitch":         headPitch,
            "headYaw":           headYaw,
            "headRoll":          headRoll,
            "smileAsymmetry":    smileAsymmetry,
            "frownAsymmetry":    frownAsymmetry,
            "stretchAsymmetry":  stretchAsymmetry,
            "blinkAsymmetry":    blinkAsymmetry,
            "squintAsymmetry":   squintAsymmetry,
        ]
    }
}

// MARK: - Motion Feature Vector

/// Core Motion–derived features.
public struct MotionFeatureVector: Sendable {
    public var accelerationMagnitude: Double   // sqrt(ax²+ay²+az²), g
    public var accelerationX: Double
    public var accelerationY: Double
    public var accelerationZ: Double
    /// Approximated as |a_t − a_(t-1)| / dt
    public var jerk:                  Double
    public var rotationRateX:         Double   // rad/s
    public var rotationRateY:         Double
    public var rotationRateZ:         Double
    public var rotationMagnitude:     Double
    public var pitchChange:           Double   // attitude delta
    public var rollChange:            Double
    public var yawChange:             Double
    /// ax²+ay²+az² (sum of squared components)
    public var motionEnergy:          Double
    public var timestamp: Date

    public init(
        accelerationMagnitude: Double = 0,
        accelerationX: Double = 0, accelerationY: Double = 0, accelerationZ: Double = 0,
        jerk:                  Double = 0,
        rotationRateX: Double = 0, rotationRateY: Double = 0, rotationRateZ: Double = 0,
        rotationMagnitude:     Double = 0,
        pitchChange: Double = 0, rollChange: Double = 0, yawChange: Double = 0,
        motionEnergy:          Double = 0,
        timestamp:             Date   = Date()
    ) {
        self.accelerationMagnitude = accelerationMagnitude
        self.accelerationX         = accelerationX
        self.accelerationY         = accelerationY
        self.accelerationZ         = accelerationZ
        self.jerk                  = jerk
        self.rotationRateX         = rotationRateX
        self.rotationRateY         = rotationRateY
        self.rotationRateZ         = rotationRateZ
        self.rotationMagnitude     = rotationMagnitude
        self.pitchChange           = pitchChange
        self.rollChange            = rollChange
        self.yawChange             = yawChange
        self.motionEnergy          = motionEnergy
        self.timestamp             = timestamp
    }

    public var namedValues: [String: Double] {
        [
            "accelerationMagnitude": accelerationMagnitude,
            "accelerationX":         accelerationX,
            "accelerationY":         accelerationY,
            "accelerationZ":         accelerationZ,
            "jerk":                  jerk,
            "rotationRateX":         rotationRateX,
            "rotationRateY":         rotationRateY,
            "rotationRateZ":         rotationRateZ,
            "rotationMagnitude":     rotationMagnitude,
            "pitchChange":           pitchChange,
            "rollChange":            rollChange,
            "yawChange":             yawChange,
            "motionEnergy":          motionEnergy,
        ]
    }
}

// MARK: - Depth Feature Vector (TrueDepth — optional)

/// TrueDepth-derived depth features.
/// The entire system degrades gracefully if depth is unavailable (nil).
public struct DepthFeatureVector: Sendable {
    public var leftMeanDepth:     Double  // mm
    public var rightMeanDepth:    Double
    /// abs(L − R) / ((L + R) / 2)
    public var depthAsymmetry:    Double
    public var leftDepthVariance:  Double
    public var rightDepthVariance: Double
    public var timestamp: Date

    public init(
        leftMeanDepth:      Double = 0, rightMeanDepth:     Double = 0,
        depthAsymmetry:     Double = 0,
        leftDepthVariance:  Double = 0, rightDepthVariance: Double = 0,
        timestamp:          Date   = Date()
    ) {
        self.leftMeanDepth      = leftMeanDepth
        self.rightMeanDepth     = rightMeanDepth
        self.depthAsymmetry     = depthAsymmetry
        self.leftDepthVariance  = leftDepthVariance
        self.rightDepthVariance = rightDepthVariance
        self.timestamp          = timestamp
    }
}

// MARK: - Combined Feature Vector

/// Full multimodal observation. Depth is optional.
public struct FeatureVector: Sendable {
    public var facial: FacialFeatureVector
    public var motion: MotionFeatureVector
    public var depth:  DepthFeatureVector?
    public var timestamp: Date

    public init(
        facial: FacialFeatureVector,
        motion: MotionFeatureVector,
        depth:  DepthFeatureVector? = nil,
        timestamp: Date = Date()
    ) {
        self.facial    = facial
        self.motion    = motion
        self.depth     = depth
        self.timestamp = timestamp
    }
}

// MARK: - Anomaly Sub-scores

public struct FacialScore: Sendable {
    public let totalScore:    Double
    public let smileScore:    Double
    public let blinkScore:    Double
    public let mouthScore:    Double
    public let headPoseScore: Double

    public init(totalScore: Double, smileScore: Double, blinkScore: Double,
                mouthScore: Double, headPoseScore: Double) {
        self.totalScore    = totalScore
        self.smileScore    = smileScore
        self.blinkScore    = blinkScore
        self.mouthScore    = mouthScore
        self.headPoseScore = headPoseScore
    }

    public static let zero = FacialScore(totalScore: 0, smileScore: 0,
                                          blinkScore: 0, mouthScore: 0, headPoseScore: 0)
}

public struct MotionScore: Sendable {
    public let totalScore:        Double
    public let accelerationScore: Double
    public let jerkScore:         Double
    public let gyroScore:         Double

    public init(totalScore: Double, accelerationScore: Double,
                jerkScore: Double, gyroScore: Double) {
        self.totalScore        = totalScore
        self.accelerationScore = accelerationScore
        self.jerkScore         = jerkScore
        self.gyroScore         = gyroScore
    }

    public static let zero = MotionScore(totalScore: 0, accelerationScore: 0,
                                          jerkScore: 0, gyroScore: 0)
}

public struct DepthScore: Sendable {
    public let totalScore: Double
    public init(totalScore: Double) { self.totalScore = totalScore }
    public static let zero = DepthScore(totalScore: 0)
}

public struct SpeechScore: Sendable {
    public let totalScore: Double
    public init(totalScore: Double) { self.totalScore = totalScore }
}

// MARK: - Detection Result  ← PRIMARY OUTPUT FOR LAPTOP B

/// The primary output model. Laptop B should depend only on this struct.
public struct DetectionResult: Sendable, Codable {
    public let facialScore:    Double
    public let depthScore:     Double
    public let motionScore:    Double
    public let temporalScore:  Double
    public let speechScore:    Double?
    public let finalScore:     Double
    public let classification: DetectionClassification
    public let timestamp:      Date

    public init(
        facialScore:    Double,
        depthScore:     Double,
        motionScore:    Double,
        temporalScore:  Double,
        speechScore:    Double? = nil,
        finalScore:     Double,
        classification: DetectionClassification,
        timestamp:      Date = Date()
    ) {
        self.facialScore    = facialScore
        self.depthScore     = depthScore
        self.motionScore    = motionScore
        self.temporalScore  = temporalScore
        self.speechScore    = speechScore
        self.finalScore     = finalScore
        self.classification = classification
        self.timestamp      = timestamp
    }
}

// MARK: - Detection Events  ← STATE MACHINE OUTPUT

/// Events emitted by DetectionStateMachine.
/// Laptop B subscribes to these via DetectionProvider.
public enum DetectionEvent: Sendable {
    case classificationChanged(DetectionResult)
    case escalatedToMedium(DetectionResult)
    case escalatedToHigh(DetectionResult)
    case resolvedToNormal(DetectionResult)
    case userConfirmedBenign(DetectionResult)
}

/// User response to a medium-confidence alert.
public enum UserResponse: Sendable {
    /// "I'm fine" — store benign anomaly, return to NORMAL
    case okay
    /// "I need help" — immediately escalate to HIGH
    case needsHelp
    /// No response within the timeout window — escalate to HIGH
    case timeout
}

// MARK: - Baseline Score (internal, but exposed for integration)

public struct BaselineScore: Sendable {
    /// Normalized 0-1; higher = more anomalous
    public let anomalyScore: Double
    /// Whether the observation is considered normal for baseline update purposes
    public let isNormal: Bool
    public let featureName: String
    /// Raw z-score before clamping
    public let rawZScore: Double

    public init(anomalyScore: Double, isNormal: Bool,
                featureName: String, rawZScore: Double) {
        self.anomalyScore = anomalyScore
        self.isNormal     = isNormal
        self.featureName  = featureName
        self.rawZScore    = rawZScore
    }
}
