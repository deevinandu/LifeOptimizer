import CoreLocation
import Foundation
import SwiftData

/// Orchestrates the full HIGH-confidence workflow (spec section 8):
/// acquire location -> start alarm -> generate incident id -> POST to
/// backend -> persist locally -> publish state for `EmergencyView`.
@MainActor
final class EmergencyManager: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var locationAcquired = false
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var contactNotified = false
    /// The contact this incident was (simulated-)sent to, if one was
    /// configured -- surfaced so EmergencyView can show *who*, not just a
    /// generic "NOTIFIED" boolean.
    @Published private(set) var notifiedContact: EmergencyContactRecord?
    /// Set if a Trusted Circle member was found nearby and notified (or
    /// found-but-not-notified, e.g. SMTP unconfigured) -- nil if no one in
    /// the circle was within range, or no circle exists.
    @Published private(set) var nearbyCircleMemberName: String?
    @Published private(set) var circleMemberNotified = false
    @Published private(set) var emergencyServicesLabel = "SIMULATED"
    @Published private(set) var alarmActive = false
    @Published private(set) var incidentId: String?
    @Published private(set) var errorMessage: String?

    private let locationProvider: LocationProvider
    private let alarmService: AlarmService
    private let emergencyService: EmergencyService

    init(locationProvider: LocationProvider, alarmService: AlarmService, emergencyService: EmergencyService) {
        self.locationProvider = locationProvider
        self.alarmService = alarmService
        self.emergencyService = emergencyService
    }

    func handleHighConfidence(
        _ result: DetectionResult,
        userResponse: UserResponse?,
        contact: EmergencyContactRecord?,
        modelContext: ModelContext
    ) async {
        isActive = true
        errorMessage = nil
        contactNotified = false
        locationAcquired = false
        notifiedContact = contact
        nearbyCircleMemberName = nil
        circleMemberNotified = false

        let generatedId = String(UUID().uuidString.prefix(8)).uppercased()
        incidentId = generatedId

        alarmService.start()
        alarmActive = true

        var acquiredCoordinate: CLLocationCoordinate2D?
        do {
            acquiredCoordinate = try await locationProvider.currentLocation()
            coordinate = acquiredCoordinate
            locationAcquired = true
        } catch {
            errorMessage = "Could not acquire location: \(error.localizedDescription)"
        }

        let event = EmergencyEvent(
            incidentId: generatedId,
            timestamp: result.timestamp,
            confidence: result.finalScore,
            classification: result.classification,
            location: acquiredCoordinate.map { GeoCoordinate(latitude: $0.latitude, longitude: $0.longitude) },
            signals: SignalBreakdown(
                facial: result.facialScore,
                depth: result.depthScore,
                motion: result.motionScore,
                temporal: result.temporalScore,
                speech: result.speechScore
            ),
            patientName: UserDefaults.standard.string(forKey: "patientName") ?? "Malavika Mohan",
            contactName: contact?.name,
            contactPhone: contact?.phone,
            contactCarrier: contact?.carrier,
            patientId: AppEnvironment.patientId
        )

        do {
            let response = try await emergencyService.triggerEmergency(event: event)
            contactNotified = response.contactNotified
            emergencyServicesLabel = response.emergencyServices
            nearbyCircleMemberName = response.circleMemberName
            circleMemberNotified = response.circleMemberNotified
        } catch {
            let backendMessage = "Backend unreachable: \(error.localizedDescription)"
            errorMessage = errorMessage.map { "\($0)\n\(backendMessage)" } ?? backendMessage
        }

        let record = DetectionEvent(
            timestamp: result.timestamp,
            classification: result.classification,
            facialScore: result.facialScore,
            depthScore: result.depthScore,
            motionScore: result.motionScore,
            temporalScore: result.temporalScore,
            speechScore: result.speechScore,
            finalScore: result.finalScore,
            latitude: acquiredCoordinate?.latitude,
            longitude: acquiredCoordinate?.longitude,
            userResponse: userResponse,
            emergencyTriggered: true,
            incidentId: generatedId
        )
        modelContext.insert(record)
        try? modelContext.save()
    }

    /// "I'm Safe" button: stop the alarm and record the cancellation. The
    /// incident stays in local history but is no longer actively escalating.
    func markSafe() {
        alarmService.stop()
        alarmActive = false
        isActive = false
    }
}
