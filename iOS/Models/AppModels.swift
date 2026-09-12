import Foundation
import SwiftData

// MARK: - Detection contract (shared shape with Laptop A's intelligence engine)
//
// The UI only ever talks to `DetectionResult` / `DetectionClassification`.
// It must never reach into ARKit, Core Motion, or baseline internals -- see
// `Detection/DetectionProvider.swift`.

// NOTE: public — LifeOptimizer/'s engine code (ConfidenceEngine,
// DetectionStateMachine, DemoDataProvider, PersistedDetectionEvent) exposes
// these three types through its own `public` API. Even though both trees
// compile into one application target (not separate modules), Swift still
// rejects a `public` declaration whose signature uses a less-accessible
// type, so these have to be `public` too for the merged target to build.
public enum DetectionClassification: String, Codable, CaseIterable {
    case normal = "NORMAL"
    case medium = "MEDIUM"
    case high = "HIGH"

    // MARK: - Backward-compat aliases (used by Laptop B's existing views)
    static var mediumConfidence: DetectionClassification { .medium }
    static var highConfidence: DetectionClassification { .high }
}

public struct DetectionResult: Codable, Equatable {
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
public enum UserResponse: String, Codable {
    case okay           // "I'm fine" — benign anomaly stored, returns to NORMAL
    case needsHelp      // "I need help" — escalate to HIGH immediately
    case timeout        // 15-second timer expired — escalate to HIGH

    // MARK: - Backward-compat alias for Laptop B code that used .confirmedOkay
    static var confirmedOkay: UserResponse { .okay }
}

// MARK: - Mobile Carrier (for email-to-SMS gateway)

/// Major US carriers, used to route a real text through that carrier's
/// email-to-SMS gateway (e.g. `<number>@vtext.com` for Verizon) since no
/// dedicated SMS API is configured on the backend (Twilio's trial tier
/// blocks any custom message content, SMS or WhatsApp -- see
/// backend/services/notifications.py). The backend owns the actual
/// gateway-domain mapping; this enum just needs to stay in sync with it
/// for the picker labels.
enum MobileCarrier: String, Codable, CaseIterable, Identifiable {
    case verizon, att, tmobile, sprint, uscellular, googleFi, boost, cricket, metro

    var id: String { rawValue }

    var label: String {
        switch self {
        case .verizon:    return "Verizon"
        case .att:        return "AT&T"
        case .tmobile:    return "T-Mobile"
        case .sprint:     return "Sprint"
        case .uscellular: return "US Cellular"
        case .googleFi:   return "Google Fi"
        case .boost:      return "Boost Mobile"
        case .cricket:    return "Cricket"
        case .metro:      return "Metro by T-Mobile"
        }
    }
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
    /// The person being monitored (not the contact) -- so the alert text
    /// can say who it's about, e.g. "Malavika Mohan may be having...".
    var patientName: String?
    var contactName: String?
    var contactPhone: String?
    /// One of `MobileCarrier`'s raw values (e.g. "verizon", "att"), or nil.
    var contactCarrier: String?
    /// This device's stable Trusted Circle identity (see `patientId` in
    /// LifeOptimizerApp) -- lets the backend look up nearby circle members
    /// for this patient. Optional so older backend versions still decode.
    var patientId: String?
}

struct EmergencyResponse: Codable {
    var status: String
    var contactNotified: Bool
    var emergencyServices: String
    var incidentId: String
    var circleMemberNotified: Bool = false
    var circleMemberName: String?
}

// MARK: - Trusted Circle
//
// Real-time "who's near me" via Apple's Find My isn't accessible to
// third-party apps -- there's no public API to read who has shared their
// location with a user, or their coordinates. This is a from-scratch,
// opt-in equivalent: a friend/family member's own copy of the app joins a
// specific patient's circle (by entering a shareable code) and reports
// their location periodically while THEIR app is open -- no special
// background-location entitlement, so it's "best effort," not continuous.

struct JoinCircleRequest: Codable {
    var name: String
    var phone: String?
    var carrier: String?
    /// The joining device's own stable identity -- lets the backend
    /// recognize repeat joins from the same device and update rather than
    /// clone a duplicate membership.
    var memberDeviceId: String?
}

struct JoinCircleResponse: Codable {
    var memberId: String
}

struct CircleLocationUpdate: Codable {
    var latitude: Double
    var longitude: Double
}

struct CircleMember: Codable, Identifiable {
    var memberId: String
    var name: String
    var phone: String?
    var carrier: String?
    var latitude: Double?
    var longitude: Double?
    /// Raw ISO-8601 string from the backend, kept as-is rather than decoded
    /// to `Date` -- Python's `datetime.isoformat()` includes fractional
    /// seconds when non-zero, which the default JSONDecoder `.iso8601`
    /// strategy (used for the rest of this app's date fields) can't parse,
    /// and this app only ever displays it, never computes with it.
    var lastUpdated: String?
    var memberDeviceId: String?

    var id: String { memberId }
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
    /// `MobileCarrier.rawValue`, or nil if unset/unknown. Needed to route
    /// a real text through the contact's carrier's email-to-SMS gateway.
    var carrier: String?

    init(name: String = "", phone: String = "", carrier: String? = nil) {
        self.name = name
        self.phone = phone
        self.carrier = carrier
    }
}
