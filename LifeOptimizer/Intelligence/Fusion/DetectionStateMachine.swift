// DetectionStateMachine.swift
// LifeOptimizer — Detection State Machine
//
// Orchestrates the full sensing pipeline:
//   NORMAL → MEDIUM_CONFIDENCE → HIGH_CONFIDENCE
//
// The state machine:
//   - Merges facial + motion streams into FeatureVectors
//   - Updates the personal baseline (only with normal observations)
//   - Emits DetectionEvents for Laptop B to consume
//   - Does NOT call 911, send SMS, or manage emergency UI (Laptop B's job)

import Foundation

// MARK: - State Machine State

public enum SMState: Equatable, Sendable {
    case idle
    case normal
    case mediumConfidence
    case highConfidence
}

/// Internal detection events emitted by the state machine.
/// LiveDetectionProvider observes these to route to Laptop B's AppState.
public enum SMDetectionEvent: Sendable {
    case classificationChanged(DetectionResult)
    case escalatedToMedium(DetectionResult)
    case escalatedToHigh(DetectionResult)
    case resolvedToNormal(DetectionResult)
    case userConfirmedBenign(DetectionResult)
}

// MARK: - Detection State Machine

@MainActor
public final class DetectionStateMachine {

    // MARK: - Dependencies

    public let faceProvider:   any FaceFeatureProvider
    public let motionProvider: any MotionFeatureProvider
    public let depthProvider:  (any TrueDepthProvider)?

    public let baselineEngine:     BaselineEngine
    public let benignAnomalyStore: BenignAnomalyStore
    public let facialDetector:     FacialAnomalyDetector
    public let motionDetector:     MotionAnomalyDetector
    public let temporalAnalyzer:   TemporalAnalyzer
    public let confidenceEngine:   ConfidenceEngine

    // MARK: - State

    public private(set) var currentState: SMState = .idle
    private var latestFacial: FacialFeatureVector?
    private var latestMotion: MotionFeatureVector?
    private var latestDepth:  DepthFeatureVector?

    private var faceTask:   Task<Void, Never>?
    private var motionTask: Task<Void, Never>?
    private var depthTask:  Task<Void, Never>?
    private var fusionTask: Task<Void, Never>?

    /// How often to compute and emit a fused DetectionResult (seconds).
    /// Lowered from 0.5s -- a real event needs to be caught within a
    /// fraction of a second, not evaluated twice a second.
    public var fusionInterval: TimeInterval = 0.2

    // MARK: - Output Streams

    private var detectionContinuation: AsyncStream<DetectionResult>.Continuation?
    private var eventContinuation:     AsyncStream<SMDetectionEvent>.Continuation?

    public lazy var detectionStream: AsyncStream<DetectionResult> = {
        AsyncStream { [weak self] continuation in
            self?.detectionContinuation = continuation
        }
    }()

    public lazy var eventStream: AsyncStream<SMDetectionEvent> = {
        AsyncStream { [weak self] continuation in
            self?.eventContinuation = continuation
        }
    }()

    // MARK: - Init

    public init(
        faceProvider:       any FaceFeatureProvider,
        motionProvider:     any MotionFeatureProvider,
        depthProvider:      (any TrueDepthProvider)? = nil,
        baselineEngine:     BaselineEngine     = BaselineEngine(),
        benignAnomalyStore: BenignAnomalyStore = BenignAnomalyStore(),
        facialDetector:     FacialAnomalyDetector  = FacialAnomalyDetector(),
        motionDetector:     MotionAnomalyDetector  = MotionAnomalyDetector(),
        temporalAnalyzer:   TemporalAnalyzer        = TemporalAnalyzer(),
        confidenceEngine:   ConfidenceEngine         = ConfidenceEngine()
    ) {
        self.faceProvider       = faceProvider
        self.motionProvider     = motionProvider
        self.depthProvider      = depthProvider
        self.baselineEngine     = baselineEngine
        self.benignAnomalyStore = benignAnomalyStore
        self.facialDetector     = facialDetector
        self.motionDetector     = motionDetector
        self.temporalAnalyzer   = temporalAnalyzer
        self.confidenceEngine   = confidenceEngine
    }

    // MARK: - Lifecycle

    public func startMonitoring() {
        guard currentState == .idle else { return }
        transition(to: .normal)

        faceProvider.start()
        motionProvider.start()
        depthProvider?.start()

        startFaceConsumer()
        startMotionConsumer()
        startDepthConsumer()
        startFusionLoop()

        print("[DetectionStateMachine] Monitoring started.")
    }

    public func stopMonitoring() {
        faceTask?.cancel();   faceTask   = nil
        motionTask?.cancel(); motionTask = nil
        depthTask?.cancel();  depthTask  = nil
        fusionTask?.cancel(); fusionTask = nil

        faceProvider.stop()
        motionProvider.stop()
        depthProvider?.stop()
        temporalAnalyzer.reset()
        transition(to: .idle)
        print("[DetectionStateMachine] Monitoring stopped.")
    }

    // MARK: - User Response

    public func submitUserResponse(_ response: UserResponse) {
        guard currentState == .mediumConfidence else { return }
        switch response {
        case .okay:
            // Store current observation as benign — do NOT update core baseline
            if let facial = latestFacial {
                benignAnomalyStore.store(
                    featureValues: facial.namedValues,
                    context: "user_confirmed_okay"
                )
            }
            let result = makeResult()
            emit(event: .userConfirmedBenign(result))
            transition(to: .normal)
            temporalAnalyzer.reset()

        case .needsHelp, .timeout:
            escalateToHigh()
        }
    }

    // MARK: - Stream Consumers

    private func startFaceConsumer() {
        faceTask = Task { [weak self] in
            guard let self else { return }
            for await vector in self.faceProvider.featureStream {
                guard !Task.isCancelled else { break }
                await MainActor.run { self.latestFacial = vector }
            }
        }
    }

    private func startMotionConsumer() {
        motionTask = Task { [weak self] in
            guard let self else { return }
            for await vector in self.motionProvider.featureStream {
                guard !Task.isCancelled else { break }
                await MainActor.run { self.latestMotion = vector }
            }
        }
    }

    private func startDepthConsumer() {
        guard let dp = depthProvider else { return }
        depthTask = Task { [weak self] in
            guard let self else { return }
            for await vector in dp.depthStream {
                guard !Task.isCancelled else { break }
                await MainActor.run { self.latestDepth = vector }
            }
        }
    }

    // MARK: - Fusion Loop

    private func startFusionLoop() {
        fusionTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let ns = UInt64(self.fusionInterval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
                await MainActor.run { self.tick() }
            }
        }
    }

    private func tick() {
        guard currentState != .idle,
              let facial = latestFacial,
              let motion = latestMotion else { return }

        // ── Score ──────────────────────────────────────────────────────────
        let facialScore = facialDetector.score(facial, baseline: baselineEngine)
        let motionScore = motionDetector.score(motion,  baseline: baselineEngine)
        let depthScore: DepthScore? = latestDepth.map { _ in DepthScore(totalScore: 0) }

        // ── Temporal ───────────────────────────────────────────────────────
        let combinedFrame = (facialScore.totalScore + motionScore.totalScore) / 2.0
        let temporalScore = temporalAnalyzer.update(frameScore: combinedFrame)

        // ── Fusion ─────────────────────────────────────────────────────────
        let result = confidenceEngine.evaluate(
            facial:   facialScore,
            depth:    depthScore,
            motion:   motionScore,
            temporal: temporalScore
        )

        // ── Baseline Update (only on normal observations) ──────────────────
        if result.classification == .normal && currentState == .normal {
            baselineEngine.updateAll(named: facial.namedValues)
            let motionNamed = Dictionary(uniqueKeysWithValues:
                motion.namedValues.map { ("motion.\($0.key)", $0.value) }
            )
            baselineEngine.updateAll(named: motionNamed)
        }

        // ── Benign Check ───────────────────────────────────────────────────
        let isBenign = benignAnomalyStore.matches(facial.namedValues)

        // ── Emit ───────────────────────────────────────────────────────────
        detectionContinuation?.yield(result)
        emit(event: .classificationChanged(result))

        // ── State Transitions ──────────────────────────────────────────────
        switch currentState {
        case .normal:
            if !isBenign && result.classification == .medium {
                escalateToMedium(result: result)
            } else if !isBenign && result.classification == .high {
                escalateToHigh()
            }

        case .mediumConfidence:
            if result.classification == .high {
                escalateToHigh()
            } else if result.classification == .normal {
                transition(to: .normal)
                emit(event: .resolvedToNormal(result))
            }

        case .highConfidence, .idle:
            break
        }
    }

    // MARK: - Transitions

    private func transition(to state: SMState) {
        guard state != currentState else { return }
        print("[DetectionStateMachine] \(currentState) → \(state)")
        currentState = state
    }

    private func escalateToMedium(result: DetectionResult) {
        transition(to: .mediumConfidence)
        emit(event: .escalatedToMedium(result))
        // Laptop B handles the 15-second timer and user prompt
    }

    private func escalateToHigh() {
        let result = makeResult()
        transition(to: .highConfidence)
        emit(event: .escalatedToHigh(result))
        // Laptop B handles location acquisition, alarm, backend call, emergency UI
    }

    // MARK: - Helpers

    private func makeResult() -> DetectionResult {
        let facial  = latestFacial ?? FacialFeatureVector()
        let motion  = latestMotion ?? MotionFeatureVector()
        let fScore  = facialDetector.score(facial, baseline: baselineEngine)
        let mScore  = motionDetector.score(motion,  baseline: baselineEngine)
        let tScore  = temporalAnalyzer.currentPersistenceScore()
        return confidenceEngine.evaluate(facial: fScore, depth: nil,
                                         motion: mScore, temporal: tScore)
    }

    private func emit(event: SMDetectionEvent) {
        eventContinuation?.yield(event)
    }
}
