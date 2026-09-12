import CoreLocation
import Foundation
import UIKit

/// Continuously reports this device's location to the backend for
/// whichever Trusted Circle it has joined -- runs independent of whether
/// the Circle tab (or the app itself) is in the foreground.
///
/// This directly answers the real problem with a manual "refresh" model:
/// someone who was nearby the last time they happened to tap refresh
/// might not be nearby anymore by the time an actual emergency happens.
/// Continuous tracking needs "Always" location authorization (not just
/// "When In Use") plus the `location` UIBackgroundMode -- both configured
/// in Info.plist. If the user only grants "While Using the App" (their
/// right to refuse), this degrades to foreground-only updates rather than
/// crashing: `allowsBackgroundLocationUpdates` is only ever set `true`
/// once authorization is confirmed as `.authorizedAlways` (setting it
/// true without that authorization is a hard runtime crash, not a soft
/// failure -- so this is a real safety check, not just tidiness).
///
/// A singleton (not scoped to CircleView) so tracking survives navigating
/// away from the Circle tab, and `resumeIfNeeded()` is called at app
/// launch so it restarts automatically across relaunches without the user
/// having to reopen that screen.
@MainActor
final class CircleLocationTracker: NSObject, ObservableObject {
    static let shared = CircleLocationTracker()

    @Published private(set) var isTracking = false
    @Published private(set) var isBackgroundCapable = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastSentAt: Date?
    /// True when the system only granted "While Using the App" -- iOS
    /// itself does not let an app's *first* location prompt offer only
    /// "Always Allow" (it always includes "While Using"/"Don't Allow" too,
    /// as a deliberate anti-dark-pattern restriction we can't route
    /// around). This flag is how the UI surfaces "you'll need to flip
    /// this in Settings yourself" instead of silently running in a
    /// degraded, foreground-only mode.
    @Published private(set) var needsAlwaysUpgrade = false

    private let manager = CLLocationManager()
    private var patientId: String?
    private var memberId: String?

    private var lastSentLocation: CLLocation?
    private var lastSentTime: Date?

    // Throttling: raw GPS updates can fire many times a minute. We don't
    // need or want to hit the backend that often -- send at most every
    // `minSendInterval`, or immediately if the device has moved more than
    // `minSendDistanceMeters` (so a real, fast-moving change isn't stuck
    // waiting out the timer).
    private let minSendInterval: TimeInterval = 20
    private let minSendDistanceMeters: CLLocationDistance = 50

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.pausesLocationUpdatesAutomatically = false
    }

    /// Call once at app launch: resumes tracking automatically if a circle
    /// was already joined in a previous session.
    func resumeIfNeeded() {
        guard
            let patientId = UserDefaults.standard.string(forKey: "joinedCircleId"), !patientId.isEmpty,
            let memberId = UserDefaults.standard.string(forKey: "joinedCircleMemberId"), !memberId.isEmpty
        else { return }
        start(patientId: patientId, memberId: memberId)
    }

    func start(patientId: String, memberId: String) {
        self.patientId = patientId
        self.memberId = memberId
        manager.requestAlwaysAuthorization()
        updateBackgroundCapability(for: manager.authorizationStatus)
        manager.startUpdatingLocation()
        isTracking = true
        lastError = nil
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        isTracking = false
        isBackgroundCapable = false
        patientId = nil
        memberId = nil
        lastSentLocation = nil
        lastSentTime = nil
    }

    private func updateBackgroundCapability(for status: CLAuthorizationStatus) {
        let canRunInBackground = status == .authorizedAlways
        // Only ever set this true when truly authorized -- setting it true
        // without "Always" authorization (and the background mode) is a
        // hard crash, not a graceful failure.
        manager.allowsBackgroundLocationUpdates = canRunInBackground
        isBackgroundCapable = canRunInBackground
    }

    private func shouldSend(_ location: CLLocation) -> Bool {
        guard let lastSentLocation, let lastSentTime else { return true }
        let elapsed = Date().timeIntervalSince(lastSentTime)
        let moved = location.distance(from: lastSentLocation)
        return elapsed >= minSendInterval || moved >= minSendDistanceMeters
    }

    private func send(_ location: CLLocation) {
        guard let patientId, let memberId else { return }
        lastSentLocation = location
        lastSentTime = Date()

        Task {
            do {
                guard let apiClient = AppEnvironment.shared.apiClient else { return }
                _ = try await apiClient.updateCircleLocation(
                    patientId: patientId,
                    memberId: memberId,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
                lastSentAt = Date()
                lastError = nil
            } catch {
                lastError = "Couldn't send location: \(error.localizedDescription)"
            }
        }
    }
}

extension CircleLocationTracker: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.updateBackgroundCapability(for: status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            guard self.isTracking, self.shouldSend(location) else { return }
            self.send(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.lastError = "Location error: \(error.localizedDescription)"
        }
    }
}
