// CoreMotionProvider.swift
// LifeOptimizer — Real Core Motion Implementation
//
// Captures device motion at 50 Hz and streams MotionFeatureVector via AsyncStream.
// Safe to use from background threads; emits on its own handler queue.

import Foundation
import CoreMotion

public final class CoreMotionProvider: MotionFeatureProvider, @unchecked Sendable {

    // MARK: - Properties

    public private(set) var isRunning = false

    private let manager = CMMotionManager()
    private let queue   = OperationQueue()

    /// Update frequency (Hz). 50 Hz is a good balance for PoC.
    public var updateInterval: TimeInterval = 1.0 / 50.0

    private var continuation: AsyncStream<MotionFeatureVector>.Continuation?
    private var previousMagnitude: Double?
    private var previousTimestamp: TimeInterval?

    // MARK: - Stream

    public lazy var featureStream: AsyncStream<MotionFeatureVector> = {
        AsyncStream { [weak self] continuation in
            self?.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }
        }
    }()

    // MARK: - Lifecycle

    public init() {
        queue.name = "com.lifeoptimizer.motion"
        queue.maxConcurrentOperationCount = 1
    }

    public func start() {
        guard !isRunning else { return }
        guard manager.isDeviceMotionAvailable else {
            print("[CoreMotionProvider] Device motion not available.")
            return
        }
        manager.deviceMotionUpdateInterval = updateInterval
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, error in
            guard let self, let motion, error == nil else { return }
            self.handleMotion(motion)
        }
        isRunning = true
        print("[CoreMotionProvider] Started at \(Int(1/updateInterval)) Hz.")
    }

    public func stop() {
        guard isRunning else { return }
        manager.stopDeviceMotionUpdates()
        continuation?.finish()
        continuation = nil
        previousMagnitude = nil
        previousTimestamp = nil
        isRunning = false
        print("[CoreMotionProvider] Stopped.")
    }

    // MARK: - Handler

    private func handleMotion(_ motion: CMDeviceMotion) {
        let now = motion.timestamp
        let dt: Double
        if let prev = previousTimestamp {
            dt = now - prev
        } else {
            dt = updateInterval
        }
        previousTimestamp = now

        let vector = MotionFeatureExtractor.extract(
            from: motion,
            previousMagnitude: previousMagnitude,
            dt: dt
        )
        previousMagnitude = vector.accelerationMagnitude
        continuation?.yield(vector)
    }
}
