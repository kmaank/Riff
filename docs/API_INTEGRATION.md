# Riff API Integration Guide

Complete API reference for integrating Riff with Mac and Android apps.

## 🔑 Base Configuration

```kotlin
// Android (Kotlin)
object RiffAPI {
    const val SUPABASE_URL = "https://yrsviodciuepunofxoja.supabase.co"
    const val SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inlyc3Zpb2RjaXVlcHVub2Z4b2phIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Mzk1OTY1ODksImV4cCI6MjA1NTE3MjU4OX0.7f_q_xbFZNOB3Gqk-PL78gQ2jEZ_CivfCk1n_JJsMbE"
}
```

```swift
// Mac (Swift)
struct RiffAPI {
    static let supabaseURL = "https://yrsviodciuepunofxoja.supabase.co"
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inlyc3Zpb2RjaXVlcHVub2Z4b2phIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Mzk1OTY1ODksImV4cCI6MjA1NTE3MjU4OX0.7f_q_xbFZNOB3Gqk-PL78gQ2jEZ_CivfCk1n_JJsMbE"
}
```

---

## 📱 1. Authentication

### Sign Up

```http
POST /auth/v1/signup
Host: yrsviodciuepunofxoja.supabase.co
apikey: {SUPABASE_ANON_KEY}
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "securepassword"
}
```

**Response:**
```json
{
  "access_token": "eyJhbGc...",
  "refresh_token": "...",
  "user": {
    "id": "uuid",
    "email": "user@example.com"
  }
}
```

### Sign In

```http
POST /auth/v1/token?grant_type=password
Host: yrsviodciuepunofxoja.supabase.co
apikey: {SUPABASE_ANON_KEY}
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "securepassword"
}
```

**Android Example:**
```kotlin
suspend fun signIn(email: String, password: String): AuthResponse {
    val client = SupabaseClient.createClient(
        supabaseUrl = RiffAPI.SUPABASE_URL,
        supabaseKey = RiffAPI.SUPABASE_ANON_KEY
    )

    return client.auth.signInWith(Email) {
        this.email = email
        this.password = password
    }
}
```

**Mac Example:**
```swift
func signIn(email: String, password: String) async throws -> Session {
    let client = SupabaseClient(
        supabaseURL: URL(string: RiffAPI.supabaseURL)!,
        supabaseKey: RiffAPI.supabaseAnonKey
    )

    let session = try await client.auth.signIn(
        email: email,
        password: password
    )
    return session
}
```

---

## ✅ 2. Validate Subscription

Check user's subscription status and quota.

```http
GET /functions/v1/validate-subscription
Host: yrsviodciuepunofxoja.supabase.co
Authorization: Bearer {ACCESS_TOKEN}
```

**Response:**
```json
{
  "valid": true,
  "tier": "pro",
  "quota_used": 1500,
  "quota_limit": 10000,
  "quota_remaining": 8500,
  "subscription_status": "active"
}
```

**Android Example:**
```kotlin
data class SubscriptionStatus(
    val valid: Boolean,
    val tier: String,
    val quotaUsed: Int,
    val quotaLimit: Int,
    val quotaRemaining: Int,
    val subscriptionStatus: String
)

suspend fun validateSubscription(accessToken: String): SubscriptionStatus {
    val response = httpClient.get("$SUPABASE_URL/functions/v1/validate-subscription") {
        header("Authorization", "Bearer $accessToken")
    }
    return response.body()
}
```

**Mac Example:**
```swift
struct SubscriptionStatus: Codable {
    let valid: Bool
    let tier: String
    let quotaUsed: Int
    let quotaLimit: Int
    let quotaRemaining: Int
    let subscriptionStatus: String
}

func validateSubscription(accessToken: String) async throws -> SubscriptionStatus {
    var request = URLRequest(url: URL(string: "\(RiffAPI.supabaseURL)/functions/v1/validate-subscription")!)
    request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

    let (data, _) = try await URLSession.shared.data(for: request)
    return try JSONDecoder().decode(SubscriptionStatus.self, from: data)
}
```

---

## 📝 3. Log Usage

Track API usage for quota management.

```http
POST /functions/v1/log-usage
Host: yrsviodciuepunofxoja.supabase.co
Authorization: Bearer {ACCESS_TOKEN}
Content-Type: application/json

{
  "endpoint": "transcribe",
  "duration_seconds": 10,
  "metadata": {
    "audio_format": "wav",
    "sample_rate": 44100
  }
}
```

**Response:**
```json
{
  "success": true,
  "quota_used": 1510,
  "quota_remaining": 8490
}
```

**Android Example:**
```kotlin
suspend fun logUsage(
    accessToken: String,
    endpoint: String,
    durationSeconds: Int,
    metadata: Map<String, Any> = emptyMap()
) {
    httpClient.post("$SUPABASE_URL/functions/v1/log-usage") {
        header("Authorization", "Bearer $accessToken")
        contentType(ContentType.Application.Json)
        setBody(mapOf(
            "endpoint" to endpoint,
            "duration_seconds" to durationSeconds,
            "metadata" to metadata
        ))
    }
}
```

---

## 📱 4. Register Device

Register a device for the user.

```http
POST /functions/v1/register-device
Host: yrsviodciuepunofxoja.supabase.co
Authorization: Bearer {ACCESS_TOKEN}
Content-Type: application/json

{
  "device_id": "unique-device-id",
  "platform": "android",
  "app_version": "1.0.0"
}
```

**Response:**
```json
{
  "success": true,
  "device_id": "unique-device-id"
}
```

**Android Example:**
```kotlin
suspend fun registerDevice(accessToken: String) {
    val deviceId = Settings.Secure.getString(
        context.contentResolver,
        Settings.Secure.ANDROID_ID
    )

    httpClient.post("$SUPABASE_URL/functions/v1/register-device") {
        header("Authorization", "Bearer $accessToken")
        contentType(ContentType.Application.Json)
        setBody(mapOf(
            "device_id" to deviceId,
            "platform" to "android",
            "app_version" to BuildConfig.VERSION_NAME
        ))
    }
}
```

**Mac Example:**
```swift
func registerDevice(accessToken: String) async throws {
    let deviceId = // Get Mac serial number or unique identifier

    var request = URLRequest(url: URL(string: "\(RiffAPI.supabaseURL)/functions/v1/register-device")!)
    request.httpMethod = "POST"
    request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")

    let body = [
        "device_id": deviceId,
        "platform": "macos",
        "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    ]
    request.httpBody = try JSONEncoder().encode(body)

    let (_, _) = try await URLSession.shared.data(for: request)
}
```

---

## 🔄 5. Sync History

Sync transcription history across devices.

```http
POST /functions/v1/sync-history
Host: yrsviodciuepunofxoja.supabase.co
Authorization: Bearer {ACCESS_TOKEN}
Content-Type: application/json

{
  "entries": [
    {
      "device_id": "device-123",
      "transcription": "Original transcription text",
      "refined_text": "Refined and improved text",
      "audio_duration": 10,
      "timestamp": "2026-02-27T10:30:00Z"
    }
  ]
}
```

**Response:**
```json
{
  "success": true,
  "synced_count": 1
}
```

**Android Example:**
```kotlin
data class HistoryEntry(
    val deviceId: String,
    val transcription: String,
    val refinedText: String?,
    val audioDuration: Int,
    val timestamp: String
)

suspend fun syncHistory(accessToken: String, entries: List<HistoryEntry>) {
    httpClient.post("$SUPABASE_URL/functions/v1/sync-history") {
        header("Authorization", "Bearer $accessToken")
        contentType(ContentType.Application.Json)
        setBody(mapOf("entries" to entries))
    }
}
```

---

## 🔑 6. Get API Key

Retrieve user's API key for direct OpenAI calls.

```http
GET /functions/v1/get-api-key
Host: yrsviodciuepunofxoja.supabase.co
Authorization: Bearer {ACCESS_TOKEN}
```

**Response:**
```json
{
  "api_key": "riff_xxxxxxxxxxxxx",
  "created_at": "2026-02-27T10:00:00Z"
}
```

---

## 🎤 7. Proxy Transcribe

Transcribe audio through Riff's proxy (handles quota).

```http
POST /functions/v1/proxy-transcribe
Host: yrsviodciuepunofxoja.supabase.co
Authorization: Bearer {ACCESS_TOKEN}
Content-Type: multipart/form-data

file: [audio file]
model: whisper-1
language: en (optional)
```

**Response:**
```json
{
  "text": "Transcribed text from audio"
}
```

**Android Example:**
```kotlin
suspend fun transcribeAudio(
    accessToken: String,
    audioFile: File,
    language: String? = null
): String {
    val response = httpClient.post("$SUPABASE_URL/functions/v1/proxy-transcribe") {
        header("Authorization", "Bearer $accessToken")
        setBody(MultiPartFormDataContent(
            formData {
                append("file", audioFile.readBytes(), Headers.build {
                    append(HttpHeaders.ContentType, "audio/wav")
                    append(HttpHeaders.ContentDisposition, "filename=\"audio.wav\"")
                })
                append("model", "whisper-1")
                language?.let { append("language", it) }
            }
        ))
    }

    val result: Map<String, String> = response.body()
    return result["text"] ?: ""
}
```

---

## ✨ 8. Proxy Refine

Refine transcribed text through Riff's proxy.

```http
POST /functions/v1/proxy-refine
Host: yrsviodciuepunofxoja.supabase.co
Authorization: Bearer {ACCESS_TOKEN}
Content-Type: application/json

{
  "text": "Raw transcription text to refine"
}
```

**Response:**
```json
{
  "refined_text": "Refined and improved transcription"
}
```

**Android Example:**
```kotlin
suspend fun refineText(accessToken: String, text: String): String {
    val response = httpClient.post("$SUPABASE_URL/functions/v1/proxy-refine") {
        header("Authorization", "Bearer $accessToken")
        contentType(ContentType.Application.Json)
        setBody(mapOf("text" to text))
    }

    val result: Map<String, String> = response.body()
    return result["refined_text"] ?: text
}
```

---

## 💳 9. Create Checkout Session

Create a Stripe checkout session for subscription.

```http
POST /functions/v1/create-checkout
Host: yrsviodciuepunofxoja.supabase.co
Authorization: Bearer {ACCESS_TOKEN}
Content-Type: application/json

{
  "price_id": "price_1ABC123..."
}
```

**Response:**
```json
{
  "url": "https://checkout.stripe.com/c/pay/cs_test_..."
}
```

**Android Example:**
```kotlin
suspend fun createCheckout(accessToken: String, priceId: String): String {
    val response = httpClient.post("$SUPABASE_URL/functions/v1/create-checkout") {
        header("Authorization", "Bearer $accessToken")
        contentType(ContentType.Application.Json)
        setBody(mapOf("price_id" to priceId))
    }

    val result: Map<String, String> = response.body()
    return result["url"] ?: throw Exception("No checkout URL")
}

// Open in browser
fun openCheckout(checkoutUrl: String) {
    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(checkoutUrl))
    context.startActivity(intent)
}
```

---

## 🏪 10. Create Customer Portal

Create Stripe customer portal session.

```http
POST /functions/v1/create-portal
Host: yrsviodciuepunofxoja.supabase.co
Authorization: Bearer {ACCESS_TOKEN}
```

**Response:**
```json
{
  "url": "https://billing.stripe.com/p/session/..."
}
```

---

## 🔒 Security Best Practices

### 1. Store Access Tokens Securely

**Android:**
```kotlin
// Use EncryptedSharedPreferences
val masterKey = MasterKey.Builder(context)
    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
    .build()

val sharedPreferences = EncryptedSharedPreferences.create(
    context,
    "riff_secure_prefs",
    masterKey,
    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
)

sharedPreferences.edit()
    .putString("access_token", accessToken)
    .apply()
```

**Mac:**
```swift
// Use Keychain
func saveAccessToken(_ token: String) {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: "riff_access_token",
        kSecValueData as String: token.data(using: .utf8)!
    ]

    SecItemDelete(query as CFDictionary)
    SecItemAdd(query as CFDictionary, nil)
}
```

### 2. Handle Token Refresh

```kotlin
// Auto-refresh tokens
suspend fun refreshTokenIfNeeded(refreshToken: String): String {
    val response = httpClient.post("$SUPABASE_URL/auth/v1/token?grant_type=refresh_token") {
        header("apikey", RiffAPI.SUPABASE_ANON_KEY)
        contentType(ContentType.Application.Json)
        setBody(mapOf("refresh_token" to refreshToken))
    }

    val result: Map<String, String> = response.body()
    return result["access_token"] ?: throw Exception("Token refresh failed")
}
```

### 3. Handle Quota Exceeded

```kotlin
try {
    val result = transcribeAudio(accessToken, audioFile)
} catch (e: ClientRequestException) {
    when (e.response.status.value) {
        403 -> {
            // Quota exceeded - prompt user to upgrade
            showUpgradeDialog()
        }
        401 -> {
            // Unauthorized - refresh token
            refreshAuthToken()
        }
    }
}
```

---

## 📊 Error Handling

All endpoints return standard HTTP status codes:

| Code | Meaning | Action |
|------|---------|--------|
| 200 | Success | Process response |
| 400 | Bad Request | Check request format |
| 401 | Unauthorized | Refresh or re-authenticate |
| 403 | Forbidden | Quota exceeded or permission denied |
| 429 | Too Many Requests | Implement backoff |
| 500 | Server Error | Retry with exponential backoff |

---

## 🧪 Testing Your Integration

Use the test scripts provided:

```bash
# Run health check
./tests/health-check.sh

# Test full subscription flow
./tests/subscription-flow-test.sh

# Test individual endpoints
./tests/edge-functions-test.sh
```

---

## 🚀 Quick Start Checklist

- [ ] Install Supabase SDK in your app
- [ ] Configure SUPABASE_URL and SUPABASE_ANON_KEY
- [ ] Implement authentication (sign up/sign in)
- [ ] Store access tokens securely
- [ ] Implement subscription validation
- [ ] Add usage logging
- [ ] Implement transcribe/refine proxies
- [ ] Add checkout flow
- [ ] Handle errors and quota limits
- [ ] Test with test scripts

---

**Need help?** Check the test scripts in `/tests/` for working examples! 🎉
