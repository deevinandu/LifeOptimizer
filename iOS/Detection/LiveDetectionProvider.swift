// LiveDetectionProvider.swift
// LifeOptimizer — Adapter: Laptop A Engine → Laptop B Protocols
//
// This file is the ONLY integration seam between the two laptops.
//
// Laptop B's AppState depends on:
//   - DetectionProvider  (iOS/Detection/DetectionProvider.swift)
//   - DetectionFeedbackReceiver (iOS/Detection/DetectionProvider.swift)
//
// Laptop A's engine is DetectionStateMachine.
//
// This adapter wraps DetectionStateMachine so AppState can consume it with
// a one-line change in LifeOptimizerApp.swift:
//
//   // Replace:   let detectionProvider = MockDetectionProvider()
//   // With:      let liveProvider = LiveDetectionProvider()
//   //            liveProvider.start()
//   //            // use liveProvider as both detectionProvider and feedbackReceiver

import Foundation

// MARK: - Live Detection Provider

@MainActor
final class LiveDetectionProvider: DetectionProvider, DetectionFeedbackReceiver {

    // MARK: - DetectionProvider stream
    let detectionStream: AsyncStream<DetectionResult>
    private let streamContinuation: AsyncStream<DetectionResult>.Continuation

    // MARK: - Underlying Laptop A engine
    let stateMachine: DetectionStateMachine
    private var listenTask: Task<Void, Never>?

    // MARK: - Init

    /// - Parameters:
    ///   - useDemoMode: Use pre-warmed mock sensors (Simulator-safe, no ARKit).
    ///   - demoScenario: Initial demo scenario (only when useDemoMode=true).
    init(useDemoMode: Bool = false, demoScenario: DemoScenario = .normal) {
        var cont: AsyncStream<DetectionResult>.Continuation!
        self.detectionStream = AsyncStream { cont = $0 }
        self.streamContinuation = cont

        if useDemoMode {
            self.stateMachine = DemoDataProvider.stateMachine(for: demoScenario)
        } else {
            // Real sensing pipeline (requires physical iPhone with TrueDepth camera)
            let faceProvider   = ARKitFaceTracker()
            let motionProvider = CoreMotionProvider()
            let depthProvider  = MockTrueDepthProvider()  // P2: swap for AVFoundationDepthProvider
            self.stateMachine  = DetectionStateMachine(
                faceProvider:   faceProvider,
                motionProvider: motionProvider,
                depthProvider:  depthProvider
            )
        }
    }

    // MARK: - Lifecycle

    func start() {
        stateMachine.startMonitoring()

        listenTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await engineResult in self.stateMachine.detectionStream {
                guard !Task.isCancelled else { break }
                // Both sides share DetectionResult / DetectionClassification from AppModels.swift.
                // The engine emits them directly — no translation needed.
                self.streamContinuation.yield(engineResult)
            }
        }
    }

    func stop() {
        listenTask?.cancel()
        listenTask = nil
        stateMachine.stopMonitoring()
    }

    // MARK: - DetectionFeedbackReceiver

    /// Laptop B's AppState calls this when the user responds to a MEDIUM alert.
    /// Routes the response into the engine's benign-anomaly / baseline logic.
    func submit(response: UserResponse, for result: DetectionResult) {
        stateMachine.submitUserResponse(response)
    }

    // MARK: - Demo Scenario Control
    // Lets the Home screen's demo buttons work even with the live engine running.

    func setScenario(_ scenario: DemoScenario) {
        if let mockFace = stateMachine.faceProvider as? MockFaceFeatureProvider {
            switch scenario {
            case .normal:        mockFace.scenario = .normal
            case .facialAnomaly: mockFace.scenario = .facialAnomaly
            case .medium:        mockFace.scenario = .facialAnomaly
            case .high:          mockFace.scenario = .high
            }
        }
        if let mockMotion = stateMachine.motionProvider as? MockMotionFeatureProvider {
            switch scenario {
            case .normal:        mockMotion.scenario = .normal
            case .facialAnomaly: mockMotion.scenario = .normal
            case .medium:        mockMotion.scenario = .agitated
            case .high:          mockMotion.scenario = .high
            }
        }
    }
}
