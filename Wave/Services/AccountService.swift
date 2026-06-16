import Foundation

struct SupabaseConfig {
    let url: URL
    let anonKey: String

    static var current: SupabaseConfig? {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "LOQUI_SUPABASE_URL") as? String,
              let anonKey = Bundle.main.object(forInfoDictionaryKey: "LOQUI_SUPABASE_ANON_KEY") as? String,
              !urlString.isEmpty,
              !anonKey.isEmpty,
              !urlString.contains("YOUR_SUPABASE"),
              !anonKey.contains("YOUR_SUPABASE"),
              let url = URL(string: urlString)
        else { return nil }
        return SupabaseConfig(url: url, anonKey: anonKey)
    }
}

struct AuthUser: Codable, Equatable {
    let id: String
    let email: String?
}

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let user: AuthUser

    var isExpired: Bool {
        expiresAt <= Date().addingTimeInterval(60)
    }
}

struct SubscriptionStatus: Codable, Equatable {
    var isActive: Bool
    var planName: String?
    var renewsAt: Date?
    var status: String?

    static let inactive = SubscriptionStatus(isActive: false, planName: nil, renewsAt: nil, status: nil)
}

enum AccountServiceError: LocalizedError {
    case missingConfiguration
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Supabase is not configured yet."
        case .invalidResponse:
            return "The server returned an unexpected response."
        case .server(let message):
            return message
        }
    }
}

final class AccountService {
    private let sessionKey = "supabase-session"

    var isConfigured: Bool { SupabaseConfig.current != nil }

    func loadSession() -> AuthSession? {
        guard let data = KeychainService.load(sessionKey) else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    func saveSession(_ session: AuthSession) {
        if let data = try? JSONEncoder().encode(session) {
            KeychainService.save(data, for: sessionKey)
        }
    }

    func clearSession() {
        KeychainService.delete(sessionKey)
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        try await authRequest(path: "auth/v1/token", query: "grant_type=password", body: [
            "email": email,
            "password": password,
        ])
    }

    func signUp(email: String, password: String) async throws -> AuthSession {
        try await authRequest(path: "auth/v1/signup", body: [
            "email": email,
            "password": password,
        ])
    }

    func refresh(_ session: AuthSession) async throws -> AuthSession {
        try await authRequest(path: "auth/v1/token", query: "grant_type=refresh_token", body: [
            "refresh_token": session.refreshToken,
        ])
    }

    func signOut(_ session: AuthSession) async throws {
        let config = try config()
        var request = URLRequest(url: config.url.appending(path: "auth/v1/logout"))
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        _ = try await URLSession.shared.data(for: request)
    }

    func fetchSubscription(session: AuthSession) async throws -> SubscriptionStatus {
        let response: SubscriptionResponse = try await edgeFunction("subscription-status", session: session)
        return SubscriptionStatus(
            isActive: response.isActive,
            planName: response.planName,
            renewsAt: response.renewsAt,
            status: response.status
        )
    }

    func createCheckoutURL(session: AuthSession) async throws -> URL {
        let response: URLResponseBody = try await edgeFunction("create-checkout-session", session: session)
        guard let url = URL(string: response.url) else { throw AccountServiceError.invalidResponse }
        return url
    }

    func createPortalURL(session: AuthSession) async throws -> URL {
        let response: URLResponseBody = try await edgeFunction("create-billing-portal-session", session: session)
        guard let url = URL(string: response.url) else { throw AccountServiceError.invalidResponse }
        return url
    }

    private func authRequest(path: String, query: String? = nil, body: [String: String]) async throws -> AuthSession {
        let config = try config()
        var components = URLComponents(url: config.url.appending(path: path), resolvingAgainstBaseURL: false)
        components?.query = query
        guard let url = components?.url else { throw AccountServiceError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let data = try await responseData(for: request)
        let response = try JSONDecoder().decode(AuthResponse.self, from: data)
        return AuthSession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)),
            user: response.user
        )
    }

    private func edgeFunction<T: Decodable>(_ name: String, session: AuthSession) async throws -> T {
        let config = try config()
        var request = URLRequest(url: config.url.appending(path: "functions/v1/\(name)"))
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        let data = try await responseData(for: request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    private func responseData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AccountServiceError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            if let error = try? JSONDecoder().decode(SupabaseErrorResponse.self, from: data) {
                throw AccountServiceError.server(error.message ?? error.errorDescription ?? error.error ?? "Request failed")
            }
            throw AccountServiceError.server("Request failed with status \(http.statusCode).")
        }
        return data
    }

    private func config() throws -> SupabaseConfig {
        guard let config = SupabaseConfig.current else { throw AccountServiceError.missingConfiguration }
        return config
    }
}

private struct AuthResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

private struct SupabaseErrorResponse: Decodable {
    let error: String?
    let message: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case message
        case errorDescription = "error_description"
    }
}

private struct SubscriptionResponse: Decodable {
    let isActive: Bool
    let planName: String?
    let renewsAt: Date?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case isActive = "is_active"
        case planName = "plan_name"
        case renewsAt = "renews_at"
        case status
    }
}

private struct URLResponseBody: Decodable {
    let url: String
}
