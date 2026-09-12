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

    private func post<Body: Encodable, Response: Decodable>(path: String, body: Body) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try decoder.decode(Response.self, from: data)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw APIError.server(statusCode: http.statusCode) }
    }
}
