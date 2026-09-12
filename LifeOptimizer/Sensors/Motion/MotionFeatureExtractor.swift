// MotionFeatureExtractor.swift
// LifeOptimizer — Motion Feature Computation
//
// Stateless helper that converts raw CMDeviceMotion / CMAccelerometerData
// readings into a MotionFeatureVector including jerk and energy.

import Foundation
import CoreMotion

public enum MotionFeatureExtractor {

    // MARK: - Main Entry Point

    /// Compute a MotionFeatureVector given current and previous device-motion readings.
    /// - Parameters:
    ///   - motion: Current CMDeviceMotion sample.
    ///   - previous: Previous magnitude (for jerk approximation). Pass nil on first sample.
    ///   - dt: Time interval between samples (seconds).
    public static func extract(
        from motion: CMDeviceMotion,
        previousMagnitude: Double?,
        dt: Double
    ) -> MotionFeatureVector {
        let a = motion.userAcceleration  // gravity-removed, in g
        let r = motion.rotationRate      // rad/s
        let att = motion.attitude        // pitch/roll/yaw radians

        let ax = a.x, ay = a.y, az = a.z
        let magnitude = sqrt(ax*ax + ay*ay + az*az)
        let energy = ax*ax + ay*ay + az*az

        let jerk: Double
        if let prev = previousMagnitude, dt > 0 {
            jerk = abs(magnitude - prev) / dt
        } else {
            jerk = 0
        }

        let rotMag = sqrt(r.x*r.x + r.y*r.y + r.z*r.z)

        return MotionFeatureVector(
            accelerationMagnitude: magnitude,
            accelerationX: ax,
            accelerationY: ay,
            accelerationZ: az,
            jerk:               jerk,
            rotationRateX:      r.x,
            rotationRateY:      r.y,
            rotationRateZ:      r.z,
            rotationMagnitude:  rotMag,
            pitchChange:        att.pitch,
            rollChange:         att.roll,
            yawChange:          att.yaw,
            motionEnergy:       energy,
            timestamp:          Date()
        )
    }

    /// Build a MotionFeatureVector directly from raw values (useful for testing / mock).
    public static func make(
        magnitude: Double = 0, x: Double = 0, y: Double = 0, z: Double = 0,
        jerk: Double = 0,
        rotX: Double = 0, rotY: Double = 0, rotZ: Double = 0,
        pitch: Double = 0, roll: Double = 0, yaw: Double = 0,
        timestamp: Date = Date()
    ) -> MotionFeatureVector {
        let rotMag = sqrt(rotX*rotX + rotY*rotY + rotZ*rotZ)
        return MotionFeatureVector(
            accelerationMagnitude: magnitude,
            accelerationX: x, accelerationY: y, accelerationZ: z,
            jerk: jerk,
            rotationRateX: rotX, rotationRateY: rotY, rotationRateZ: rotZ,
            rotationMagnitude: rotMag,
            pitchChange: pitch, rollChange: roll, yawChange: yaw,
            motionEnergy: x*x + y*y + z*z,
            timestamp: timestamp
        )
    }
}
