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
                statusRow("Emergency contact", emergencyManager.contactNotified ? "NOTIFIED (SIMULATED)" : "-")
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

    private func statusRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}
