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
    private let riffDir: URL

    /// Whether the Supabase credentials are real (not placeholder defaults)
    var hasValidCredentials: Bool {
        return !supabaseUrl.contains("your-project") && !supabaseAnonKey.contains("your-anon-key")
    }

    init() {
        // Read Supabase config from settings
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let riffDir = appSupport.appendingPathComponent("Riff")
        let configPath = riffDir.appendingPathComponent("config.json")
        self.riffDir = riffDir

        // Load config to get Supabase credentials
        var url = "https://yrsviodciuepunofxoja.supabase.co"
        var key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inlyc3Zpb2RjaXVlcHVub2Z4b2phIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Mzk1OTY1ODksImV4cCI6MjA1NTE3MjU4OX0.7f_q_xbFZNOB3Gqk-PL78gQ2jEZ_CivfCk1n_JJsMbE"

        AuthLogger.log("Loading config from: \(configPath.path)")

        if let configData = try? Data(contentsOf: configPath),
           let config = try? JSONDecoder().decode([String: AnyCodable].self, from: configData),
           let auth = config["auth"]?.value as? [String: Any] {
            url = auth["supabase_url"] as? String ?? url
            key = auth["supabase_anon_key"] as? String ?? key
            AuthLogger.log("Config loaded successfully. Supabase URL: \(url)")
        } else {
            AuthLogger.log("WARNING: Could not load config.json — using default placeholder credentials")
        }

        self.supabaseUrl = url
        self.supabaseAnonKey = key
        self.authStatePath = riffDir.appendingPathComponent("auth_state.json")

        // Validate credentials
        if supabaseUrl.contains("your-project") || supabaseAnonKey.contains("your-anon-key") {
            AuthLogger.log("ERROR: Supabase credentials are still placeholder defaults! Login will not work.")
            AuthLogger.log("  supabase_url: \(supabaseUrl)")
            AuthLogger.log("  supabase_anon_key: \(String(supabaseAnonKey.prefix(10)))...")
        } else {
            AuthLogger.log("Supabase credentials loaded. URL: \(supabaseUrl)")
        }

        // Load cached auth state
        loadCachedState()

        // Start polling auth_state.json for changes from Python
        startAuthStateMonitor()

        AuthLogger.log("SwiftAuthManager initialized. isAuthenticated=\(isAuthenticated), email=\(userEmail)")

        // Fire a background connectivity check on startup — results go to debug_auth.log only
        runStartupConnectivityCheck()
    }

    /// Quick background check on startup to verify Supabase is reachable.
    /// Results are written only to debug_auth.log — never shown in the UI.
    private func runStartupConnectivityCheck() {
        let targetUrl = supabaseUrl
        let anonKey = supabaseAnonKey
        DispatchQueue.global(qos: .utility).async {
            AuthLogger.log("=== Startup Connectivity Check ===")
            AuthLogger.log("Target: \(targetUrl)")

            // 1. DNS check — can we resolve the host?
            let host = URL(string: targetUrl)?.host ?? "unknown"
            AuthLogger.log("Resolving DNS for: \(host)")
            let hostRef = CFHostCreateWithName(nil, host as CFString).takeRetainedValue()
            var resolved = DarwinBoolean(false)
            CFHostStartInfoResolution(hostRef, .addresses, nil)
            let addresses = CFHostGetAddressing(hostRef, &resolved)?.takeUnretainedValue() as? [Data]
            if resolved.boolValue, let addrs = addresses, !addrs.isEmpty {
                AuthLogger.log("DNS OK: \(host) resolved to \(addrs.count) address(es)")
            } else {
                AuthLogger.log("DNS FAILED: Could not resolve \(host)")
                AuthLogger.log("=== Connectivity Check Done (DNS failure) ===")
                return
            }

            // 2. HTTP check — can we reach the Supabase health endpoint?
            guard let healthUrl = URL(string: "\(targetUrl)/auth/v1/health") else {
                AuthLogger.log("ERROR: Invalid health URL")
                AuthLogger.log("=== Connectivity Check Done ===")
                return
            }

            var req = URLRequest(url: healthUrl)
            req.httpMethod = "GET"
            req.setValue(anonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 10

            let semaphore = DispatchSemaphore(value: 0)
            var result = ""

            let task = URLSession.shared.dataTask(with: req) { data, response, error in
                if let error = error {
                    let nsErr = error as NSError
                    result = "FAILED: code=\(nsErr.code), domain=\(nsErr.domain), \(error.localizedDescription)"
                } else if let http = response as? HTTPURLResponse {
                    let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    result = "HTTP \(http.statusCode): \(body.prefix(200))"
                } else {
                    result = "UNEXPECTED: non-HTTP response"
                }
                semaphore.signal()
            }
            task.resume()
            _ = semaphore.wait(timeout: .now() + 12)

            if result.isEmpty {
                result = "TIMEOUT: No response in 12s"
            }

            AuthLogger.log("Health check result: \(result)")
            AuthLogger.log("=== Connectivity Check Done ===")
        }
    }

    // MARK: - Authentication Methods

    func signInWithEmail(email: String, password: String) async throws {
        AuthLogger.log("signInWithEmail called for: \(email)")

        guard hasValidCredentials else {
            AuthLogger.log("ERROR: Cannot sign in — Supabase credentials are placeholder defaults")
            AuthLogger.log("  supabase_url=\(supabaseUrl)")
            await MainActor.run {
                self.errorMessage = "Login unavailable. Please reinstall or contact support."
                self.isLoading = false
            }
            throw AuthError.loginFailed("Supabase credentials not configured")
        }

        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }

        let endpoint = "\(supabaseUrl)/auth/v1/token?grant_type=password"
        AuthLogger.log("POST \(endpoint)")

        guard let url = URL(string: endpoint) else {
            AuthLogger.log("ERROR: Invalid URL: \(endpoint)")
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = "Something went wrong. Check debug_auth.log."
            }
            throw AuthError.loginFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = ["email": email, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        AuthLogger.log("Request headers: apikey=\(supabaseAnonKey.prefix(20))..., Authorization=Bearer ..., Content-Type=application/json")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                AuthLogger.log("ERROR: Response is not HTTPURLResponse")
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = "Login failed. Please try again."
                }
                throw AuthError.invalidResponse
            }

            AuthLogger.log("Response status: \(httpResponse.statusCode)")
            AuthLogger.log("Response headers: \(httpResponse.allHeaderFields)")

            if httpResponse.statusCode == 200 {
                let result = try JSONDecoder().decode(AuthResponse.self, from: data)
                AuthLogger.log("Login successful for user: \(result.user.id)")

                await MainActor.run {
                    self.isAuthenticated = true
                    self.userEmail = result.user.email
                    self.userId = result.user.id
                    self.isLoading = false
                }

                writeAuthState(authenticated: true, email: result.user.email, userId: result.user.id)
                storeTokens(accessToken: result.accessToken, refreshToken: result.refreshToken)
            } else {
                let responseBody = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                AuthLogger.log("Login failed HTTP \(httpResponse.statusCode): \(responseBody)")

                let decoded = try? JSONDecoder().decode(ErrorResponse.self, from: data)
                let userMessage = decoded?.errorDescription ?? decoded?.msg ?? "Login failed. Please try again."
                AuthLogger.log("User-facing error: \(userMessage)")
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = userMessage
                }
                throw AuthError.loginFailed(userMessage)
            }
        } catch let error as AuthError {
            throw error
        } catch {
            let nsError = error as NSError
            AuthLogger.log("ERROR: Network error during login: code=\(nsError.code), domain=\(nsError.domain), description=\(error.localizedDescription)")
            AuthLogger.log("ERROR: Full error userInfo: \(nsError.userInfo)")

            Self.logNetworkDiagnostic(url: supabaseUrl)

            let userMessage: String
            if nsError.code == NSURLErrorNotConnectedToInternet {
                userMessage = "No internet connection."
            } else if nsError.code == NSURLErrorTimedOut {
                AuthLogger.log("DIAGNOSTIC: Request timed out after 30s to \(supabaseUrl)")
                userMessage = "Connection timed out. Please try again."
            } else if nsError.code == NSURLErrorCannotFindHost {
                AuthLogger.log("DIAGNOSTIC: DNS resolution failed for \(supabaseUrl)")
                userMessage = "Cannot reach server. Please try again."
            } else {
                userMessage = "Connection error. Please try again."
            }
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = userMessage
            }
            throw AuthError.loginFailed(userMessage)
        }
    }

    func signUpWithEmail(email: String, password: String) async throws {
        AuthLogger.log("signUpWithEmail called for: \(email)")

        guard hasValidCredentials else {
            AuthLogger.log("ERROR: Cannot sign up — Supabase credentials are placeholder defaults")
            AuthLogger.log("  supabase_url=\(supabaseUrl)")
            await MainActor.run {
                self.errorMessage = "Signup unavailable. Please reinstall or contact support."
                self.isLoading = false
            }
            throw AuthError.signupFailed("Supabase credentials not configured")
        }

        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }

        let endpoint = "\(supabaseUrl)/auth/v1/signup"
        AuthLogger.log("POST \(endpoint)")

        guard let url = URL(string: endpoint) else {
            AuthLogger.log("ERROR: Invalid URL: \(endpoint)")
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = "Something went wrong. Please try again."
            }
            throw AuthError.signupFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = ["email": email, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        AuthLogger.log("Request headers: apikey=\(supabaseAnonKey.prefix(20))..., Authorization=Bearer ..., Content-Type=application/json")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                AuthLogger.log("ERROR: Response is not HTTPURLResponse")
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = "Signup failed. Please try again."
                }
                throw AuthError.invalidResponse
            }

            AuthLogger.log("Response status: \(httpResponse.statusCode)")
            AuthLogger.log("Response headers: \(httpResponse.allHeaderFields)")

            if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                if let result = try? JSONDecoder().decode(AuthResponse.self, from: data),
                   !result.accessToken.isEmpty {
                    AuthLogger.log("Signup successful with immediate auth for user: \(result.user.id)")

                    await MainActor.run {
                        self.isAuthenticated = true
                        self.userEmail = result.user.email
                        self.userId = result.user.id
                        self.isLoading = false
                    }

                    writeAuthState(authenticated: true, email: result.user.email, userId: result.user.id)
                    storeTokens(accessToken: result.accessToken, refreshToken: result.refreshToken)
                } else {
                    let responseBody = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                    AuthLogger.log("Signup OK but email confirmation required. Response: \(responseBody)")

                    await MainActor.run {
                        self.isLoading = false
                        self.errorMessage = "Check your email! We sent a confirmation link to \(email)."
                    }
                }
            } else {
                let responseBody = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                AuthLogger.log("Signup failed HTTP \(httpResponse.statusCode): \(responseBody)")

                let decoded = try? JSONDecoder().decode(ErrorResponse.self, from: data)
                let userMessage = decoded?.errorDescription ?? decoded?.msg ?? "Signup failed. Please try again."
                AuthLogger.log("User-facing error: \(userMessage)")
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = userMessage
                }
                throw AuthError.signupFailed(userMessage)
            }
        } catch let error as AuthError {
            throw error
        } catch {
            let nsError = error as NSError
            AuthLogger.log("ERROR: Network error during signup: code=\(nsError.code), domain=\(nsError.domain), description=\(error.localizedDescription)")
            AuthLogger.log("ERROR: Full error userInfo: \(nsError.userInfo)")

            Self.logNetworkDiagnostic(url: supabaseUrl)

            let userMessage: String
            if nsError.code == NSURLErrorNotConnectedToInternet {
                userMessage = "No internet connection."
            } else if nsError.code == NSURLErrorTimedOut {
                AuthLogger.log("DIAGNOSTIC: Request timed out after 30s to \(supabaseUrl)")
                userMessage = "Connection timed out. Please try again."
            } else if nsError.code == NSURLErrorCannotFindHost {
                AuthLogger.log("DIAGNOSTIC: DNS resolution failed for \(supabaseUrl)")
                userMessage = "Cannot reach server. Please try again."
            } else {
                userMessage = "Connection error. Please try again."
            }
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = userMessage
            }
            throw AuthError.signupFailed(userMessage)
        }
    }

    /// Fire-and-forget connectivity diagnostic written only to debug_auth.log
    static func logNetworkDiagnostic(url: String) {
        DispatchQueue.global(qos: .utility).async {
            AuthLogger.log("--- Network Diagnostic Start ---")
            AuthLogger.log("DIAGNOSTIC: Target URL: \(url)")

            // Quick HEAD request to check basic reachability
            guard let testUrl = URL(string: url) else {
                AuthLogger.log("DIAGNOSTIC: Invalid URL — cannot run diagnostic")
                AuthLogger.log("--- Network Diagnostic End ---")
                return
            }

            var req = URLRequest(url: testUrl)
            req.httpMethod = "HEAD"
            req.timeoutInterval = 10

            let semaphore = DispatchSemaphore(value: 0)
            var diagResult = ""

            let task = URLSession.shared.dataTask(with: req) { _, response, error in
                if let error = error {
                    let nsErr = error as NSError
                    diagResult = "FAILED: code=\(nsErr.code), domain=\(nsErr.domain), desc=\(error.localizedDescription)"
                } else if let http = response as? HTTPURLResponse {
                    diagResult = "OK: HTTP \(http.statusCode)"
                } else {
                    diagResult = "UNEXPECTED: non-HTTP response"
                }
                semaphore.signal()
            }
            task.resume()
            _ = semaphore.wait(timeout: .now() + 12)

            if diagResult.isEmpty {
                diagResult = "TIMEOUT: HEAD request did not complete in 12s"
            }

            AuthLogger.log("DIAGNOSTIC: HEAD \(url) → \(diagResult)")
            AuthLogger.log("--- Network Diagnostic End ---")
        }
    }

    func signInWithOAuth(provider: String) {
        AuthLogger.log("signInWithOAuth called for provider: \(provider)")

        guard hasValidCredentials else {
            AuthLogger.log("ERROR: Cannot use OAuth — Supabase credentials are placeholder defaults")
            DispatchQueue.main.async {
                self.errorMessage = "Login unavailable. Please reinstall or contact support."
            }
            return
        }

        let authUrl = "\(supabaseUrl)/auth/v1/authorize?provider=\(provider)&redirect_to=riff://oauth/callback"
        AuthLogger.log("Opening OAuth URL: \(authUrl)")

        if let url = URL(string: authUrl) {
            NSWorkspace.shared.open(url)
        } else {
            AuthLogger.log("ERROR: Invalid OAuth URL: \(authUrl)")
        }
    }

    func handleOAuthCallback(url: URL) {
        AuthLogger.log("handleOAuthCallback called with URL: \(url.absoluteString)")

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let fragment = components.fragment else {
            AuthLogger.log("ERROR: OAuth callback URL has no fragment")
            return
        }

        let params = fragment.components(separatedBy: "&")
            .reduce(into: [String: String]()) { result, param in
                let parts = param.components(separatedBy: "=")
                if parts.count == 2 {
                    result[parts[0]] = parts[1]
                }
            }

        AuthLogger.log("OAuth callback params: \(params.keys.joined(separator: ", "))")

        if let accessToken = params["access_token"],
           let refreshToken = params["refresh_token"] {

            AuthLogger.log("OAuth tokens received, storing...")
            storeTokens(accessToken: accessToken, refreshToken: refreshToken)

            if let userInfo = decodeJWT(token: accessToken) {
                let email = userInfo["email"] as? String ?? ""
                let userId = userInfo["sub"] as? String ?? ""
                AuthLogger.log("OAuth JWT decoded: email=\(email), userId=\(userId)")

                DispatchQueue.main.async {
                    self.isAuthenticated = true
                    self.userEmail = email
                    self.userId = userId
                }

                writeAuthState(authenticated: true, email: email, userId: userId)
            } else {
                AuthLogger.log("ERROR: Failed to decode OAuth JWT")
            }
        } else {
            AuthLogger.log("ERROR: OAuth callback missing access_token or refresh_token")
            if let errorDesc = params["error_description"] {
                AuthLogger.log("OAuth error: \(errorDesc)")
                DispatchQueue.main.async {
                    self.errorMessage = errorDesc
                }
            }
        }
    }

    func signOut() {
        AuthLogger.log("signOut called")

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
        AuthLogger.log("Sign out complete — tokens cleared, auth state written")
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
        AuthLogger.log("validateSubscription called")

        // Try UserDefaults first, then Keychain
        var accessToken = UserDefaults.standard.string(forKey: "supabase_access_token")
        if accessToken == nil {
            AuthLogger.log("No token in UserDefaults, checking Keychain...")
            accessToken = getFromKeychain(service: "riff", account: "supabase_access_token")
        }

        guard let token = accessToken else {
            AuthLogger.log("ERROR: No access token available for subscription validation")
            throw AuthError.notAuthenticated
        }

        AuthLogger.log("Token found, calling validate-subscription endpoint")

        let url = URL(string: "\(supabaseUrl)/functions/v1/validate-subscription")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                AuthLogger.log("Subscription validation response status: \(httpResponse.statusCode)")
            }

            let result = try JSONDecoder().decode(SubscriptionResponse.self, from: data)
            AuthLogger.log("Subscription validated: tier=\(result.tier), status=\(result.status)")

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
        } catch {
            AuthLogger.log("ERROR: Subscription validation failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - IPC with Python

    private func loadCachedState() {
        AuthLogger.log("Loading cached auth state from: \(authStatePath.path)")

        guard FileManager.default.fileExists(atPath: authStatePath.path) else {
            AuthLogger.log("No auth_state.json found — starting unauthenticated")
            return
        }

        do {
            let data = try Data(contentsOf: authStatePath)
            let state = try JSONDecoder().decode(AuthState.self, from: data)

            AuthLogger.log("Cached auth state: authenticated=\(state.authenticated), email=\(state.email), timestamp=\(state.timestamp)")

            DispatchQueue.main.async {
                self.isAuthenticated = state.authenticated
                self.userEmail = state.email
                self.userId = state.userId
            }
        } catch {
            AuthLogger.log("ERROR: Failed to load auth_state.json: \(error.localizedDescription)")
        }
    }

    private func writeAuthState(authenticated: Bool, email: String, userId: String) {
        let state = AuthState(
            authenticated: authenticated,
            email: email,
            userId: userId,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: riffDir, withIntermediateDirectories: true)

        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: authStatePath)
            AuthLogger.log("Auth state written: authenticated=\(authenticated), email=\(email)")
        } catch {
            AuthLogger.log("ERROR: Failed to write auth_state.json: \(error.localizedDescription)")
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
        AuthLogger.log("Storing tokens (access: \(accessToken.prefix(10))..., refresh: \(refreshToken.prefix(10))...)")

        // Store in Keychain for Python backend compatibility
        storeInKeychain(service: "riff", account: "supabase_access_token", value: accessToken)
        storeInKeychain(service: "riff", account: "supabase_refresh_token", value: refreshToken)

        // Also store in UserDefaults for Swift UI
        UserDefaults.standard.set(accessToken, forKey: "supabase_access_token")
        UserDefaults.standard.set(refreshToken, forKey: "supabase_refresh_token")

        AuthLogger.log("Tokens stored in Keychain + UserDefaults")
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
            AuthLogger.log("ERROR: Keychain store failed for \(account): OSStatus \(status)")
        } else {
            AuthLogger.log("Keychain store success for \(account)")
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
    let errorDescription: String?
    let msg: String?

    enum CodingKeys: String, CodingKey {
        case errorDescription = "error_description"
        case msg
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

// MARK: - Auth Debug Logger
/// Centralized logger for auth operations — writes to ~/Documents/Riff/debug_auth.log
/// (same directory as Python's debug.log and activity.log)
struct AuthLogger {
    static let logDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Documents/Riff")
    }()

    static let logFile: URL = {
        return logDir.appendingPathComponent("debug_auth.log")
    }()

    static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [Auth] \(message)"
        print(line)

        // Also append to file for persistent debugging
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
            if let data = (line + "\n").data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logFile.path) {
                    if let handle = try? FileHandle(forWritingTo: logFile) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    try? data.write(to: logFile)
                }
            }
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
