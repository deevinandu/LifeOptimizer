import Foundation

protocol EmergencyService {
    func triggerEmergency(event: EmergencyEvent) async throws -> EmergencyResponse
}

/// Posts the incident to our own mock backend. This does NOT contact real
/// emergency services or send a real SMS -- it only reaches the FastAPI PoC
/// backend, which itself simulates those outcomes (see backend/main.py).
final class BackendEmergencyService: EmergencyService {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func triggerEmergency(event: EmergencyEvent) async throws -> EmergencyResponse {
        try await apiClient.postEmergency(event)
    }
}
