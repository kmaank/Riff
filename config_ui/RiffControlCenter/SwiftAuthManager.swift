//
//  SwiftAuthManager.swift
//  RiffControlCenter
//
//  Swift-side authentication manager
//  Handles Supabase auth and IPC with Python via auth_state.json
//

import SwiftUI
import Foundation

struct QuotaInfo {
    var riffsLimit: Int?
    var riffsUsed: Int
    var secondsLimit: Int?
    var secondsUsed: Double
}

class SwiftAuthManager: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var userEmail: String = ""
    @Published var userId: String = ""
    @Published var subscriptionTier: String = "free"
    @Published var subscriptionStatus: String = "active"
    @Published var quota: QuotaInfo?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    let supabaseUrl: String
    let supabaseAnonKey: String
    private let authStatePath: URL

    init() {
        // Read Supabase config from settings
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let riffDir = appSupport.appendingPathComponent("Riff")
        let configPath = riffDir.appendingPathComponent("config.json")

        // Load config to get Supabase credentials
        var url = "https://your-project.supabase.co"
        var key = "your-anon-key"

        if let configData = try? Data(contentsOf: configPath),
           let config = try? JSONDecoder().decode([String: AnyCodable].self, from: configData),
           let auth = config["auth"]?.value as? [String: Any] {
            url = auth["supabase_url"] as? String ?? url
            key = auth["supabase_anon_key"] as? String ?? key
        }

        self.supabaseUrl = url
        self.supabaseAnonKey = key
        self.authStatePath = riffDir.appendingPathComponent("auth_state.json")

        // Load cached auth state
        loadCachedState()

        // Start polling auth_state.json for changes from Python
        startAuthStateMonitor()
    }

    // MARK: - Authentication Methods

    func signInWithEmail(email: String, password: String) async throws {
        isLoading = true
        errorMessage = nil

        let url = URL(string: "\(supabaseUrl)/auth/v1/token?grant_type=password")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["email": email, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        if httpResponse.statusCode == 200 {
            let result = try JSONDecoder().decode(AuthResponse.self, from: data)

            await MainActor.run {
                self.isAuthenticated = true
                self.userEmail = result.user.email
                self.userId = result.user.id
                self.isLoading = false
            }

            // Write auth state for Python
            writeAuthState(authenticated: true, email: result.user.email, userId: result.user.id)

            // Store tokens securely
            storeTokens(accessToken: result.accessToken, refreshToken: result.refreshToken)
        } else {
            let error = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = error?.errorDescription ?? "Login failed"
            }
            throw AuthError.loginFailed(error?.errorDescription ?? "Unknown error")
        }
    }

    func signUpWithEmail(email: String, password: String) async throws {
        isLoading = true
        errorMessage = nil

        let url = URL(string: "\(supabaseUrl)/auth/v1/signup")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["email": email, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
            let result = try JSONDecoder().decode(AuthResponse.self, from: data)

            await MainActor.run {
                self.isAuthenticated = true
                self.userEmail = result.user.email
                self.userId = result.user.id
                self.isLoading = false
            }

            // Write auth state for Python
            writeAuthState(authenticated: true, email: result.user.email, userId: result.user.id)

            // Store tokens
            storeTokens(accessToken: result.accessToken, refreshToken: result.refreshToken)
        } else {
            let error = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = error?.errorDescription ?? "Signup failed"
            }
            throw AuthError.signupFailed(error?.errorDescription ?? "Unknown error")
        }
    }

    func signInWithOAuth(provider: String) {
        // Open OAuth flow in system browser
        // Provider: "google", "github", "apple"
        let authUrl = "\(supabaseUrl)/auth/v1/authorize?provider=\(provider)&redirect_to=riff://oauth/callback"

        if let url = URL(string: authUrl) {
            NSWorkspace.shared.open(url)
        }
    }

    func handleOAuthCallback(url: URL) {
        // Parse OAuth callback URL
        // Extract access_token and refresh_token from URL fragments
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let fragment = components.fragment else {
            return
        }

        let params = fragment.components(separatedBy: "&")
            .reduce(into: [String: String]()) { result, param in
                let parts = param.components(separatedBy: "=")
                if parts.count == 2 {
                    result[parts[0]] = parts[1]
                }
            }

        if let accessToken = params["access_token"],
           let refreshToken = params["refresh_token"] {

            // Store tokens
            storeTokens(accessToken: accessToken, refreshToken: refreshToken)

            // Decode JWT to get user info (basic decode, no verification)
            if let userInfo = decodeJWT(token: accessToken) {
                DispatchQueue.main.async {
                    self.isAuthenticated = true
                    self.userEmail = userInfo["email"] as? String ?? ""
                    self.userId = userInfo["sub"] as? String ?? ""
                }

                writeAuthState(authenticated: true, email: self.userEmail, userId: self.userId)
            }
        }
    }

    func signOut() {
        isAuthenticated = false
        userEmail = ""
        userId = ""
        subscriptionTier = "free"
        quota = nil

        // Clear stored tokens from Keychain
        deleteFromKeychain(service: "riff", account: "supabase_access_token")
        deleteFromKeychain(service: "riff", account: "supabase_refresh_token")
        deleteFromKeychain(service: "riff", account: "managed_groq_key")

        // Clear from UserDefaults
        UserDefaults.standard.removeObject(forKey: "supabase_access_token")
        UserDefaults.standard.removeObject(forKey: "supabase_refresh_token")

        // Write auth state for Python
        writeAuthState(authenticated: false, email: "", userId: "")
    }

    private func deleteFromKeychain(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Subscription Methods

    func validateSubscription() async throws {
        // Try UserDefaults first, then Keychain
        var accessToken = UserDefaults.standard.string(forKey: "supabase_access_token")
        if accessToken == nil {
            accessToken = getFromKeychain(service: "riff", account: "supabase_access_token")
        }

        guard let token = accessToken else {
            throw AuthError.notAuthenticated
        }

        let url = URL(string: "\(supabaseUrl)/functions/v1/validate-subscription")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        let (data, _) = try await URLSession.shared.data(for: request)
        let result = try JSONDecoder().decode(SubscriptionResponse.self, from: data)

        await MainActor.run {
            self.subscriptionTier = result.tier
            self.subscriptionStatus = result.status
            self.quota = QuotaInfo(
                riffsLimit: result.quota.riffsLimit,
                riffsUsed: result.quota.riffsUsed,
                secondsLimit: result.quota.secondsLimit,
                secondsUsed: result.quota.secondsUsed
            )
        }
    }

    // MARK: - IPC with Python

    private func loadCachedState() {
        guard let data = try? Data(contentsOf: authStatePath),
              let state = try? JSONDecoder().decode(AuthState.self, from: data) else {
            return
        }

        DispatchQueue.main.async {
            self.isAuthenticated = state.authenticated
            self.userEmail = state.email
            self.userId = state.userId
        }
    }

    private func writeAuthState(authenticated: Bool, email: String, userId: String) {
        let state = AuthState(
            authenticated: authenticated,
            email: email,
            userId: userId,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )

        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: authStatePath)
        }
    }

    private func startAuthStateMonitor() {
        // Poll auth_state.json every 2 seconds for changes from Python
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.loadCachedState()
        }
    }

    // MARK: - Token Management

    private func storeTokens(accessToken: String, refreshToken: String) {
        // Store in Keychain for Python backend compatibility
        storeInKeychain(service: "riff", account: "supabase_access_token", value: accessToken)
        storeInKeychain(service: "riff", account: "supabase_refresh_token", value: refreshToken)

        // Also store in UserDefaults for Swift UI
        UserDefaults.standard.set(accessToken, forKey: "supabase_access_token")
        UserDefaults.standard.set(refreshToken, forKey: "supabase_refresh_token")
    }

    private func storeInKeychain(service: String, account: String, value: String) {
        let data = value.data(using: .utf8)!

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            print("Error storing in keychain: \(status)")
        }
    }

    private func getFromKeychain(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    private func decodeJWT(token: String) -> [String: Any]? {
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3,
              let payloadData = base64UrlDecode(parts[1]),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return nil
        }
        return json
    }

    private func base64UrlDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let length = Double(base64.lengthOfBytes(using: .utf8))
        let requiredLength = 4 * ceil(length / 4.0)
        let paddingLength = requiredLength - length
        if paddingLength > 0 {
            base64 += String(repeating: "=", count: Int(paddingLength))
        }

        return Data(base64Encoded: base64)
    }
}

// MARK: - Data Models

struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let user: User

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
    }

    struct User: Codable {
        let id: String
        let email: String
    }
}

struct ErrorResponse: Codable {
    let errorDescription: String

    enum CodingKeys: String, CodingKey {
        case errorDescription = "error_description"
    }
}

struct SubscriptionResponse: Codable {
    let valid: Bool
    let tier: String
    let status: String
    let quota: Quota

    struct Quota: Codable {
        let riffsLimit: Int?
        let riffsUsed: Int
        let secondsLimit: Int?
        let secondsUsed: Double

        enum CodingKeys: String, CodingKey {
            case riffsLimit = "riffs_limit"
            case riffsUsed = "riffs_used"
            case secondsLimit = "seconds_limit"
            case secondsUsed = "seconds_used"
        }
    }
}

struct AuthState: Codable {
    let authenticated: Bool
    let email: String
    let userId: String
    let timestamp: String

    enum CodingKeys: String, CodingKey {
        case authenticated
        case email
        case userId = "user_id"
        case timestamp
    }
}

enum AuthError: LocalizedError {
    case invalidResponse
    case loginFailed(String)
    case signupFailed(String)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .loginFailed(let message):
            return message
        case .signupFailed(let message):
            return message
        case .notAuthenticated:
            return "Not authenticated"
        }
    }
}

// Helper for decoding arbitrary JSON
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        if let bool = value as? Bool {
            try container.encode(bool)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let string = value as? String {
            try container.encode(string)
        } else if let array = value as? [Any] {
            try container.encode(array.map { AnyCodable($0) })
        } else if let dictionary = value as? [String: Any] {
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        } else {
            try container.encodeNil()
        }
    }
}
