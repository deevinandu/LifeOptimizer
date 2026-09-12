import Foundation

enum APIError: Error {
    case invalidResponse
    case server(statusCode: Int)
}

/// Thin URLSession client for the FastAPI backend. The base URL is
/// configurable from Settings because "localhost" only resolves to the
/// backend when running in the iOS Simulator on the same Mac -- a physical
/// iPhone demoing against a laptop backend needs the laptop's LAN IP (see
/// INTEGRATION_B.md).
final class APIClient {
    var baseURL: URL

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: URL = URL(string: "http://127.0.0.1:8000")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func health() async throws -> Bool {
        let (_, response) = try await session.data(from: baseURL.appendingPathComponent("health"))
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    func postEmergency(_ event: EmergencyEvent) async throws -> EmergencyResponse {
        try await post(path: "emergency", body: event)
    }

    func getIncident(id: String) async throws -> Data {
        let (data, response) = try await session.data(from: baseURL.appendingPathComponent("incident/\(id)"))
        try validate(response)
        return data
    }

    // MARK: - Trusted Circle

    func joinCircle(patientId: String, request: JoinCircleRequest) async throws -> JoinCircleResponse {
        try await post(path: "circle/\(patientId)/join", body: request)
    }

    func updateCircleLocation(patientId: String, memberId: String, latitude: Double, longitude: Double) async throws -> CircleMember {
        try await post(
            path: "circle/\(patientId)/members/\(memberId)/location",
            body: CircleLocationUpdate(latitude: latitude, longitude: longitude)
        )
    }

    func getCircleMembers(patientId: String) async throws -> [CircleMember] {
        try await get(path: "circle/\(patientId)/members")
    }

    func removeCircleMember(patientId: String, memberId: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("circle/\(patientId)/members/\(memberId)"))
        request.httpMethod = "DELETE"
        applyStandardHeaders(&request)
        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    private func get<Response: Decodable>(path: String) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        applyStandardHeaders(&request)
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try decoder.decode(Response.self, from: data)
    }

    private func post<Body: Encodable, Response: Decodable>(path: String, body: Body) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        applyStandardHeaders(&request)

        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try decoder.decode(Response.self, from: data)
    }

    private func applyStandardHeaders(_ request: inout URLRequest) {
        // Default is 60s -- long enough that a genuinely hung request (bad
        // URL, dead tunnel) looks indistinguishable from "still working"
        // for a good while. Fail fast and visibly instead.
        request.timeoutInterval = 10
        // ngrok's free tier serves an interstitial HTML "you're about to
        // visit..." warning page to requests it thinks come from a
        // browser, instead of proxying straight to the backend -- this
        // header opts out of that so JSON always comes back as JSON.
        request.setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw APIError.server(statusCode: http.statusCode) }
    }
}
