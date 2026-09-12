import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \DetectionEvent.timestamp, order: .reverse) private var events: [DetectionEvent]

    var body: some View {
        NavigationStack {
            Group {
                if events.isEmpty {
                    ContentUnavailableView("No incidents yet", systemImage: "clock")
                } else {
                    List(events) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(event.classification).bold()
                                Spacer()
                                Text(event.timestamp, style: .time)
                                    .foregroundStyle(.secondary)
                            }
                            Text("Facial \(pct(event.facialScore)) · Motion \(pct(event.motionScore)) · Overall \(pct(event.finalScore))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if event.emergencyTriggered {
                                Text("Emergency triggered · Incident \(event.incidentId ?? "-")")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
        }
    }

    private func pct(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
