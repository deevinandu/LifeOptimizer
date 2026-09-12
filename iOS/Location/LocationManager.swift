import CoreLocation
import Foundation

protocol LocationProvider {
    func currentLocation() async throws -> CLLocationCoordinate2D
}

enum LocationError: Error {
    case authorizationDenied
    case unavailable
}

/// Thin async wrapper around `CLLocationManager`. Only ever called on
/// demand (from `EmergencyManager` when a HIGH-confidence event fires) --
/// per the privacy model, location is NOT continuously tracked during
/// normal monitoring.
final class LocationManager: NSObject, LocationProvider, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func currentLocation() async throws -> CLLocationCoordinate2D {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            requestAuthorizationIfNeeded()
            manager.requestLocation()
        }
    }

    private func requestAuthorizationIfNeeded() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            continuation?.resume(throwing: LocationError.authorizationDenied)
            continuation = nil
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            continuation?.resume(throwing: LocationError.unavailable)
            continuation = nil
            return
        }
        continuation?.resume(returning: location.coordinate)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
