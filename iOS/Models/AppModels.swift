import Foundation
import SwiftData

// MARK: - Detection contract (shared shape with Laptop A's intelligence engine)
//
// The UI only ever talks to `DetectionResult` / `DetectionClassification`.
// It must never reach into ARKit, Core Motion, or baseline internals -- see
// `Detection/DetectionProvider.swift`.

enum DetectionClassification: String, Codable, CaseIterable {
    case normal = "NORMAL"
    case medium = "MEDIUM"
    case high = "HIGH"

    // MARK: - Backward-compat aliases (used by Laptop B's existing views)
    static var mediumConfidence: DetectionClassification { .medium }
    static var highConfidence: DetectionClassification { .high }
}

struct DetectionResult: Codable, Equatable {
    var facialScore: Double
    var depthScore: Double
    var motionScore: Double
    var temporalScore: Double
    var speechScore: Double?
    var finalScore: Double
    var classification: DetectionClassification
    var timestamp: Date
}

/// How the user responded to a MEDIUM-confidence prompt (or failed to).
enum UserResponse: String, Codable {
    case okay           // "I'm fine" — benign anomaly stored, returns to NORMAL
    case needsHelp      // "I need help" — escalate to HIGH immediately
    case timeout        // 15-second timer expired — escalate to HIGH

    // MARK: - Backward-compat alias for Laptop B code that used .confirmedOkay
    static var confirmedOkay: UserResponse { .okay }
}

// MARK: - Emergency / networking payloads

struct GeoCoordinate: Codable, Equatable {
    var latitude: Double
    var longitude: Double
}

struct SignalBreakdown: Codable, Equatable {
    var facial: Double
    var depth: Double?
    var motion: Double
    var temporal: Double?
    var speech: Double?
}

/// Body sent to `POST /emergency`. Deliberately carries only scores, a
/// classification label, location, and identifiers -- never raw facial
/// frames, depth maps, or the on-device personal baseline.
struct EmergencyEvent: Codable {
    var incidentId: String
    var timestamp: Date
    var confidence: Double
    var classification: DetectionClassification
    var location: GeoCoordinate?
    var signals: SignalBreakdown
    var contactName: String?
    var contactPhone: String?
}

struct EmergencyResponse: Codable {
    var status: String
    var contactNotified: Bool
    var emergencyServices: String
    var incidentId: String
}

struct IncidentResponse: Codable {
    var status: String
    var incidentId: String
}

// MARK: - Speech (stretch goal, not wired into the MVP flow)

struct SpeechResult: Codable {
    var slurScore: Double
    var confidence: Double
}

// MARK: - Local persistence (SwiftData)

/// A locally-stored record of one detection/incident. Only scores,
/// classification, location, and outcome are persisted -- no raw sensor
/// streams, per the project's privacy model.
@Model
final class DetectionEvent {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var classification: String
    var facialScore: Double
    var depthScore: Double
    var motionScore: Double
    var temporalScore: Double
    var speechScore: Double?
    var finalScore: Double
    var latitude: Double?
    var longitude: Double?
    var userResponse: String?
    var emergencyTriggered: Bool
    var incidentId: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        classification: DetectionClassification,
        facialScore: Double,
        depthScore: Double,
        motionScore: Double,
        temporalScore: Double,
        speechScore: Double? = nil,
        finalScore: Double,
        latitude: Double? = nil,
        longitude: Double? = nil,
        userResponse: UserResponse? = nil,
        emergencyTriggered: Bool = false,
        incidentId: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.classification = classification.rawValue
        self.facialScore = facialScore
        self.depthScore = depthScore
        self.motionScore = motionScore
        self.temporalScore = temporalScore
        self.speechScore = speechScore
        self.finalScore = finalScore
        self.latitude = latitude
        self.longitude = longitude
        self.userResponse = userResponse?.rawValue
        self.emergencyTriggered = emergencyTriggered
        self.incidentId = incidentId
    }
}

/// Single emergency-contact record configured in Settings. Modeled as a
/// SwiftData entity (rather than plain UserDefaults) so it participates in
/// the same local store as everything else and is easy to query/observe.
@Model
final class EmergencyContactRecord {
    var name: String
    var phone: String

    init(name: String = "", phone: String = "") {
        self.name = name
        self.phone = phone
    }
}
