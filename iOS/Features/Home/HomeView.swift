import SwiftData
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @Query private var contacts: [EmergencyContactRecord]
    @State private var navigateToMonitoring = false

    var body: some View {
        NavigationStack {
            List {
                Section("Monitoring") {
                    Button("Start Monitoring") {
                        appState.resetToMonitoring()
                        // Clears any stuck demo override left over from a
                        // previous MEDIUM/HIGH demo test -- otherwise the
                        // next stream tick can immediately re-escalate.
                        AppEnvironment.shared.liveDetectionProvider?.resumeRealMonitoring()
                        goToMonitoring()
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
                                appState.resetToMonitoring()
                                // Route to whichever provider is active
                                if let live = AppEnvironment.shared.liveDetectionProvider {
                                    live.setScenario(demoScenario(for: mode))
                                } else {
                                    AppEnvironment.shared.mockDetectionProvider?.trigger(mode)
                                }
                                goToMonitoring()
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
