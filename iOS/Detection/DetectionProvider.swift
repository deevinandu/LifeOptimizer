import Foundation

/// The one interface the application layer depends on for sensing. Laptop
/// A's real ARKit/Core Motion/baseline/fusion engine and our
/// `MockDetectionProvider` both conform to this -- the UI never knows or
/// cares which one is plugged in.
protocol DetectionProvider {
    var detectionStream: AsyncStream<DetectionResult> { get }
}

/// Companion protocol so the UI can report a user's response to a
/// MEDIUM-confidence prompt back to whichever engine is running, WITHOUT
/// touching baseline/anomaly internals directly (see the "baseline
/// pollution rule" -- an anomalous observation must never silently update
/// the core baseline; only the engine that owns the baseline may decide
/// what a confirmed-okay response means for it).
protocol DetectionFeedbackReceiver {
    func submit(response: UserResponse, for result: DetectionResult)
}
