// MockFaceFeatureProvider.swift
// LifeOptimizer — Deterministic Mock Face Sensor
//
// Used during demo / testing. Conforms to the same FaceFeatureProvider protocol
// so it can be dropped in anywhere the real ARKitFaceTracker is used.

import Foundation

/// Deterministic demo scenarios.
public enum FaceScenario {
    /// Normal baseline behavior — low asymmetry
    case normal
    /// Subtle unilateral mouth drooping — medium anomaly
    case facialAnomaly
    /// Pronounced unilateral facial deviation — high anomaly
    case high
    /// Custom override — supply your own vector
    case custom(FacialFeatureVector)
}

@MainActor
public final class MockFaceFeatureProvider: FaceFeatureProvider {

    public private(set) var isRunning = false
    public var scenario: FaceScenario = .normal

    /// Emission interval. Default 100 ms ≈ 10 Hz (sufficient for demo).
    public var interval: TimeInterval = 0.1

    private var continuation: AsyncStream<FacialFeatureVector>.Continuation?
    private var emitTask: Task<Void, Never>?

    public lazy var featureStream: AsyncStream<FacialFeatureVector> = {
        AsyncStream { [weak self] continuation in
            self?.continuation = continuation
        }
    }()

    public init(scenario: FaceScenario = .normal) {
        self.scenario = scenario
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        emitTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isRunning else { break }
                let ns = UInt64(self.interval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
                let vec = self.makeVector()
                self.continuation?.yield(vec)
            }
        }
    }

    public func stop() {
        isRunning = false
        emitTask?.cancel()
        emitTask = nil
    }

    // MARK: - Scenario Vectors

    private func makeVector() -> FacialFeatureVector {
        switch scenario {
        case .normal:
            // Symmetric, relaxed face
            return FaceFeatureExtractor.make(
                smileLeft:  Double.random(in: 0.04...0.08),
                smileRight: Double.random(in: 0.04...0.09),
                frownLeft:  Double.random(in: 0.01...0.03),
                frownRight: Double.random(in: 0.01...0.03),
                blinkLeft:  Double.random(in: 0.0...0.05),
                blinkRight: Double.random(in: 0.0...0.05),
                pitch: Double.random(in: -0.05...0.05),
                yaw:   Double.random(in: -0.05...0.05),
                roll:  Double.random(in: -0.02...0.02)
            )

        case .facialAnomaly:
            // Left side drooping — significant smile asymmetry
            return FaceFeatureExtractor.make(
                smileLeft:  0.02,
                smileRight: 0.55,
                frownLeft:  0.40,
                frownRight: 0.08,
                blinkLeft:  0.65,
                blinkRight: 0.10,
                pitch: 0.0,
                yaw:   Double.random(in: -0.05...0.05),
                roll:  0.0
            )

        case .high:
            // Severe left-side facial paralysis simulation
            return FaceFeatureExtractor.make(
                smileLeft:  0.01,
                smileRight: 0.80,
                frownLeft:  0.75,
                frownRight: 0.05,
                stretchLeft: 0.05,
                stretchRight: 0.70,
                jawOpen:    0.25,
                blinkLeft:  0.90,
                blinkRight: 0.05,
                squintLeft: 0.0,
                squintRight: 0.55,
                pitch: 0.0, yaw: 0.0, roll: 0.0
            )

        case .custom(let v):
            return v
        }
    }
}
