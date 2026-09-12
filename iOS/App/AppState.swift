import Foundation
import SwiftData

/// UI-facing phase of the monitoring workflow. Distinct from
/// `DetectionClassification` (which describes one detection reading) --
/// this tracks what the *app* is doing about the latest reading.
enum AppPhase: Equatable {
    case idle
    case monitoring
    case awaitingResponse
    case emergency
}

/// Drives the medium/high confidence workflow described in the spec:
/// consumes `DetectionResult`s, runs the 15-second confirmation countdown,
/// and hands off to `EmergencyManager` on HIGH. This is the one place that
/// owns "what does the app do when a reading comes in" -- screens only read
/// its published state and call `respond(_:)` / `startMonitoring()`.
@MainActor
final class AppState: ObservableObject {
    static let countdownSeconds = 15

    @Published private(set) var phase: AppPhase = .idle
    @Published private(set) var latestResult: DetectionResult?
    @Published private(set) var countdown: Int = AppState.countdownSeconds

    let detectionProvider: DetectionProvider
    let feedbackReceiver: DetectionFeedbackReceiver?
    let emergencyManager: EmergencyManager

    private var modelContext: ModelContext?
    private var listenTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var pendingMediumResult: DetectionResult?

    init(
        detectionProvider: DetectionProvider,
        feedbackReceiver: DetectionFeedbackReceiver?,
        emergencyManager: EmergencyManager
    ) {
        self.detectionProvider = detectionProvider
        self.feedbackReceiver = feedbackReceiver
        self.emergencyManager = emergencyManager
    }

    /// Must be called once the SwiftData context is available (from the
    /// root view's environment) so incidents/contacts can be read/written.
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func startMonitoring() {
        guard listenTask == nil else { return }
        phase = .monitoring
        listenTask = Task { [weak self] in
            guard let self else { return }
            for await result in self.detectionProvider.detectionStream {
                self.handle(result)
            }
        }
    }

    /// Forces the workflow back to a clean MONITORING state regardless of
    /// what it's currently doing. Meant for explicit, user-initiated
    /// "(re)start monitoring" actions -- Home's "Start Monitoring" button
    /// and the demo-mode buttons -- as opposed to `startMonitoring()`,
    /// which only starts the underlying detection stream once at app
    /// launch and is a no-op on every later call (the stream keeps running
    /// continuously in the background regardless). Without this, `phase`
    /// getting stuck at `.awaitingResponse` or `.emergency` -- e.g. you
    /// backed out of a MEDIUM demo without responding, and its 15s
    /// countdown auto-escalated in the background while you weren't
    /// looking -- silently blocked every later "Start Monitoring" tap:
    /// it re-showed the same stuck alert instead of doing anything.
    func resetToMonitoring() {
        if phase == .emergency {
            emergencyManager.markSafe()
        }
        cancelCountdown()
        pendingMediumResult = nil
        phase = .monitoring
        if listenTask == nil {
            listenTask = Task { [weak self] in
                guard let self else { return }
                for await result in self.detectionProvider.detectionStream {
                    self.handle(result)
                }
            }
        }
    }

    func stopMonitoring() {
        listenTask?.cancel()
        listenTask = nil
        cancelCountdown()
        phase = .idle
    }

    private func handle(_ result: DetectionResult) {
        latestResult = result

        switch result.classification {
        case .normal:
            guard phase != .emergency else { return }
            phase = .monitoring
            cancelCountdown()

        case .medium:
            guard phase != .emergency, phase != .awaitingResponse else { return }
            pendingMediumResult = result
            phase = .awaitingResponse
            startCountdown()

        case .high:
            guard phase != .emergency else { return }
            cancelCountdown()
            Task { await self.trigger(result: result, userResponse: nil) }
        }
    }

    /// Called by `MediumConfidenceView`'s buttons, and internally on timeout.
    func respond(_ response: UserResponse) {
        guard let result = pendingMediumResult else { return }
        cancelCountdown()
        pendingMediumResult = nil
        feedbackReceiver?.submit(response: response, for: result)

        switch response {
        case .okay:
            phase = .monitoring

        case .needsHelp, .timeout:
            // Escalate deterministically here rather than waiting on the
            // detection engine to re-emit a HIGH reading -- an unanswered
            // MEDIUM alert is itself the reason to escalate.
            let escalated = DetectionResult(
                facialScore: result.facialScore,
                depthScore: result.depthScore,
                motionScore: result.motionScore,
                temporalScore: result.temporalScore,
                speechScore: result.speechScore,
                finalScore: max(result.finalScore, DetectionConfig.highThreshold + 0.05),
                classification: .high,
                timestamp: .now
            )
            Task { await self.trigger(result: escalated, userResponse: response) }
        }
    }

    /// "I'm Safe" on the emergency screen: stop the alarm, tell the
    /// detection engine the situation resolved (as a benign confirmation),
    /// and return to normal monitoring.
    func resolveEmergency() {
        emergencyManager.markSafe()
        if let result = latestResult {
            feedbackReceiver?.submit(response: .confirmedOkay, for: result)
        }
        phase = .monitoring
    }

    private func trigger(result: DetectionResult, userResponse: UserResponse?) async {
        guard phase != .emergency else { return }
        phase = .emergency
        guard let modelContext else { return }
        let contact = try? modelContext.fetch(FetchDescriptor<EmergencyContactRecord>()).first
        await emergencyManager.handleHighConfidence(
            result,
            userResponse: userResponse,
            contact: contact,
            modelContext: modelContext
        )
    }

    private func startCountdown() {
        countdown = Self.countdownSeconds
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            guard let self else { return }
            while self.countdown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                self.countdown -= 1
            }
            if !Task.isCancelled {
                self.respond(.timeout)
            }
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = Self.countdownSeconds
    }
}
