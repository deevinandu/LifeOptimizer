// MotionFeatureProvider.swift
// LifeOptimizer — Motion Sensor Protocol

import Foundation

/// Provides a stream of motion feature vectors from any source (CoreMotion, mock).
public protocol MotionFeatureProvider: AnyObject, Sendable {
    /// Starts sensor capture at the configured update interval.
    func start()
    /// Stops sensor capture and releases resources.
    func stop()
    /// Async stream of motion feature observations (~50 Hz when active).
    var featureStream: AsyncStream<MotionFeatureVector> { get }
    /// Whether the provider is currently active.
    var isRunning: Bool { get }
}
