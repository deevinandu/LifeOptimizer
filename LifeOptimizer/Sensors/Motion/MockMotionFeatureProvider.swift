// MockMotionFeatureProvider.swift
// LifeOptimizer — Deterministic Mock Motion Sensor

import Foundation

/// Deterministic demo scenarios for motion.
public enum MotionScenario {
    case normal        // Still phone, low variance
    case agitated      // Moving phone — medium anomaly
    case high          // Sudden drop / violent movement
    case custom(MotionFeatureVector)
}

public final class MockMotionFeatureProvider: MotionFeatureProvider, @unchecked Sendable {

    public private(set) var isRunning = false
    public var scenario: MotionScenario = .normal
    public var interval: TimeInterval = 0.1

    private var continuation: AsyncStream<MotionFeatureVector>.Continuation?
    private var emitTask: Task<Void, Never>?

    public lazy var featureStream: AsyncStream<MotionFeatureVector> = {
        AsyncStream { [weak self] continuation in
            self?.continuation = continuation
        }
    }()

    public init(scenario: MotionScenario = .normal) {
        self.scenario = scenario
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        emitTask = Task { [weak self] in
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

    private func makeVector() -> MotionFeatureVector {
        switch scenario {
        case .normal:
            let n = Double.random(in: 0.0...0.05)
            return MotionFeatureExtractor.make(
                magnitude: 0.05 + n, x: n, y: n * 0.5, z: n * 0.3,
                jerk: Double.random(in: 0.0...0.02)
            )
        case .agitated:
            let n = Double.random(in: 0.2...0.5)
            return MotionFeatureExtractor.make(
                magnitude: 0.5 + n, x: n, y: n * 0.8, z: n * 0.6,
                jerk: Double.random(in: 0.3...0.8),
                rotX: Double.random(in: 0.1...0.5),
                rotY: Double.random(in: 0.1...0.5)
            )
        case .high:
            let n = Double.random(in: 1.5...3.0)
            return MotionFeatureExtractor.make(
                magnitude: n, x: n * 0.7, y: n * 0.8, z: n * 0.5,
                jerk: Double.random(in: 2.0...5.0),
                rotX: Double.random(in: 1.0...2.0),
                rotY: Double.random(in: 1.0...2.0),
                rotZ: Double.random(in: 0.5...1.5)
            )
        case .custom(let v):
            return v
        }
    }
}
