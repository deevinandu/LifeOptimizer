import SwiftData
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @Query private var contacts: [EmergencyContactRecord]
    @State private var navigateToMonitoring = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        appState.resetToMonitoring()
                        // Clears any stuck demo override left over from a
                        // previous MEDIUM/HIGH demo test -- otherwise the
                        // next stream tick can immediately re-escalate.
                        AppEnvironment.shared.liveDetectionProvider?.resumeRealMonitoring()
                        goToMonitoring()
                    } label: {
                        Label("Start Monitoring", systemImage: "shield.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.vertical, 4)
                } footer: {
                    Text("Begins live facial and motion monitoring using your on-device baseline.")
                }

                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(DemoMode.allCases) { mode in
                            Button {
                                appState.resetToMonitoring()
                                // Route to whichever provider is active
                                if let live = AppEnvironment.shared.liveDetectionProvider {
                                    live.setScenario(demoScenario(for: mode))
                                } else {
                                    AppEnvironment.shared.mockDetectionProvider?.trigger(mode)
                                }
                                goToMonitoring()
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: mode.symbolName)
                                        .font(.title3)
                                    Text(mode.label)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 64)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                } header: {
                    Text("Demo mode")
                } footer: {
                    Text("Forces a NORMAL / MEDIUM / HIGH reading for demonstration purposes.")
                }

                Section("Emergency contact") {
                    if let contact = contacts.first, !contact.name.isEmpty {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.name)
                                Text(contact.phone)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "person.crop.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    } else {
                        Label {
                            Text("Not configured — add one in Settings")
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section("Privacy") {
                    Text("Your personal baseline stays on this device. Only emergency incident information is shared with the backend.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("StrOK")
            .navigationDestination(isPresented: $navigateToMonitoring) {
                MonitoringView()
            }
        }
    }

    /// Forces a genuine false -> true transition on `navigateToMonitoring`
    /// every time, instead of just setting it to `true`. `MonitoringView`
    /// presents a `.fullScreenCover` (the Emergency screen) on top of this
    /// pushed destination, and that combination is a known SwiftUI quirk
    /// where `navigationDestination(isPresented:)`'s binding doesn't
    /// reliably reset to `false` when popped -- so a plain `= true` here
    /// can silently no-op (SwiftUI sees "still true", nothing changes) if
    /// it was already stuck `true` from the previous visit. Resetting
    /// first, then setting true on the next run loop turn, guarantees the
    /// navigation actually fires.
    private func goToMonitoring() {
        navigateToMonitoring = false
        DispatchQueue.main.async {
            navigateToMonitoring = true
        }
    }

    /// Maps Laptop B's DemoMode to Laptop A's DemoScenario for the live engine.
    private func demoScenario(for mode: DemoMode) -> DemoScenario {
        switch mode {
        case .normal:        return .normal
        case .facialAnomaly: return .facialAnomaly
        case .medium:        return .medium
        case .high:          return .high
        }
    }
}

private extension DemoMode {
    var symbolName: String {
        switch self {
        case .normal: return "checkmark.circle"
        case .facialAnomaly: return "face.dashed"
        case .medium: return "exclamationmark.triangle"
        case .high: return "bolt.trianglebadge.exclamationmark"
        }
    }
}
