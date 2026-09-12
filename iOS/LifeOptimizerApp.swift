import ARKit
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

        // --- Detection engine wiring -------------------------------------------
        // Use the real Laptop A engine when ARKit face tracking is supported
        // (physical iPhone with TrueDepth front camera).
        // Fall back to MockDetectionProvider on Simulator or unsupported devices.
        let apiClient = APIClient()

        let detectionProvider: DetectionProvider & DetectionFeedbackReceiver
        if ARFaceTrackingConfiguration.isSupported {
            // Real engine: ARKit + CoreMotion + mock TrueDepth
            let liveProvider = LiveDetectionProvider(useDemoMode: false)
            liveProvider.start()
            AppEnvironment.shared.liveDetectionProvider = liveProvider
            detectionProvider = liveProvider
        } else {
            // Simulator / unsupported device: deterministic mock
            let mockProvider = MockDetectionProvider()
            AppEnvironment.shared.mockDetectionProvider = mockProvider
            detectionProvider = mockProvider
        }

        // --- Emergency infrastructure ------------------------------------------
        let locationManager = LocationManager()
        let alarmManager    = AlarmManager()
        let emergencyService = BackendEmergencyService(apiClient: apiClient)
        let emergencyManager = EmergencyManager(
            locationProvider: locationManager,
            alarmService:     alarmManager,
            emergencyService: emergencyService
        )

        let appState = AppState(
            detectionProvider: detectionProvider,
            feedbackReceiver:  detectionProvider,
            emergencyManager:  emergencyManager
        )
        appState.configure(modelContext: container.mainContext)

        _appState       = StateObject(wrappedValue: appState)
        _emergencyManager = StateObject(wrappedValue: emergencyManager)

        AppEnvironment.shared.apiClient = apiClient
        appState.startMonitoring()
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

/// Process-wide environment holder for objects that need to be accessed
/// from SwiftUI views without threading through every EnvironmentObject.
final class AppEnvironment {
    static let shared = AppEnvironment()
    /// Set when running on a device with ARKit face tracking support.
    var liveDetectionProvider: LiveDetectionProvider?
    /// Set when running on Simulator or unsupported hardware.
    var mockDetectionProvider: MockDetectionProvider?
    var apiClient: APIClient?
    private init() {}
}
