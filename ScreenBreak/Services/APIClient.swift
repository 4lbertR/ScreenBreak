import Foundation
import os

// MARK: - API Error Types

/// Errors that can be thrown by `APIClient` methods.
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

/// Response returned by the register and login endpoints.
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

/// Payload sent when syncing local statistics to the backend.
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

/// A single entry on the leaderboard.
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

/// Wrapper for the motivational-quote endpoint response.
private struct QuoteResponse: Codable, Sendable {
    let quote: String
}

/// Generic error body returned by the backend.
private struct APIErrorBody: Codable, Sendable {
    let error: String?
    let message: String?
}

// MARK: - HTTP Method

private enum HTTPMethod: String {
    case get    = "GET"
    case post   = "POST"
    case put    = "PUT"
    case patch  = "PATCH"
    case delete = "DELETE"
}

// MARK: - APIClient

/// An actor-isolated REST client for communication with the ScreenBreak Node.js backend.
///
/// All network calls use modern `async/await` with `URLSession`. The client attaches a
/// bearer token (when available) and handles common error scenarios (401, 5xx, network
/// failures). The app is designed to work **fully offline** — callers should catch errors
/// gracefully and fall back to local data.
///
/// Thread safety is guaranteed by the `actor` isolation.
actor APIClient {

    // MARK: - Singleton

    static let shared = APIClient()

    // MARK: - Configuration

    /// Base URL for the backend API. In production this would come from a remote config
    /// or build-time constant. Defaults to localhost for development.
    private let baseURL: String

    /// Bearer token set after successful login or registration.
    private var authToken: String?

    /// The configured `URLSession` used for all requests.
    private let session: URLSession

    /// JSON decoder configured for ISO-8601 date parsing.
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// JSON encoder configured for ISO-8601 date serialisation.
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ScreenBreak",
                                category: "APIClient")

    // MARK: - Init

    private init() {
        // Read base URL from Info.plist or fall back to localhost.
        if let plistURL = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           !plistURL.isEmpty {
            self.baseURL = plistURL
        } else {
            self.baseURL = "http://localhost:3000/api"
        }

        // Configure a session with reasonable timeouts.
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)

        logger.info("APIClient initialised with base URL: \(self.baseURL)")
    }

    // MARK: - Token Management

    /// Sets the bearer token used for authenticated requests.
    ///
    /// - Parameter token: The JWT or opaque token string received from the backend.
    func setAuthToken(_ token: String?) {
        authToken = token
    }

    /// Returns the currently stored auth token, if any.
    func getAuthToken() -> String? {
        return authToken
    }

    // MARK: - Authentication Endpoints

    /// Registers a new user account on the backend.
    ///
    /// - Parameters:
    ///   - username: The desired username (must be unique on the server).
    ///   - password: The user's password (transmitted over HTTPS, hashed server-side).
    /// - Returns: An `AuthResponse` containing the token and user details.
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
        logger.info("Registration successful for user '\(username)'.")
        return response
    }

    /// Authenticates an existing user and obtains a token.
    ///
    /// - Parameters:
    ///   - username: The user's username.
    ///   - password: The user's password.
    /// - Returns: An `AuthResponse` containing the token and user details.
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
        logger.info("Login successful for user '\(username)'.")
        return response
    }

    // MARK: - Stats Sync

    /// Pushes local aggregated statistics to the backend for leaderboard and backup purposes.
    ///
    /// - Parameter stats: The `SyncPayload` containing the user's recent daily stats
    ///   and lifetime counters.
    func syncStats(stats: SyncPayload) async throws {
        let _: EmptyResponse = try await makeRequest(
            endpoint: "/stats/sync",
            method: .post,
            body: stats
        )
        logger.info("Stats synced successfully.")
    }

    // MARK: - Leaderboard

    /// Fetches the current leaderboard rankings from the backend.
    ///
    /// - Returns: An array of `LeaderboardEntry` sorted by rank.
    func getLeaderboard() async throws -> [LeaderboardEntry] {
        let entries: [LeaderboardEntry] = try await makeRequest(
            endpoint: "/leaderboard",
            method: .get
        )
        logger.info("Leaderboard fetched: \(entries.count) entries.")
        return entries
    }

    // MARK: - Motivational Quotes

    /// Fetches a random motivational quote from the backend.
    ///
    /// - Returns: The quote as a plain `String`.
    func getMotivationalQuote() async throws -> String {
        let response: QuoteResponse = try await makeRequest(
            endpoint: "/quotes/random",
            method: .get
        )
        return response.quote
    }

    // MARK: - Unlock Logging

    /// Reports a single app unlock event to the backend for analytics.
    ///
    /// - Parameters:
    ///   - appName: Human-readable name of the unlocked app.
    ///   - adDuration: How many seconds of ad the user watched.
    func logUnlock(appName: String, adDuration: Int) async throws {
        let body: [String: Any] = [
            "appName": appName,
            "adDuration": adDuration,
            "timestamp": ISO8601DateFormatter().string(from: .now)
        ]
        // Manual serialisation because [String: Any] is not Encodable.
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        let _: EmptyResponse = try await makeRequestWithRawBody(
            endpoint: "/unlocks/log",
            method: .post,
            bodyData: jsonData
        )
        logger.info("Unlock logged: \(appName), \(adDuration)s ad.")
    }

    // MARK: - Generic Request Builder

    /// Builds and executes an HTTP request, decoding the response into the specified type.
    ///
    /// - Parameters:
    ///   - endpoint: The path component appended to `baseURL` (e.g. "/auth/login").
    ///   - method: The HTTP method.
    ///   - body: An optional `Encodable` value to serialise as the JSON request body.
    /// - Returns: The decoded response of type `T`.
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

    /// Builds and executes an HTTP request using pre-serialised body data.
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
            // If the caller expects `EmptyResponse`, allow empty bodies.
            if T.self == EmptyResponse.self, data.isEmpty || (data.count < 5) {
                // swiftlint:disable:next force_cast
                return EmptyResponse() as! T
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                logger.error("Decoding failed for \(endpoint): \(error.localizedDescription)")
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

/// A decodable placeholder for endpoints that return no meaningful body.
private struct EmptyResponse: Decodable {}

/// Type-erasing wrapper that lets `makeRequest` accept any `Encodable` body.
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
