import SwiftUI

struct EmergencyView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var emergencyManager: EmergencyManager

    var body: some View {
        VStack(spacing: 20) {
            Text("🚨 POSSIBLE EMERGENCY DETECTED")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text("Possible stroke-like event detected. This is not a medical diagnosis.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let result = appState.latestResult {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Facial anomaly: \(percent(result.facialScore))")
                    Text("Motion anomaly: \(percent(result.motionScore))")
                    Text("Overall confidence: \(percent(result.finalScore))")
                        .bold()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }

            VStack(spacing: 8) {
                statusRow("Location", emergencyManager.locationAcquired ? "Acquired" : "Unavailable")
                statusRow("Emergency contact", contactStatusText)
                statusRow("Trusted Circle", circleStatusText)
                statusRow("Emergency services", emergencyManager.emergencyServicesLabel)
                statusRow("Alarm", emergencyManager.alarmActive ? "ACTIVE" : "STOPPED")
                statusRow("Incident ID", emergencyManager.incidentId ?? "-")
            }

            if let error = emergencyManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button {
                appState.resolveEmergency()
            } label: {
                Text("I'm Safe")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding()
        .interactiveDismissDisabled()
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    /// Shows *who* was (simulated-)notified, not just a generic status, so
    /// it's obvious whether an emergency contact was actually configured
    /// and used for this incident -- no name/phone means Settings never
    /// had one saved when this HIGH event fired.
    private var contactStatusText: String {
        guard let contact = emergencyManager.notifiedContact, !contact.name.isEmpty else {
            return "No contact configured"
        }
        let label = contact.phone.isEmpty ? contact.name : "\(contact.name) (\(contact.phone))"
        return emergencyManager.contactNotified ? "\(label) — NOTIFIED (SIMULATED)" : "\(label) — not notified"
    }

    /// Whoever the backend found nearby in this patient's Trusted Circle,
    /// if anyone -- distinct from the fixed emergency contact above.
    private var circleStatusText: String {
        guard let name = emergencyManager.nearbyCircleMemberName else {
            return "No one nearby"
        }
        return emergencyManager.circleMemberNotified ? "\(name) — NOTIFIED (SIMULATED)" : "\(name) — not notified"
    }

    private func statusRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}
