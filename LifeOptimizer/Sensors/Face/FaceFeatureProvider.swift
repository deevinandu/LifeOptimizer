// FaceFeatureProvider.swift
// LifeOptimizer — Face Sensor Protocol
//
// Both ARKitFaceTracker and MockFaceFeatureProvider conform to this protocol.
// Laptop B should never import ARKit directly.

import Foundation

/// Provides a stream of facial feature vectors from any source (ARKit, mock, replay).
@MainActor
public protocol FaceFeatureProvider: AnyObject {
    /// Starts sensor capture. Safe to call multiple times (idempotent).
    func start()
    /// Stops sensor capture and releases resources.
    func stop()
    /// Async stream of facial feature observations.
    /// Each element is emitted once per ARKit frame (≈ 30–60 Hz when active).
    var featureStream: AsyncStream<FacialFeatureVector> { get }
    /// Whether the provider is currently active.
    var isRunning: Bool { get }
}
