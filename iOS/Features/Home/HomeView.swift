import SwiftData
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @Query private var contacts: [EmergencyContactRecord]
    @State private var navigateToMonitoring = false

    var body: some View {
        NavigationStack {
            List {
                Section("Personal baseline") {
                    Label("READY (demo mode)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                Section("Monitoring") {
                    Button("Start Monitoring") {
                        appState.startMonitoring()
                        navigateToMonitoring = true
                    }
                }

                Section("Emergency contact") {
                    if let contact = contacts.first, !contact.name.isEmpty {
                        Text("\(contact.name) — \(contact.phone)")
                    } else {
                        Text("Not configured").foregroundStyle(.secondary)
                    }
                }

                Section {
                    HStack {
                        ForEach(DemoMode.allCases) { mode in
                            Button(mode.label) {
                                appState.startMonitoring()
                                // Route to whichever provider is active
                                if let live = AppEnvironment.shared.liveDetectionProvider {
                                    live.setScenario(demoScenario(for: mode))
                                } else {
                                    AppEnvironment.shared.mockDetectionProvider?.trigger(mode)
                                }
                                navigateToMonitoring = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } header: {
                    Text("Demo mode")
                } footer: {
                    Text("Forces a NORMAL / MEDIUM / HIGH reading for demonstration purposes.")
                }

                Section("Privacy") {
                    Text("Your personal baseline stays on this device. Only emergency incident information is shared with the backend.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("LifeOptimizer")
            .navigationDestination(isPresented: $navigateToMonitoring) {
                MonitoringView()
            }
        }
    }

    /// Maps Laptop B's DemoMode to Laptop A's DemoScenario for the live engine.
    private func demoScenario(for mode: DemoMode) -> DemoScenario {
        switch mode {
        case .normal: return .normal
        case .medium: return .medium
        case .high:   return .high
        }
    }
}
