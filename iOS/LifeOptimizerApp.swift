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
        //
        // Seed from whatever SettingsView last persisted (same UserDefaults
        // key as its @AppStorage) so a URL you applied on a previous launch
        // is still in effect -- previously this always hardcoded 127.0.0.1
        // at startup regardless of what you'd set in Settings.
        let storedBackendURLString = UserDefaults.standard.string(forKey: "backendURLString")
        let backendURL = storedBackendURLString.flatMap(URL.init(string:))
            ?? URL(string: "http://127.0.0.1:8000")!
        let apiClient = APIClient(baseURL: backendURL)

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

        // Resume Trusted Circle location reporting if this device already
        // joined one in a previous session -- otherwise it'd only restart
        // once the user happens to reopen the Circle tab.
        CircleLocationTracker.shared.resumeIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(emergencyManager)
                .modelContainer(modelContainer)
        }
    }
}

/// Gates first-launch setup (personal baseline calibration + emergency
/// contact) in front of the normal app. Monitoring itself always starts at
/// launch regardless (see LifeOptimizerApp.init) -- this only decides
/// whether the onboarding UI or the regular tab UI is what's on screen.
/// Demo mode (Home's Normal / Facial Anomaly / Medium / High buttons)
/// stays available in RootTabView either way.
private struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            RootTabView()
        } else {
            OnboardingView {
                hasCompletedOnboarding = true
            }
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

    /// This device's stable Trusted Circle identity -- generated once and
    /// persisted, not tied to any account system. Shared with a friend's
    /// device (as a short code) so they can join this patient's circle;
    /// also sent along with every emergency so the backend can look up
    /// nearby circle members for this specific patient.
    static var patientId: String {
        if let existing = UserDefaults.standard.string(forKey: "patientId") {
            return existing
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "patientId")
        return id
    }
}
