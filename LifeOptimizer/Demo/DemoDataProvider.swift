// DemoDataProvider.swift
// LifeOptimizer — Deterministic Demo Mode
//
// Provides pre-wired DetectionStateMachine instances for each demo scenario.
// The SAME protocols are used — demo mode is just a specific configuration
// of MockFaceFeatureProvider + MockMotionFeatureProvider.
//
// USAGE (in app):
//   let sm = DemoDataProvider.stateMachine(for: .high)
//   sm.startMonitoring()
//   // subscribe to sm.detectionStream / sm.eventStream

import Foundation

// MARK: - Demo Scenario

public enum DemoScenario: String, CaseIterable {
    case normal        = "Normal"
    case facialAnomaly = "Facial Anomaly (Medium)"
    case medium        = "Medium Confidence"
    case high          = "High Confidence"
}

// MARK: - Demo Data Provider

public enum DemoDataProvider {

    /// Build a fully configured DetectionStateMachine for a given demo scenario.
    /// Uses mock providers so no real hardware is required.
    @MainActor
    public static func stateMachine(for scenario: DemoScenario) -> DetectionStateMachine {
        let (faceScenario, motionScenario) = scenarioConfig(scenario)

        let faceProvider   = MockFaceFeatureProvider(scenario: faceScenario)
        let motionProvider = MockMotionFeatureProvider(scenario: motionScenario)
        let depthProvider  = MockTrueDepthProvider()

        // Pre-warm baseline so anomaly detection fires immediately
        let baseline = prewarmBaseline()

        let sm = DetectionStateMachine(
            faceProvider:   faceProvider,
            motionProvider: motionProvider,
            depthProvider:  depthProvider,
            baselineEngine: baseline
        )

        // Faster fusion loop for snappy demo
        sm.fusionInterval = 0.3

        return sm
    }

    // MARK: - Fixed DetectionResult Snapshots (for UI preview / tests)

    /// Returns a static DetectionResult for the given scenario.
    /// Useful for SwiftUI previews or unit tests without a live state machine.
    public static func snapshotResult(for scenario: DemoScenario) -> DetectionResult {
        switch scenario {
        case .normal:
            return DetectionResult(
                facialScore: 0.10, depthScore: 0.08, motionScore: 0.08,
                temporalScore: 0.05, speechScore: nil,
                finalScore: 0.10, classification: .normal, timestamp: Date()
            )
        case .facialAnomaly:
            return DetectionResult(
                facialScore: 0.65, depthScore: 0.12, motionScore: 0.10,
                temporalScore: 0.45, speechScore: nil,
                finalScore: 0.48, classification: .medium, timestamp: Date()
            )
        case .medium:
            return DetectionResult(
                facialScore: 0.65, depthScore: 0.20, motionScore: 0.10,
                temporalScore: 0.55, speechScore: nil,
                finalScore: 0.50, classification: .medium, timestamp: Date()
            )
        case .high:
            return DetectionResult(
                facialScore: 0.85, depthScore: 0.60, motionScore: 0.80,
                temporalScore: 0.90, speechScore: nil,
                finalScore: 0.85, classification: .high, timestamp: Date()
            )
        }
    }

    // MARK: - Private

    private static func scenarioConfig(_ scenario: DemoScenario)
        -> (FaceScenario, MotionScenario)
    {
        switch scenario {
        case .normal:
            return (.normal, .normal)
        case .facialAnomaly:
            return (.facialAnomaly, .normal)
        case .medium:
            return (.facialAnomaly, .agitated)
        case .high:
            return (.high, .high)
        }
    }

    /// Build a pre-warmed baseline so anomaly detection fires without needing
    /// 30+ real observations during a demo.
    private static func prewarmBaseline() -> BaselineEngine {
        let engine = BaselineEngine(bootstrapThreshold: 5)

        // Simulate 20 "normal" facial observations
        for _ in 0..<20 {
            let fv = FaceFeatureExtractor.make(
                smileLeft: Double.random(in: 0.04...0.08),
                smileRight: Double.random(in: 0.04...0.09),
                frownLeft: Double.random(in: 0.01...0.03),
                frownRight: Double.random(in: 0.01...0.03),
                blinkLeft: Double.random(in: 0.0...0.05),
                blinkRight: Double.random(in: 0.0...0.05)
            )
            engine.updateAll(named: fv.namedValues)
        }

        // Simulate 20 "normal" motion observations
        for _ in 0..<20 {
            let mv = MotionFeatureExtractor.make(
                magnitude: 0.05,
                x: Double.random(in: 0.0...0.02),
                y: Double.random(in: 0.0...0.02),
                z: Double.random(in: 0.0...0.02),
                jerk: Double.random(in: 0.0...0.01)
            )
            let named = Dictionary(uniqueKeysWithValues:
                mv.namedValues.map { ("motion.\($0.key)", $0.value) }
            )
            engine.updateAll(named: named)
        }

        return engine
    }
}
