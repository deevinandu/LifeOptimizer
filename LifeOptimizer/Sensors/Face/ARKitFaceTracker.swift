// ARKitFaceTracker.swift
// LifeOptimizer — Real ARKit Face Tracking Implementation
//
// Uses ARSCNView + ARFaceAnchor to stream facial blend shapes at ~30–60 Hz.
// Requires a TrueDepth front camera (iPhone X and later).
// Must run on the main thread (ARSCNView requirement).

import ARKit
import SceneKit
import Foundation

/// Real ARKit-based implementation of FaceFeatureProvider.
/// Requires front TrueDepth camera. Falls back gracefully if not supported.
@MainActor
public final class ARKitFaceTracker: NSObject, FaceFeatureProvider {

    // MARK: - Properties

    public private(set) var isRunning = false

    private let sceneView = ARSCNView()
    private var continuation: AsyncStream<FacialFeatureVector>.Continuation?

    public lazy var featureStream: AsyncStream<FacialFeatureVector> = {
        AsyncStream { [weak self] continuation in
            self?.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.stop()
                }
            }
        }
    }()

    // MARK: - Lifecycle

    public override init() {
        super.init()
        sceneView.delegate = self
        sceneView.session.delegate = self
    }

    public func start() {
        guard !isRunning else { return }
        guard ARFaceTrackingConfiguration.isSupported else {
            print("[ARKitFaceTracker] Face tracking not supported on this device.")
            return
        }
        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = false
        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
        print("[ARKitFaceTracker] Started.")
    }

    public func stop() {
        guard isRunning else { return }
        sceneView.session.pause()
        continuation?.finish()
        continuation = nil
        isRunning = false
        print("[ARKitFaceTracker] Stopped.")
    }

    // MARK: - Internal emit

    private func emit(_ vector: FacialFeatureVector) {
        continuation?.yield(vector)
    }
}

// MARK: - ARSCNViewDelegate

extension ARKitFaceTracker: ARSCNViewDelegate {
    public func renderer(_ renderer: SCNSceneRenderer,
                         didUpdate node: SCNNode,
                         for anchor: ARAnchor) {
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }
        let vector = FaceFeatureExtractor.extract(from: faceAnchor)
        Task { @MainActor in
            self.emit(vector)
        }
    }

    public func renderer(_ renderer: SCNSceneRenderer,
                         didAdd node: SCNNode,
                         for anchor: ARAnchor) {
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }
        let vector = FaceFeatureExtractor.extract(from: faceAnchor)
        Task { @MainActor in
            self.emit(vector)
        }
    }
}

// MARK: - ARSessionDelegate

extension ARKitFaceTracker: ARSessionDelegate {
    public func session(_ session: ARSession, didFailWithError error: Error) {
        print("[ARKitFaceTracker] Session error: \(error.localizedDescription)")
        isRunning = false
    }

    public func sessionWasInterrupted(_ session: ARSession) {
        print("[ARKitFaceTracker] Session interrupted.")
    }

    public func sessionInterruptionEnded(_ session: ARSession) {
        print("[ARKitFaceTracker] Session resumed.")
        start()
    }
}
