import SwiftData
import SwiftUI

@main
struct LifeOptimizerApp: App {
    let modelContainer: ModelContainer
    @StateObject private var appState: AppState
    @StateObject private var emergencyManager: EmergencyManager

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: DetectionEvent.self, EmergencyContactRecord.self)
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
        modelContainer = container

        // --- Dependency wiring -------------------------------------------------
        // To swap in Laptop A's real engine once it exists, replace this one
        // line with the real `DetectionProvider` -- nothing else in the app
        // needs to change. See INTEGRATION_B.md.
        let detectionProvider = MockDetectionProvider()

        let apiClient = APIClient()
        let locationManager = LocationManager()
        let alarmManager = AlarmManager()
        let emergencyService = BackendEmergencyService(apiClient: apiClient)
        let emergencyManager = EmergencyManager(
            locationProvider: locationManager,
            alarmService: alarmManager,
            emergencyService: emergencyService
        )

        let appState = AppState(
            detectionProvider: detectionProvider,
            feedbackReceiver: detectionProvider,
            emergencyManager: emergencyManager
        )

        appState.configure(modelContext: container.mainContext)

        _appState = StateObject(wrappedValue: appState)
        _emergencyManager = StateObject(wrappedValue: emergencyManager)

        // Demo-mode control lives on `MockDetectionProvider` itself; expose
        // it (and the API client, for the Settings backend-URL field)
        // globally via `AppEnvironment` so views can reach them without
        // knowing concrete networking/provider types.
        AppEnvironment.shared.mockDetectionProvider = detectionProvider
        AppEnvironment.shared.apiClient = apiClient
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(appState)
                .environmentObject(emergencyManager)
                .modelContainer(modelContainer)
        }
    }
}

/// Small process-wide holder for the demo-mode hook. Kept separate from the
/// `DetectionProvider` protocol itself so the protocol stays exactly what a
/// real Laptop-A engine would implement -- demo control is a mock-only
/// concept.
final class AppEnvironment {
    static let shared = AppEnvironment()
    var mockDetectionProvider: MockDetectionProvider?
    var apiClient: APIClient?
    private init() {}
}
