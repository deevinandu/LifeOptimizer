import Foundation

/// The three demo scenarios a person can force from the Home screen
/// (spec section "DEMO MODE").
enum DemoMode: String, CaseIterable, Identifiable {
    case normal
    case medium
    case high

    var id: String { rawValue }

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

/// Deterministic stand-in for Laptop A's real ARKit/Core Motion/baseline
/// engine. It conforms to exactly the interfaces a real engine would
/// (`DetectionProvider` + `DetectionFeedbackReceiver`), so the whole app can
/// be built and demoed today and Laptop A's engine can replace this with a
/// one-line change once it exists (see INTEGRATION_B.md).
final class MockDetectionProvider: DetectionProvider, DetectionFeedbackReceiver {
    let detectionStream: AsyncStream<DetectionResult>

    private let continuation: AsyncStream<DetectionResult>.Continuation
    private var tickTask: Task<Void, Never>?
    private var currentMode: DemoMode = .normal

    init() {
        var continuation: AsyncStream<DetectionResult>.Continuation!
        detectionStream = AsyncStream { continuation = $0 }
        self.continuation = continuation
        startTicking()
    }

    deinit {
        tickTask?.cancel()
        continuation.finish()
    }

    /// Called by the Home screen's Demo Mode buttons -- covers Scenarios 1
    /// (normal), 2 (trigger medium), and 5 (trigger high directly).
    func trigger(_ mode: DemoMode) {
        currentMode = mode
        emit(for: mode)
    }

    /// Scenario 3 (user confirms okay) and the "needs help"/timeout path
    /// that feeds Scenario 4. A confirmed-okay response is treated as a
    /// benign anomaly, NOT as a normal-baseline update -- a real engine
    /// would route this into its benign-anomaly store rather than the core
    /// baseline (baseline-pollution rule).
    ///
    /// Note: for `.needsHelp`/`.timeout` we only update `currentMode` (so
    /// later ticks reflect HIGH) and deliberately do NOT emit immediately --
    /// `AppState` already escalates to the emergency workflow synchronously
    /// on this response, and an extra immediate emission here could race
    /// with that and double-trigger it.
    func submit(response: UserResponse, for result: DetectionResult) {
        switch response {
        case .okay:
            currentMode = .normal
            emit(for: .normal)
        case .needsHelp, .timeout:
            currentMode = .high
        }
    }

    private func startTicking() {
        tickTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                self.emit(for: self.currentMode)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func emit(for mode: DemoMode) {
        let facial: Double
        let depth: Double
        let motion: Double
        let temporal: Double

        switch mode {
        case .normal:
            (facial, depth, motion, temporal) = (0.10, 0.05, 0.08, 0.05)
        case .medium:
            (facial, depth, motion, temporal) = (0.65, 0.40, 0.10, 0.55)
        case .high:
            (facial, depth, motion, temporal) = (0.85, 0.70, 0.80, 0.90)
        }

        let finalScore = DetectionConfig.finalScore(facial: facial, depth: depth, motion: motion, temporal: temporal)
        let result = DetectionResult(
            facialScore: facial,
            depthScore: depth,
            motionScore: motion,
            temporalScore: temporal,
            speechScore: nil,
            finalScore: finalScore,
            classification: DetectionConfig.classify(finalScore),
            timestamp: .now
        )
        continuation.yield(result)
    }
}
