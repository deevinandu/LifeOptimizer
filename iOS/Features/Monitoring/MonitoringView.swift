import SwiftUI

struct MonitoringView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 32) {
            ScoreBar(title: "FACIAL", value: appState.latestResult?.facialScore ?? 0)
            ScoreBar(title: "MOTION", value: appState.latestResult?.motionScore ?? 0)

            VStack(spacing: 4) {
                Text("STATUS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(statusLabel)
                    .font(.title2.bold())
                    .foregroundStyle(statusColor)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Monitoring")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: isAwaitingResponse) {
            MediumConfidenceView()
        }
        .fullScreenCover(isPresented: isEmergency) {
            EmergencyView()
        }
    }

    private var isAwaitingResponse: Binding<Bool> {
        Binding(get: { appState.phase == .awaitingResponse }, set: { _ in })
    }

    private var isEmergency: Binding<Bool> {
        Binding(get: { appState.phase == .emergency }, set: { _ in })
    }

    private var statusLabel: String {
        switch appState.latestResult?.classification {
        case .none, .some(.normal): return "NORMAL"
        case .some(.mediumConfidence): return "MEDIUM CONFIDENCE"
        case .some(.highConfidence): return "HIGH CONFIDENCE"
        }
    }

    private var statusColor: Color {
        switch appState.latestResult?.classification {
        case .none, .some(.normal): return .green
        case .some(.mediumConfidence): return .orange
        case .some(.highConfidence): return .red
        }
    }
}

private struct ScoreBar: View {
    let title: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor)
                        .frame(width: proxy.size.width * CGFloat(min(max(value, 0), 1)))
                }
            }
            .frame(height: 18)
            Text("\(Int((value * 100).rounded()))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var barColor: Color {
        switch value {
        case ..<DetectionConfig.mediumThreshold: return .green
        case ..<DetectionConfig.highThreshold: return .orange
        default: return .red
        }
    }
}
