import Foundation
import os

// MARK: - API Error Types

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case decodingFailed(underlying: Error)
    case encodingFailed(underlying: Error)
    case unauthorized
    case networkUnavailable
    case serverError(String)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The request URL is invalid."
        case .invalidResponse:
            return "The server returned an invalid response."
        case .httpError(let code, let message):
            return "HTTP \(code): \(message ?? "Unknown error")"
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .encodingFailed(let error):
            return "Failed to encode request body: \(error.localizedDescription)"
        case .unauthorized:
            return "Authentication required. Please log in again."
        case .networkUnavailable:
            return "Network is unavailable. Please check your connection."
        case .serverError(let message):
            return "Server error: \(message)"
        case .unknown(let error):
            return "An unexpected error occurred: \(error.localizedDescription)"
        }
    }
}

// MARK: - API Response Types

struct AuthResponse: Codable, Sendable {
    let token: String
    let userID: String
    let username: String

    enum CodingKeys: String, CodingKey {
        case token
        case userID = "userId"
        case username
    }
}

struct SyncPayload: Codable, Sendable {
    let dailyStats: [DailyStatPayload]
    let currentStreak: Int
    let longestStreak: Int
    let totalLifetimeUnlocks: Int
    let totalLifetimeAdSeconds: Double
    let lastSyncDate: Date

    struct DailyStatPayload: Codable, Sendable {
        let date: Date
        let totalScreenTimeBlocked: Double
        let unlockCount: Int
        let totalAdTimeWatched: Double
        let appsBlocked: Int
    }
}

struct LeaderboardEntry: Codable, Sendable, Identifiable {
    let id: String
    let username: String
    let currentStreak: Int
    let totalScreenTimeBlocked: Double
    let rank: Int

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case currentStreak
        case totalScreenTimeBlocked
        case rank
    }
}

private struct QuoteResponse: Codable, Sendable {
    let quote: String
}

private struct APIErrorBody: Codable, Sendable {
    let error: String?
    let message: String?
}

private enum HTTPMethod: String {
    case get    = "GET"
    case post   = "POST"
    case put    = "PUT"
    case patch  = "PATCH"
    case delete = "DELETE"
}

// MARK: - APIClient

actor APIClient {

    static let shared = APIClient()

    private let baseURL: String
    private var authToken: String?
    private let session: URLSession

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ScreenBreak",
                                category: "APIClient")

    private init() {
        if let plistURL = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           !plistURL.isEmpty {
            self.baseURL = plistURL
        } else {
            self.baseURL = "http://localhost:3000/api"
        }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Token Management

    func setAuthToken(_ token: String?) {
        authToken = token
    }

    func getAuthToken() -> String? {
        return authToken
    }

    // MARK: - Authentication Endpoints

    func register(username: String, password: String) async throws -> AuthResponse {
        let body: [String: String] = [
            "username": username,
            "password": password
        ]
        let response: AuthResponse = try await makeRequest(
            endpoint: "/auth/register",
            method: .post,
            body: body
        )
        authToken = response.token
        return response
    }

    func login(username: String, password: String) async throws -> AuthResponse {
        let body: [String: String] = [
            "username": username,
            "password": password
        ]
        let response: AuthResponse = try await makeRequest(
            endpoint: "/auth/login",
            method: .post,
            body: body
        )
        authToken = response.token
        return response
    }

    // MARK: - Stats Sync

    func syncStats(stats: SyncPayload) async throws {
        let _: EmptyResponse = try await makeRequest(
            endpoint: "/stats/sync",
            method: .post,
            body: stats
        )
    }

    // MARK: - Leaderboard

    func getLeaderboard() async throws -> [LeaderboardEntry] {
        let entries: [LeaderboardEntry] = try await makeRequest(
            endpoint: "/leaderboard",
            method: .get
        )
        return entries
    }

    // MARK: - Motivational Quotes

    func getMotivationalQuote() async throws -> String {
        let response: QuoteResponse = try await makeRequest(
            endpoint: "/quotes/random",
            method: .get
        )
        return response.quote
    }

    // MARK: - Unlock Logging

    func logUnlock(appName: String, adDuration: Int) async throws {
        let body: [String: Any] = [
            "appName": appName,
            "adDuration": adDuration,
            "timestamp": ISO8601DateFormatter().string(from: .now)
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        let _: EmptyResponse = try await makeRequestWithRawBody(
            endpoint: "/unlocks/log",
            method: .post,
            bodyData: jsonData
        )
    }

    // MARK: - Generic Request Builder

    private func makeRequest<T: Decodable>(
        endpoint: String,
        method: HTTPMethod,
        body: (any Encodable)? = nil
    ) async throws -> T {
        let bodyData: Data?
        if let body {
            do {
                bodyData = try encoder.encode(AnyEncodable(body))
            } catch {
                throw APIError.encodingFailed(underlying: error)
            }
        } else {
            bodyData = nil
        }

        return try await makeRequestWithRawBody(endpoint: endpoint, method: method, bodyData: bodyData)
    }

    private func makeRequestWithRawBody<T: Decodable>(
        endpoint: String,
        method: HTTPMethod,
        bodyData: Data?
    ) async throws -> T {
        guard let url = URL(string: baseURL + endpoint) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = bodyData

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw APIError.networkUnavailable
            case .timedOut:
                throw APIError.networkUnavailable
            default:
                throw APIError.unknown(urlError)
            }
        } catch {
            throw APIError.unknown(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            if T.self == EmptyResponse.self, data.isEmpty || (data.count < 5) {
                // swiftlint:disable:next force_cast
                return EmptyResponse() as! T
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                logger.error("Decoding failed for \(endpoint, privacy: .public)")
                throw APIError.decodingFailed(underlying: error)
            }

        case 401:
            authToken = nil
            throw APIError.unauthorized

        case 400...499:
            let errorBody = try? decoder.decode(APIErrorBody.self, from: data)
            let message = errorBody?.message ?? errorBody?.error ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)

        case 500...599:
            let errorBody = try? decoder.decode(APIErrorBody.self, from: data)
            let message = errorBody?.message ?? "Internal server error"
            throw APIError.serverError(message)

        default:
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: nil)
        }
    }
}

// MARK: - Helper Types

private struct EmptyResponse: Decodable {}

private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ wrapped: any Encodable) {
        _encode = { encoder in
            try wrapped.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
