// TrueDepthProvider.swift
// LifeOptimizer — TrueDepth Abstraction (Protocol + Mock)
//
// IMPORTANT: TrueDepth is auxiliary. The rest of the system works without it.
// All call sites accept DepthFeatureVector? — nil means depth is unavailable.

import Foundation
import AVFoundation

// MARK: - Protocol

/// Provides depth feature vectors from the TrueDepth camera.
/// If hardware is unavailable, substitute MockTrueDepthProvider.
public protocol TrueDepthProvider: AnyObject {
    func start()
    func stop()
    /// Async stream of depth feature observations. ~30 Hz when active.
    var depthStream: AsyncStream<DepthFeatureVector> { get }
    /// Returns true only if TrueDepth capture can actually be started.
    var isSupported: Bool { get }
    var isRunning: Bool { get }
}

// MARK: - Mock Implementation (Default / Fallback)

/// Produces plausible depth values with a small simulated asymmetry.
/// Used when TrueDepth hardware is unavailable or during testing.
public final class MockTrueDepthProvider: TrueDepthProvider {

    public var isSupported: Bool { false }
    public private(set) var isRunning = false

    private var continuation: AsyncStream<DepthFeatureVector>.Continuation?
    private var task: Task<Void, Never>?

    public lazy var depthStream: AsyncStream<DepthFeatureVector> = {
        AsyncStream { [weak self] continuation in
            self?.continuation = continuation
        }
    }()

    public init() {}

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 33_000_000) // ~30 Hz
                guard let self, self.isRunning else { break }
                let noise = Double.random(in: -2.0...2.0)
                let vec = DepthFeatureVector(
                    leftMeanDepth:      420 + noise,
                    rightMeanDepth:     422 + noise,
                    depthAsymmetry:     abs(noise) / 421.0,
                    leftDepthVariance:  1.2,
                    rightDepthVariance: 1.3
                )
                self.continuation?.yield(vec)
            }
        }
        print("[MockTrueDepthProvider] Started (mock — no real depth capture).")
    }

    public func stop() {
        isRunning = false
        task?.cancel()
        task = nil
        continuation?.finish()
        continuation = nil
    }
}

// MARK: - Real TrueDepth Provider (Stub — P2 priority)
//
// A full implementation would:
//   1. Use AVCaptureSession with AVCaptureDevice (builtInTrueDepthCamera)
//   2. Add AVCaptureDepthDataOutput
//   3. In depthDataOutput(_:didOutput:from:) convert depthData to pixel buffer
//   4. Compute left-half / right-half mean + variance per frame
//   5. Yield DepthFeatureVector
//
// This is left as a commented stub because AVFoundation depth capture
// requires physical device testing and is P2 priority for the PoC.
//
// To implement: create a class AVFoundationDepthProvider: TrueDepthProvider
// and swap it in where MockTrueDepthProvider is used.
