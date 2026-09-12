// MockDetectionProvider.swift
// LifeOptimizer — Lightweight Mock for Laptop B Integration Testing
//
// Laptop B can use this without needing ARKit or CoreMotion to be available.
// Just inject MockDetectionProvider wherever DetectionProvider is expected.

import Foundation

@MainActor
public final class MockDetectionProvider: DetectionProvider {

    public private(set) var currentState: SMState = .idle

    private var detectionCont: AsyncStream<DetectionResult>.Continuation?
    private var eventCont:     AsyncStream<DetectionEvent>.Continuation?
    private var emitTask:      Task<Void, Never>?

    public var scenario: DemoScenario = .normal
    public var emitInterval: TimeInterval = 1.0

    public lazy var detectionStream: AsyncStream<DetectionResult> = {
        AsyncStream { [weak self] cont in self?.detectionCont = cont }
    }()

    public lazy var eventStream: AsyncStream<DetectionEvent> = {
        AsyncStream { [weak self] cont in self?.eventCont = cont }
    }()

    public init(scenario: DemoScenario = .normal) {
        self.scenario = scenario
    }

    // MARK: - DetectionProvider

    public func startMonitoring() {
        guard currentState == .idle else { return }
        currentState = .normal
        emitTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let ns = UInt64(self.emitInterval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
                self.emitCurrent()
            }
        }
    }

    public func stopMonitoring() {
        emitTask?.cancel()
        emitTask = nil
        currentState = .idle
    }

    public func submitUserResponse(_ response: UserResponse) {
        switch response {
        case .okay:
            currentState = .normal
            let r = DemoDataProvider.snapshotResult(for: .normal)
            eventCont?.yield(.userConfirmedBenign(r))
        case .needsHelp, .timeout:
            currentState = .highConfidence
            let r = DemoDataProvider.snapshotResult(for: .high)
            eventCont?.yield(.escalatedToHigh(r))
        }
    }

    // MARK: - Manual Scenario Injection (for Laptop B testing)

    public func inject(scenario: DemoScenario) {
        self.scenario = scenario
        emitCurrent()

        switch scenario {
        case .normal:
            currentState = .normal
        case .facialAnomaly, .medium:
            currentState = .mediumConfidence
            let r = DemoDataProvider.snapshotResult(for: scenario)
            eventCont?.yield(.escalatedToMedium(r))
        case .high:
            currentState = .highConfidence
            let r = DemoDataProvider.snapshotResult(for: .high)
            eventCont?.yield(.escalatedToHigh(r))
        }
    }

    private func emitCurrent() {
        let result = DemoDataProvider.snapshotResult(for: scenario)
        detectionCont?.yield(result)
        eventCont?.yield(.classificationChanged(result))
    }
}
