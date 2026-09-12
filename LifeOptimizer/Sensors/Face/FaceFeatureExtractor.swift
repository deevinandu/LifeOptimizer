// FaceFeatureExtractor.swift
// LifeOptimizer — Asymmetry + Derived Feature Computation
//
// Stateless helper that converts raw ARFaceAnchor blend-shape coefficients
// into a FacialFeatureVector including all derived asymmetry features.

import ARKit
import simd

public enum FaceFeatureExtractor {

    // Small value to avoid division by zero
    private static let epsilon: Double = 1e-6

    // MARK: - Main Entry Point

    /// Extract a full FacialFeatureVector from an ARFaceAnchor.
    /// - Parameter anchor: The live ARFaceAnchor from ARKit.
    /// - Returns: A fully populated FacialFeatureVector with raw and derived features.
    public static func extract(from anchor: ARFaceAnchor) -> FacialFeatureVector {
        let bs = anchor.blendShapes

        // Raw coefficients
        let smileL   = value(bs, .mouthSmileLeft)
        let smileR   = value(bs, .mouthSmileRight)
        let frownL   = value(bs, .mouthFrownLeft)
        let frownR   = value(bs, .mouthFrownRight)
        let stretchL = value(bs, .mouthStretchLeft)
        let stretchR = value(bs, .mouthStretchRight)
        let blinkL   = value(bs, .eyeBlinkLeft)
        let blinkR   = value(bs, .eyeBlinkRight)
        let squintL  = value(bs, .eyeSquintLeft)
        let squintR  = value(bs, .eyeSquintRight)

        // Head pose
        let (pitch, yaw, roll) = headPose(from: anchor.transform)

        return FacialFeatureVector(
            mouthSmileLeft:    smileL,
            mouthSmileRight:   smileR,
            mouthFrownLeft:    frownL,
            mouthFrownRight:   frownR,
            mouthStretchLeft:  stretchL,
            mouthStretchRight: stretchR,
            mouthPucker:       value(bs, .mouthPucker),
            mouthFunnel:       value(bs, .mouthFunnel),
            jawOpen:           value(bs, .jawOpen),
            eyeBlinkLeft:      blinkL,
            eyeBlinkRight:     blinkR,
            eyeSquintLeft:     squintL,
            eyeSquintRight:    squintR,
            headPitch:         pitch,
            headYaw:           yaw,
            headRoll:          roll,
            smileAsymmetry:    normalizedAsymmetry(smileL, smileR),
            frownAsymmetry:    normalizedAsymmetry(frownL, frownR),
            stretchAsymmetry:  normalizedAsymmetry(stretchL, stretchR),
            blinkAsymmetry:    abs(blinkL - blinkR),
            squintAsymmetry:   abs(squintL - squintR),
            timestamp:         Date()
        )
    }

    // MARK: - Synthetic Vector for Tests / Mock

    /// Build a FacialFeatureVector from raw values (useful for testing).
    public static func make(
        smileLeft: Double = 0, smileRight: Double = 0,
        frownLeft: Double = 0, frownRight: Double = 0,
        stretchLeft: Double = 0, stretchRight: Double = 0,
        pucker: Double = 0, funnel: Double = 0, jawOpen: Double = 0,
        blinkLeft: Double = 0, blinkRight: Double = 0,
        squintLeft: Double = 0, squintRight: Double = 0,
        pitch: Double = 0, yaw: Double = 0, roll: Double = 0,
        timestamp: Date = Date()
    ) -> FacialFeatureVector {
        FacialFeatureVector(
            mouthSmileLeft:    smileLeft,
            mouthSmileRight:   smileRight,
            mouthFrownLeft:    frownLeft,
            mouthFrownRight:   frownRight,
            mouthStretchLeft:  stretchLeft,
            mouthStretchRight: stretchRight,
            mouthPucker:       pucker,
            mouthFunnel:       funnel,
            jawOpen:           jawOpen,
            eyeBlinkLeft:      blinkLeft,
            eyeBlinkRight:     blinkRight,
            eyeSquintLeft:     squintLeft,
            eyeSquintRight:    squintRight,
            headPitch:         pitch,
            headYaw:           yaw,
            headRoll:          roll,
            smileAsymmetry:    normalizedAsymmetry(smileLeft, smileRight),
            frownAsymmetry:    normalizedAsymmetry(frownLeft, frownRight),
            stretchAsymmetry:  normalizedAsymmetry(stretchLeft, stretchRight),
            blinkAsymmetry:    abs(blinkLeft - blinkRight),
            squintAsymmetry:   abs(squintLeft - squintRight),
            timestamp:         timestamp
        )
    }

    // MARK: - Asymmetry Formulas

    /// Normalized asymmetry: abs(L − R) / max(L + R, ε)
    /// Returns 0 when both sides are equal, approaches 1 as one side dominates.
    public static func normalizedAsymmetry(_ left: Double, _ right: Double) -> Double {
        let diff = abs(left - right)
        let sum  = left + right
        return diff / max(sum, epsilon)
    }

    /// Simple absolute asymmetry: abs(L − R)
    public static func absoluteAsymmetry(_ left: Double, _ right: Double) -> Double {
        abs(left - right)
    }

    // MARK: - Private Helpers

    private static func value(
        _ shapes: [ARFaceAnchor.BlendShapeLocation: NSNumber],
        _ key: ARFaceAnchor.BlendShapeLocation
    ) -> Double {
        Double(truncating: shapes[key] ?? 0)
    }

    /// Decompose the 4×4 ARFaceAnchor transform into Euler angles (radians).
    private static func headPose(from transform: simd_float4x4) -> (pitch: Double, yaw: Double, roll: Double) {
        // Extract rotation matrix from the transform
        let r = transform
        // Standard Euler decomposition (Y-up, right-handed)
        let pitch = Double(asin(-r[2][1]))
        let yaw   = Double(atan2(r[2][0], r[2][2]))
        let roll  = Double(atan2(r[0][1], r[1][1]))
        return (pitch, yaw, roll)
    }
}
