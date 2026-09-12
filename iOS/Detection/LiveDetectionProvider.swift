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

    // MARK: - Forced demo-scenario override
    //
    // On a physical device the real engine's providers are ARKitFaceTracker /
    // CoreMotionProvider, not mocks -- so setScenario's mock-casting below is
    // a no-op there, and Home's demo buttons silently did nothing. A real
    // facial anomaly is also nearly impossible to hold steady: the fusion
    // loop re-evaluates every `fusionInterval` and reverts to NORMAL the
    // instant your face relaxes, so a real test flickers and vanishes before
    // anyone can react. While a scenario is forced, we suppress the real
    // engine's stream and emit a fixed, ticking snapshot instead -- the same
    // deterministic behavior MockDetectionProvider gives Simulator users,
    // just hosted here so it works on-device too.
    private var forcedScenario: DemoScenario?
    private var demoTask: Task<Void, Never>?

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
                // Suppressed while a demo scenario is forced (see
                // `forcedScenario`) so real (near-zero, NORMAL) readings
                // don't race with -- and instantly cancel -- a forced
                // MEDIUM/HIGH demo reading.
                guard self.forcedScenario == nil else { continue }
                // Both sides share DetectionResult / DetectionClassification from AppModels.swift.
                // The engine emits them directly — no translation needed.
                self.streamContinuation.yield(engineResult)
            }
        }
    }

    func stop() {
        listenTask?.cancel()
        listenTask = nil
        demoTask?.cancel()
        demoTask = nil
        stateMachine.stopMonitoring()
    }

    // MARK: - DetectionFeedbackReceiver

    /// Laptop B's AppState calls this when the user responds to a MEDIUM alert.
    /// Routes the response into the engine's benign-anomaly / baseline logic --
    /// unless a demo scenario is currently forced, in which case there's no
    /// real MEDIUM reading to resolve, so we mirror MockDetectionProvider's
    /// behavior instead.
    func submit(response: UserResponse, for result: DetectionResult) {
        guard forcedScenario != nil else {
            stateMachine.submitUserResponse(response)
            return
        }
        switch response {
        case .okay:
            setScenario(.normal)
        case .needsHelp, .timeout:
            // AppState already escalates to the emergency workflow
            // synchronously on this response (see AppState.respond(_:)) --
            // an immediate re-emission here would race with that, so we
            // only update what the next tick reflects, same as
            // MockDetectionProvider does.
            forcedScenario = .high
        }
    }

    // MARK: - Demo Scenario Control
    // Lets the Home screen's demo buttons work whether the live engine is
    // backed by mocks (Simulator/demo mode) or real ARKit/CoreMotion (device).

    func setScenario(_ scenario: DemoScenario) {
        if let mockFace = stateMachine.faceProvider as? MockFaceFeatureProvider {
            // Simulator/demo-mode engine: drive the mocks directly so the
            // full real pipeline (baseline, anomaly detectors, fusion) still
            // runs on top of synthetic sensor input.
            switch scenario {
            case .normal:        mockFace.scenario = .normal
            case .facialAnomaly: mockFace.scenario = .facialAnomaly
            case .medium:        mockFace.scenario = .facialAnomaly
            case .high:          mockFace.scenario = .high
            }
            if let mockMotion = stateMachine.motionProvider as? MockMotionFeatureProvider {
                switch scenario {
                case .normal:        mockMotion.scenario = .normal
                case .facialAnomaly: mockMotion.scenario = .normal
                case .medium:        mockMotion.scenario = .agitated
                case .high:          mockMotion.scenario = .high
                }
            }
            forcedScenario = nil
            demoTask?.cancel()
            demoTask = nil
            return
        }

        // Real hardware: there are no mocks to drive, so force a fixed,
        // ticking snapshot instead (suppressing the real engine's stream --
        // see the `listenTask` guard above) until a different scenario is
        // chosen.
        forcedScenario = scenario
        demoTask?.cancel()
        demoTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                guard let current = self.forcedScenario else { break }
                self.streamContinuation.yield(DemoDataProvider.snapshotResult(for: current))
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
}
