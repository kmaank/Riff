# Riff System Architecture & Reference Guide

**Complete Technical Documentation**
*Authentication, Subscription, Proxy & API Systems*

---

## 📋 Table of Contents

1. [System Overview](#system-overview)
2. [Architecture Diagram](#architecture-diagram)
3. [Phase 1: Supabase Backend](#phase-1-supabase-backend)
4. [Phase 2: Database Schema](#phase-2-database-schema)
5. [Phase 3: Edge Functions](#phase-3-edge-functions)
6. [Phase 4: Authentication Flow](#phase-4-authentication-flow)
7. [Phase 5: Swift UI Integration](#phase-5-swift-ui-integration)
8. [Phase 6: Python Backend Integration](#phase-6-python-backend-integration)
9. [Subscription System](#subscription-system)
10. [Quota Management](#quota-management)
11. [API Proxy System](#api-proxy-system)
12. [Data Flow Examples](#data-flow-examples)
13. [Security Model](#security-model)
14. [Troubleshooting Guide](#troubleshooting-guide)
15. [Common Issues & Solutions](#common-issues--solutions)

---

## System Overview

### What Riff Does

Riff is a voice-to-text transcription app with:
- **User Authentication** (email/password + OAuth)
- **Tiered Subscriptions** (Free, Starter, Pro, Business)
- **Quota Management** (riffs/month, recording hours/month)
- **API Proxying** (Groq API for transcription/refinement)
- **Multi-device Sync** (history across Mac/Android)
- **Stripe Integration** (payments & billing)

### Technology Stack

| Component | Technology |
|-----------|------------|
| **Database** | Supabase (PostgreSQL) |
| **Auth** | Supabase Auth |
| **Backend** | Supabase Edge Functions (Deno) |
| **Mac App** | Python 3.11 + Swift UI |
| **Android App** | Kotlin (planned) |
| **Payments** | Stripe |
| **AI API** | Groq (Whisper + Llama) |

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        USER DEVICES                              │
│  ┌──────────────────┐                    ┌──────────────────┐  │
│  │   Mac App        │                    │  Android App     │  │
│  │                  │                    │                  │  │
│  │  Swift UI        │                    │  Kotlin          │  │
│  │  (Settings)      │                    │  (Full App)      │  │
│  │       +          │                    │                  │  │
│  │  Python Backend  │                    │                  │  │
│  │  (Recording)     │                    │                  │  │
│  └────────┬─────────┘                    └────────┬─────────┘  │
│           │                                       │             │
└───────────┼───────────────────────────────────────┼─────────────┘
            │                                       │
            │           HTTPS/REST API              │
            │                                       │
┌───────────▼───────────────────────────────────────▼─────────────┐
│                     SUPABASE PLATFORM                            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                  Supabase Auth                          │   │
│  │  • Email/Password                                       │   │
│  │  • OAuth (Google, GitHub, Apple)                       │   │
│  │  • JWT Token Management                                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              PostgreSQL Database (RLS)                  │   │
│  │  • profiles (user data + subscription)                  │   │
│  │  • devices (registered devices)                         │   │
│  │  • usage_logs (API usage tracking)                      │   │
│  │  • history (transcription history)                      │   │
│  │  • suspicious_activities (fraud detection)              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Edge Functions (Deno)                      │   │
│  │  1. validate-subscription  → Check tier & quota         │   │
│  │  2. log-usage             → Track API usage             │   │
│  │  3. register-device       → Device management           │   │
│  │  4. sync-history          → Sync transcriptions         │   │
│  │  5. get-api-key           → Fetch managed API key       │   │
│  │  6. create-checkout       → Stripe checkout session     │   │
│  │  7. create-portal         → Stripe customer portal      │   │
│  │  8. stripe-webhook        → Handle Stripe events        │   │
│  │  9. proxy-transcribe      → Proxy to Groq Whisper       │   │
│  │ 10. proxy-refine          → Proxy to Groq Llama         │   │
│  └─────────────────────────────────────────────────────────┘   │
└──────────────────────┬───────────────────────────────────────────┘
                       │
         ┌─────────────┼─────────────┐
         │                           │
         │                           │
┌────────▼────────┐         ┌────────▼────────┐
│  Stripe API     │         │   Groq API      │
│  • Payments     │         │   • Whisper     │
│  • Subscriptions│         │   • Llama 3     │
│  • Webhooks     │         │                 │
└─────────────────┘         └─────────────────┘
```

---

## Phase 1: Supabase Backend

### 1.1 Project Setup

**Supabase Project**: `yrsviodciuepunofxoja`
**URL**: `https://yrsviodciuepunofxoja.supabase.co`
**Region**: US East (Ohio)

**Configuration** (`config.json`):
```json
{
  "auth": {
    "supabase_url": "https://yrsviodciuepunofxoja.supabase.co",
    "supabase_anon_key": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
  }
}
```

### 1.2 Authentication Setup

**Enabled Auth Providers**:
- ✅ Email/Password
- ✅ Google OAuth
- ✅ GitHub OAuth
- ✅ Apple OAuth

**Auth Configuration**:
- Email confirmations: Disabled (for development)
- Auto-confirm users: Enabled
- JWT expiry: 1 hour
- Refresh token rotation: Enabled

### 1.3 Environment Variables

**Supabase Secrets** (set in Dashboard → Edge Functions):

```bash
STRIPE_SECRET_KEY=sk_test_...        # Stripe API key
STRIPE_WEBHOOK_SECRET=whsec_...      # Webhook signature secret
GROQ_API_KEY=gsk_...                 # Managed Groq API key
```

---

## Phase 2: Database Schema

### 2.1 Complete Schema

```sql
-- ============================================================
-- PROFILES TABLE
-- User subscription and quota information
-- ============================================================

CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,

    -- Subscription
    subscription_tier TEXT NOT NULL DEFAULT 'free',
    subscription_status TEXT NOT NULL DEFAULT 'active',
    stripe_customer_id TEXT UNIQUE,
    stripe_subscription_id TEXT,
    subscription_start_date TIMESTAMPTZ,
    subscription_end_date TIMESTAMPTZ,

    -- Quota (resets monthly)
    quota_limit INTEGER NOT NULL DEFAULT 50,
    quota_used INTEGER NOT NULL DEFAULT 0,
    quota_reset_date TIMESTAMPTZ NOT NULL DEFAULT (date_trunc('month', NOW()) + INTERVAL '1 month'),

    -- Metadata
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- DEVICES TABLE
-- Registered devices for each user
-- ============================================================

CREATE TABLE devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL,
    device_name TEXT,
    platform TEXT NOT NULL, -- 'macos', 'android', 'ios'
    app_version TEXT,
    last_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(user_id, device_id)
);

-- ============================================================
-- USAGE_LOGS TABLE
-- Track all API usage for quota management
-- ============================================================

CREATE TABLE usage_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    device_id TEXT,
    endpoint TEXT NOT NULL, -- 'transcribe', 'refine'
    duration_seconds REAL,
    word_count INTEGER,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- HISTORY TABLE
-- Transcription history (synced across devices)
-- ============================================================

CREATE TABLE history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    device_id TEXT,
    transcription TEXT NOT NULL,
    refined_text TEXT,
    audio_duration REAL,
    style TEXT,
    script_mode TEXT,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- SUSPICIOUS_ACTIVITIES TABLE
-- Fraud detection and security monitoring
-- ============================================================

CREATE TABLE suspicious_activities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    activity_type TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX idx_profiles_email ON profiles(email);
CREATE INDEX idx_profiles_stripe_customer ON profiles(stripe_customer_id);
CREATE INDEX idx_devices_user_id ON devices(user_id);
CREATE INDEX idx_usage_logs_user_id ON usage_logs(user_id);
CREATE INDEX idx_usage_logs_created_at ON usage_logs(created_at);
CREATE INDEX idx_history_user_id ON history(user_id);
CREATE INDEX idx_history_timestamp ON history(timestamp);
CREATE INDEX idx_suspicious_activities_user_id ON suspicious_activities(user_id);
```

### 2.2 Row Level Security (RLS)

**Security Model**: Users can only access their own data.

```sql
-- Enable RLS on all tables
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE usage_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE history ENABLE ROW LEVEL SECURITY;
ALTER TABLE suspicious_activities ENABLE ROW LEVEL SECURITY;

-- Profiles policies
CREATE POLICY "Users can view own profile"
    ON profiles FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "Users can update own profile"
    ON profiles FOR UPDATE
    USING (auth.uid() = id);

-- Devices policies
CREATE POLICY "Users can view own devices"
    ON devices FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own devices"
    ON devices FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Usage logs policies
CREATE POLICY "Users can view own usage"
    ON usage_logs FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own usage"
    ON usage_logs FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- History policies
CREATE POLICY "Users can view own history"
    ON history FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own history"
    ON history FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own history"
    ON history FOR DELETE
    USING (auth.uid() = user_id);

-- Suspicious activities policies
CREATE POLICY "Users can view own activities"
    ON suspicious_activities FOR SELECT
    USING (auth.uid() = user_id);
```

### 2.3 Database Functions

```sql
-- Auto-create profile on user signup
CREATE OR REPLACE FUNCTION create_profile_for_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO profiles (id, email, subscription_tier, subscription_status)
    VALUES (NEW.id, NEW.email, 'free', 'active');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION create_profile_for_user();

-- Update timestamp on profile update
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER profiles_updated_at
    BEFORE UPDATE ON profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();
```

---

## Phase 3: Edge Functions

### 3.1 Function Overview

| Function | Purpose | Auth Required | Rate Limit |
|----------|---------|---------------|------------|
| `validate-subscription` | Check subscription & quota | ✅ Yes | 60/min |
| `log-usage` | Track API usage | ✅ Yes | 120/min |
| `register-device` | Register new device | ✅ Yes | 10/min |
| `sync-history` | Sync transcription history | ✅ Yes | 30/min |
| `get-api-key` | Get managed Groq API key | ✅ Yes | 60/min |
| `create-checkout` | Create Stripe checkout | ✅ Yes | 10/min |
| `create-portal` | Create Stripe portal | ✅ Yes | 10/min |
| `stripe-webhook` | Handle Stripe webhooks | ❌ No | N/A |
| `proxy-transcribe` | Proxy to Groq Whisper | ✅ Yes | 30/min |
| `proxy-refine` | Proxy to Groq Llama | ✅ Yes | 30/min |

### 3.2 Shared Utilities

**File**: `supabase/functions/_shared/utils.ts`

```typescript
// Authentication & user retrieval
export async function getUserFromRequest(req: Request, supabaseClient: SupabaseClient) {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) throw new Error("Missing authorization header");

  const token = authHeader.replace("Bearer ", "");
  const { data: { user }, error } = await supabaseClient.auth.getUser(token);

  if (error || !user) throw new Error("Invalid token");
  return user;
}

// Rate limiting
export async function checkRateLimit(
  supabaseClient: SupabaseClient,
  userId: string,
  action: string,
  limit: number,
  windowMinutes: number
): Promise<boolean> {
  // Implementation tracks requests in time window
  // Returns true if within limit, false if exceeded
}

// Quota checking
export async function checkQuota(
  supabaseClient: SupabaseClient,
  userId: string,
  requiredQuota: number = 1
): Promise<{ allowed: boolean; reason?: string }> {
  // Checks if user has remaining quota
  // Returns {allowed: true} or {allowed: false, reason: "..."}
}
```

### 3.3 Detailed Function Documentation

#### 1. validate-subscription

**Purpose**: Check user's subscription tier, status, and quota

**Endpoint**: `POST /functions/v1/validate-subscription`

**Request**:
```bash
curl -X POST https://yrsviodciuepunofxoja.supabase.co/functions/v1/validate-subscription \
  -H "Authorization: Bearer {ACCESS_TOKEN}" \
  -H "apikey: {SUPABASE_ANON_KEY}"
```

**Response**:
```json
{
  "valid": true,
  "tier": "pro",
  "status": "active",
  "features": {
    "byok": false,
    "priority_support": true,
    "api_access": true,
    "custom_prompts": true,
    "riffs_limit": null,
    "seconds_limit": null
  },
  "quota": {
    "riffs_limit": null,
    "riffs_used": 125,
    "seconds_limit": null,
    "seconds_used": 3600,
    "reset_date": "2026-03-01T00:00:00Z"
  },
  "subscription_end_date": "2026-12-31T23:59:59Z"
}
```

**Logic**:
1. Get user from JWT token
2. Fetch profile from database
3. Check subscription status
4. Return tier, features, and quota info

---

#### 2. log-usage

**Purpose**: Track API usage for quota enforcement

**Endpoint**: `POST /functions/v1/log-usage`

**Request**:
```bash
curl -X POST https://yrsviodciuepunofxoja.supabase.co/functions/v1/log-usage \
  -H "Authorization: Bearer {ACCESS_TOKEN}" \
  -H "apikey: {SUPABASE_ANON_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "endpoint": "transcribe",
    "duration_seconds": 45.5,
    "word_count": 250,
    "metadata": {
      "model": "whisper-large-v3",
      "language": "en"
    }
  }'
```

**Response**:
```json
{
  "success": true,
  "quota_used": 126,
  "quota_remaining": null
}
```

**Logic**:
1. Authenticate user
2. Insert usage log
3. Increment quota_used in profiles
4. Return updated quota

---

#### 3. register-device

**Purpose**: Register a device for multi-device sync

**Endpoint**: `POST /functions/v1/register-device`

**Request**:
```bash
curl -X POST https://yrsviodciuepunofxoja.supabase.co/functions/v1/register-device \
  -H "Authorization: Bearer {ACCESS_TOKEN}" \
  -H "apikey: {SUPABASE_ANON_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "mac-12345",
    "device_name": "MacBook Pro",
    "platform": "macos",
    "app_version": "1.0.0"
  }'
```

**Response**:
```json
{
  "success": true,
  "device_id": "mac-12345"
}
```

---

#### 4. sync-history

**Purpose**: Sync transcription history across devices

**Endpoint**: `POST /functions/v1/sync-history`

**Request**:
```bash
curl -X POST https://yrsviodciuepunofxoja.supabase.co/functions/v1/sync-history \
  -H "Authorization: Bearer {ACCESS_TOKEN}" \
  -H "apikey: {SUPABASE_ANON_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "entries": [
      {
        "device_id": "mac-12345",
        "transcription": "Hello world",
        "refined_text": "Hello, world!",
        "audio_duration": 2.5,
        "timestamp": "2026-02-28T10:00:00Z"
      }
    ]
  }'
```

**Response**:
```json
{
  "success": true,
  "synced_count": 1
}
```

---

#### 5. get-api-key

**Purpose**: Fetch managed Groq API key for paid users

**Endpoint**: `POST /functions/v1/get-api-key`

**Request**:
```bash
curl -X POST https://yrsviodciuepunofxoja.supabase.co/functions/v1/get-api-key \
  -H "Authorization: Bearer {ACCESS_TOKEN}" \
  -H "apikey: {SUPABASE_ANON_KEY}"
```

**Response**:
```json
{
  "api_key": "riff_managed_abc123...",
  "provider": "groq"
}
```

**Logic**:
1. Check if user is on paid tier
2. If free tier, return error (requires BYOK)
3. If paid, return managed Groq API key

---

#### 6. create-checkout

**Purpose**: Create Stripe checkout session for subscription

**Endpoint**: `POST /functions/v1/create-checkout`

**Request**:
```bash
curl -X POST https://yrsviodciuepunofxoja.supabase.co/functions/v1/create-checkout \
  -H "Authorization: Bearer {ACCESS_TOKEN}" \
  -H "apikey: {SUPABASE_ANON_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "price_id": "price_1ABC123..."
  }'
```

**Response**:
```json
{
  "url": "https://checkout.stripe.com/c/pay/cs_test_..."
}
```

**Logic**:
1. Get or create Stripe customer
2. Create checkout session with price_id
3. Set success/cancel URLs
4. Return checkout URL

---

#### 7. create-portal

**Purpose**: Create Stripe customer portal for billing management

**Endpoint**: `POST /functions/v1/create-portal`

**Request**:
```bash
curl -X POST https://yrsviodciuepunofxoja.supabase.co/functions/v1/create-portal \
  -H "Authorization: Bearer {ACCESS_TOKEN}" \
  -H "apikey: {SUPABASE_ANON_KEY}"
```

**Response**:
```json
{
  "url": "https://billing.stripe.com/p/session/..."
}
```

---

#### 8. stripe-webhook

**Purpose**: Handle Stripe webhook events

**Endpoint**: `POST /functions/v1/stripe-webhook`

**Signature Verification**: Required (Stripe-Signature header)

**Events Handled**:
- `customer.subscription.created` → Activate subscription
- `customer.subscription.updated` → Update subscription details
- `customer.subscription.deleted` → Downgrade to free tier
- `invoice.payment_succeeded` → Confirm payment
- `invoice.payment_failed` → Handle failed payment

**Logic**:
```typescript
// Verify Stripe signature
const signature = req.headers.get("Stripe-Signature");
const event = stripe.webhooks.constructEvent(body, signature, webhookSecret);

switch (event.type) {
  case "customer.subscription.created":
    // Update profile with subscription details
    await supabase.from("profiles").update({
      subscription_tier: getTierFromPriceId(subscription.items.data[0].price.id),
      subscription_status: "active",
      stripe_subscription_id: subscription.id,
      subscription_start_date: new Date(subscription.current_period_start * 1000),
      subscription_end_date: new Date(subscription.current_period_end * 1000)
    }).eq("stripe_customer_id", subscription.customer);
    break;

  case "customer.subscription.deleted":
    // Downgrade to free tier
    await supabase.from("profiles").update({
      subscription_tier: "free",
      subscription_status: "canceled",
      stripe_subscription_id: null
    }).eq("stripe_customer_id", subscription.customer);
    break;
}
```

---

#### 9. proxy-transcribe

**Purpose**: Proxy audio transcription to Groq Whisper API

**Endpoint**: `POST /functions/v1/proxy-transcribe`

**Request**:
```bash
curl -X POST https://yrsviodciuepunofxoja.supabase.co/functions/v1/proxy-transcribe \
  -H "Authorization: Bearer {ACCESS_TOKEN}" \
  -H "apikey: {SUPABASE_ANON_KEY}" \
  -H "Content-Type: multipart/form-data" \
  -F "file=@audio.wav" \
  -F "model=whisper-large-v3" \
  -F "language=en"
```

**Response**:
```json
{
  "text": "This is the transcribed text from the audio file."
}
```

**Logic**:
1. Check quota
2. Get effective API key (BYOK or managed)
3. Forward request to Groq API
4. Log usage
5. Return transcription

---

#### 10. proxy-refine

**Purpose**: Proxy text refinement to Groq Llama API

**Endpoint**: `POST /functions/v1/proxy-refine`

**Request**:
```bash
curl -X POST https://yrsviodciuepunofxoja.supabase.co/functions/v1/proxy-refine \
  -H "Authorization: Bearer {ACCESS_TOKEN}" \
  -H "apikey: {SUPABASE_ANON_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "raw transcription text here",
    "style": "professional",
    "script_mode": "prose"
  }'
```

**Response**:
```json
{
  "refined_text": "Polished, refined version of the transcription."
}
```

**Logic**:
1. Check quota
2. Get effective API key
3. Build prompt based on style/script_mode
4. Call Groq Llama API
5. Log usage
6. Return refined text

---

## Phase 4: Authentication Flow

### 4.1 Token Storage Architecture

**The Critical Fix**: Tokens must be stored in **macOS Keychain**, not UserDefaults.

```
┌─────────────────────────────────────────────────────┐
│              Token Storage Strategy                 │
├─────────────────────────────────────────────────────┤
│                                                     │
│  Swift UI (RiffControlCenter)                      │
│  └─ storeTokens()                                  │
│     ├─ Keychain ← PRIMARY (for Python)            │
│     └─ UserDefaults ← BACKUP (for Swift)          │
│                                                     │
│  Python Backend                                     │
│  └─ _get_access_token()                           │
│     └─ Keychain ONLY                               │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### 4.2 Complete Authentication Flow

#### Sign Up Flow

```
User enters email/password in LoginView
          ↓
Swift: signUpWithEmail(email, password)
          ↓
POST /auth/v1/signup
  Headers: {apikey: SUPABASE_ANON_KEY}
  Body: {email, password}
          ↓
Supabase Auth creates user
          ↓
Response: {access_token, refresh_token, user: {id, email}}
          ↓
Swift: storeTokens(accessToken, refreshToken)
  ├─ Store in Keychain (service: "riff")
  │  ├─ account: "supabase_access_token"
  │  └─ account: "supabase_refresh_token"
  └─ Store in UserDefaults (backup)
          ↓
Swift: writeAuthState(authenticated: true, email, userId)
  └─ Write to ~/Library/Application Support/Riff/auth_state.json
          ↓
Database Trigger: create_profile_for_user()
  └─ Insert into profiles (free tier, active)
          ↓
Python: Detects auth_state.json change
  └─ Loads tokens from Keychain
          ↓
✅ User is authenticated in both Swift and Python
```

#### Sign In Flow

```
User enters email/password in LoginView
          ↓
Swift: signInWithEmail(email, password)
          ↓
POST /auth/v1/token?grant_type=password
  Headers: {apikey: SUPABASE_ANON_KEY}
  Body: {email, password}
          ↓
Supabase Auth validates credentials
          ↓
Response: {access_token, refresh_token, user: {id, email}}
          ↓
Swift: storeTokens(accessToken, refreshToken)
  [Same as signup - Keychain + UserDefaults]
          ↓
Swift: writeAuthState(authenticated: true, email, userId)
          ↓
Python: Detects auth_state.json change
  └─ Loads tokens from Keychain
          ↓
✅ User is authenticated
```

#### OAuth Flow (Google/GitHub/Apple)

```
User clicks "Continue with Google"
          ↓
Swift: signInWithOAuth(provider: "google")
          ↓
Opens system browser:
  https://yrsviodciuepunofxoja.supabase.co/auth/v1/authorize?
    provider=google&
    redirect_to=riff://oauth/callback
          ↓
User authorizes in browser
          ↓
Browser redirects to: riff://oauth/callback#access_token=...&refresh_token=...
          ↓
Swift: handleOAuthCallback(url)
  └─ Parse access_token and refresh_token from URL fragment
          ↓
Swift: storeTokens(accessToken, refreshToken)
  [Same as email/password]
          ↓
✅ OAuth authentication complete
```

### 4.3 Token Refresh Flow

```
Python makes API call with access_token
          ↓
Supabase returns 401 Unauthorized (token expired)
          ↓
Python: refresh_token()
          ↓
POST /auth/v1/token?grant_type=refresh_token
  Headers: {apikey: SUPABASE_ANON_KEY}
  Body: {refresh_token}
          ↓
Response: {access_token, refresh_token} (new tokens)
          ↓
Python: _store_tokens(access_token, refresh_token)
  └─ Update Keychain
          ↓
Retry original API call with new token
          ↓
✅ Request succeeds
```

### 4.4 Sign Out Flow

```
User clicks "Sign Out"
          ↓
Swift: signOut()
  ├─ Clear Keychain
  │  ├─ Delete supabase_access_token
  │  ├─ Delete supabase_refresh_token
  │  └─ Delete managed_groq_key
  ├─ Clear UserDefaults
  └─ writeAuthState(authenticated: false)
          ↓
Python: Detects auth_state.json change
  └─ Clears cached tokens
          ↓
✅ User signed out from both Swift and Python
```

---

## Phase 5: Swift UI Integration

### 5.1 SwiftAuthManager

**File**: `config_ui/RiffControlCenter/SwiftAuthManager.swift`

**Purpose**: Manages authentication in Swift UI

**Key Methods**:

```swift
class SwiftAuthManager: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var userEmail: String = ""
    @Published var userId: String = ""
    @Published var subscriptionTier: String = "free"
    @Published var quota: QuotaInfo?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // Authentication
    func signUpWithEmail(email: String, password: String) async throws
    func signInWithEmail(email: String, password: String) async throws
    func signInWithOAuth(provider: String)
    func signOut()

    // Subscription
    func validateSubscription() async throws

    // Token Management (CRITICAL)
    private func storeTokens(accessToken: String, refreshToken: String) {
        // Store in Keychain for Python
        storeInKeychain(service: "riff", account: "supabase_access_token", value: accessToken)
        storeInKeychain(service: "riff", account: "supabase_refresh_token", value: refreshToken)

        // Store in UserDefaults for Swift
        UserDefaults.standard.set(accessToken, forKey: "supabase_access_token")
        UserDefaults.standard.set(refreshToken, forKey: "supabase_refresh_token")
    }

    private func storeInKeychain(service: String, account: String, value: String) {
        let data = value.data(using: .utf8)!

        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    // IPC with Python
    private func writeAuthState(authenticated: Bool, email: String, userId: String) {
        let state = AuthState(
            authenticated: authenticated,
            email: email,
            userId: userId,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
        try? JSONEncoder().encode(state).write(to: authStatePath)
    }
}
```

### 5.2 IPC Between Swift and Python

**Mechanism**: JSON file sharing

**Auth State File**: `~/Library/Application Support/Riff/auth_state.json`

**Format**:
```json
{
  "authenticated": true,
  "email": "user@example.com",
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": "2026-02-28T10:30:00Z"
}
```

**Flow**:
1. Swift writes `auth_state.json` when auth state changes
2. Python polls file every 2 seconds
3. Python reads state and loads tokens from Keychain
4. Both Swift and Python stay in sync

---

## Phase 6: Python Backend Integration

### 6.1 AuthManager

**File**: `utils/auth_manager.py`

**Purpose**: Manages authentication, subscription, and quota in Python

**Key Methods**:

```python
class AuthManager:
    def __init__(self, config_manager):
        self.supabase_url = config["auth"]["supabase_url"]
        self.supabase_anon_key = config["auth"]["supabase_anon_key"]
        self._access_token = None
        self._refresh_token = None

    # ==================== Authentication ====================

    @property
    def is_authenticated(self) -> bool:
        """Check if user has valid tokens"""
        return self._get_access_token() is not None

    def _get_access_token(self) -> Optional[str]:
        """Get access token from Keychain"""
        if self._access_token:
            return self._access_token

        try:
            token = keyring.get_password("riff", "supabase_access_token")
            if token:
                self._access_token = token
            return token
        except Exception as e:
            logger.error(f"Error getting access token: {e}")
            return None

    def _store_tokens(self, access_token: str, refresh_token: str):
        """Store tokens in macOS Keychain"""
        keyring.set_password("riff", "supabase_access_token", access_token)
        keyring.set_password("riff", "supabase_refresh_token", refresh_token)
        self._access_token = access_token
        self._refresh_token = refresh_token

    # ==================== Subscription ====================

    def validate_subscription(self, force_online: bool = False) -> Dict[str, Any]:
        """
        Validate subscription with offline caching:
        - < 7 days: use cache
        - 7-14 days: try online, fallback to cache
        - > 14 days: require online
        """
        # Check cache age
        if not force_online and self._cached_subscription:
            age = datetime.now() - self._last_validated
            if age < timedelta(days=7):
                return self._cached_subscription

        # Online validation
        return self._validate_online()

    def _validate_online(self) -> Optional[Dict[str, Any]]:
        """Call validate-subscription Edge Function"""
        url = f"{self.supabase_url}/functions/v1/validate-subscription"
        headers = {
            "Authorization": f"Bearer {self._get_access_token()}",
            "apikey": self.supabase_anon_key
        }

        response = httpx.post(url, headers=headers, timeout=10.0)
        result = response.json()

        # Cache result
        self._cached_subscription = result
        self._last_validated = datetime.now()
        self._save_cache()

        return result

    # ==================== Quota Management ====================

    def can_riff(self) -> Tuple[bool, str]:
        """Check if user can create a riff"""
        subscription = self.validate_subscription()

        # Check quota
        quota = subscription.get("quota", {})
        tier = subscription.get("tier", "free")
        features = get_tier_features(tier)

        # Check riff limit
        if features.riffs_limit is not None:
            if quota["riffs_used"] >= features.riffs_limit:
                return False, f"Monthly riff limit reached ({features.riffs_limit})"

        # Check recording time limit
        if features.seconds_limit is not None:
            if quota["seconds_used"] >= features.seconds_limit:
                return False, f"Recording time limit reached"

        return True, "OK"

    # ==================== API Key Management ====================

    def get_effective_api_key(self) -> Optional[str]:
        """Get API key based on tier"""
        tier = self.get_tier()
        features = get_tier_features(tier)

        if features.byok:
            # Free tier: use BYOK
            return self.config.config.get("api", {}).get("api_key", "")
        else:
            # Paid tiers: fetch managed key
            return self._fetch_managed_key()

    def _fetch_managed_key(self) -> Optional[str]:
        """Fetch managed Groq API key from backend"""
        # Check cache first
        cached_key = keyring.get_password("riff", "managed_groq_key")
        if cached_key:
            return cached_key

        # Fetch from backend
        url = f"{self.supabase_url}/functions/v1/get-api-key"
        headers = {
            "Authorization": f"Bearer {self._get_access_token()}",
            "apikey": self.supabase_anon_key
        }

        response = httpx.post(url, headers=headers, timeout=10.0)
        result = response.json()
        api_key = result.get("api_key")

        # Cache in keychain
        keyring.set_password("riff", "managed_groq_key", api_key)

        return api_key

    # ==================== Usage Logging ====================

    def log_usage(self, word_count: int, recording_seconds: float,
                  style: str, script_mode: str):
        """Log riff usage to backend"""
        url = f"{self.supabase_url}/functions/v1/log-usage"
        headers = {
            "Authorization": f"Bearer {self._get_access_token()}",
            "apikey": self.supabase_anon_key,
            "Content-Type": "application/json"
        }
        data = {
            "word_count": word_count,
            "recording_seconds": recording_seconds,
            "style": style,
            "script_mode": script_mode
        }

        httpx.post(url, headers=headers, json=data, timeout=10.0)
```

---

## Subscription System

### Subscription Tiers

| Tier | Price | Riffs/Month | Hours/Month | Features |
|------|-------|-------------|-------------|----------|
| **Free** | $0 | 50 | 5 hours | BYOK, Basic support |
| **Starter** | $9/mo | 500 | 50 hours | Managed API, Email support |
| **Pro** | $29/mo | Unlimited | Unlimited | Priority support, API access |
| **Business** | $99/mo | Unlimited | Unlimited | Custom prompts, SLA, Phone support |

### Tier Configuration

**File**: `utils/subscription_config.py`

```python
@dataclass
class TierFeatures:
    name: str
    byok: bool                      # Bring Your Own Key
    priority_support: bool
    api_access: bool
    custom_prompts: bool
    riffs_limit: Optional[int]      # None = unlimited
    seconds_limit: Optional[int]    # None = unlimited

TIER_FEATURES = {
    "free": TierFeatures(
        name="Free",
        byok=True,
        priority_support=False,
        api_access=False,
        custom_prompts=False,
        riffs_limit=50,
        seconds_limit=18000  # 5 hours
    ),
    "starter": TierFeatures(
        name="Starter",
        byok=False,
        priority_support=False,
        api_access=False,
        custom_prompts=False,
        riffs_limit=500,
        seconds_limit=180000  # 50 hours
    ),
    "pro": TierFeatures(
        name="Pro",
        byok=False,
        priority_support=True,
        api_access=True,
        custom_prompts=True,
        riffs_limit=None,  # Unlimited
        seconds_limit=None  # Unlimited
    ),
    "business": TierFeatures(
        name="Business",
        byok=False,
        priority_support=True,
        api_access=True,
        custom_prompts=True,
        riffs_limit=None,
        seconds_limit=None
    )
}
```

### Stripe Product/Price IDs

**Configure in Stripe Dashboard → Products**

```python
STRIPE_PRICE_IDS = {
    "starter_monthly": "price_1ABC...",
    "starter_yearly": "price_1DEF...",
    "pro_monthly": "price_1GHI...",
    "pro_yearly": "price_1JKL...",
    "business_monthly": "price_1MNO...",
    "business_yearly": "price_1PQR..."
}
```

### Quota Reset

**Automatic Monthly Reset**:

```sql
-- Runs on 1st of every month
CREATE OR REPLACE FUNCTION reset_monthly_quotas()
RETURNS void AS $$
BEGIN
    UPDATE profiles
    SET quota_used = 0,
        quota_reset_date = date_trunc('month', NOW()) + INTERVAL '1 month'
    WHERE quota_reset_date <= NOW();
END;
$$ LANGUAGE plpgsql;

-- Schedule with pg_cron or external cron
SELECT cron.schedule('reset-quotas', '0 0 1 * *', 'SELECT reset_monthly_quotas()');
```

---

## Quota Management

### How Quotas Work

```
┌─────────────────────────────────────────────────────┐
│                  Quota Lifecycle                     │
├─────────────────────────────────────────────────────┤
│                                                      │
│  1. User creates riff                               │
│     └─ Check: can_riff()                            │
│        ├─ validate_subscription()                   │
│        └─ Check quota_used < quota_limit            │
│                                                      │
│  2. If allowed, proceed with transcription          │
│                                                      │
│  3. After completion, log usage                     │
│     └─ log_usage(word_count, seconds)               │
│        └─ Increment quota_used in database          │
│                                                      │
│  4. Monthly reset (1st of month)                    │
│     └─ quota_used = 0                               │
│     └─ quota_reset_date = next month                │
│                                                      │
└─────────────────────────────────────────────────────┘
```

### Quota Enforcement Points

**1. Before Recording** (Python):
```python
allowed, reason = auth_manager.can_riff()
if not allowed:
    show_quota_exceeded_dialog(reason)
    return
```

**2. In Edge Function** (TypeScript):
```typescript
const quotaCheck = await checkQuota(supabase, user.id, 1);
if (!quotaCheck.allowed) {
    return new Response(
        JSON.stringify({ error: quotaCheck.reason }),
        { status: 403 }
    );
}
```

**3. After Usage** (Python):
```python
auth_manager.log_usage(
    word_count=len(transcription.split()),
    recording_seconds=audio_duration,
    style=style,
    script_mode=script_mode
)
```

---

## API Proxy System

### Why Proxy?

1. **Quota Enforcement**: Backend controls usage
2. **Key Management**: Users don't need API keys (paid tiers)
3. **Usage Tracking**: Centralized logging
4. **Security**: API keys never exposed to client
5. **Rate Limiting**: Prevent abuse

### Proxy Flow

```
User records audio
       ↓
Python: Check quota with can_riff()
       ↓
Python: Get effective API key
  ├─ Free tier: config["api"]["api_key"] (BYOK)
  └─ Paid tier: fetch from get-api-key Edge Function
       ↓
Python: Call proxy-transcribe Edge Function
       ↓
Edge Function: Verify quota
       ↓
Edge Function: Forward to Groq Whisper API
       ↓
Groq: Transcribe audio
       ↓
Edge Function: Return transcription
       ↓
Edge Function: Log usage
       ↓
Python: Receive transcription
       ↓
Python: Call proxy-refine Edge Function
       ↓
Edge Function: Forward to Groq Llama API
       ↓
Groq: Refine text
       ↓
Edge Function: Return refined text
       ↓
Edge Function: Log usage
       ↓
Python: Display result to user
```

### BYOK vs Managed Keys

| Tier | API Key Source | How It Works |
|------|----------------|--------------|
| **Free** | BYOK (User provides) | User adds Groq API key to `config.json` |
| **Starter** | Managed (Backend) | Backend provides API key via `get-api-key` |
| **Pro** | Managed | Same as Starter |
| **Business** | Managed | Same as Starter |

---

## Data Flow Examples

### Example 1: User Signs Up and Creates First Riff

```
[1] User enters email/password in LoginView
       ↓
[2] Swift: signUpWithEmail()
    POST /auth/v1/signup
       ↓
[3] Supabase Auth creates user
    Returns: {access_token, refresh_token, user}
       ↓
[4] Swift: storeTokens() → Keychain + UserDefaults
       ↓
[5] Swift: writeAuthState() → auth_state.json
       ↓
[6] Database Trigger: create_profile_for_user()
    INSERT INTO profiles (tier='free', status='active')
       ↓
[7] Python detects auth_state.json change
    Loads tokens from Keychain
       ↓
[8] User presses recording hotkey
       ↓
[9] Python: auth_manager.can_riff()
    └─ validate_subscription()
       POST /functions/v1/validate-subscription
       Returns: {tier: 'free', quota: {riffs_used: 0, riffs_limit: 50}}
    └─ Check: 0 < 50 ✓ Allowed
       ↓
[10] Python: Start recording audio
       ↓
[11] User finishes recording (10 seconds)
       ↓
[12] Python: Get API key
     auth_manager.get_effective_api_key()
     └─ Tier is 'free' → BYOK
     └─ Return config["api"]["api_key"]
       ↓
[13] Python: Transcribe audio
     POST /functions/v1/proxy-transcribe
     Headers: {Authorization: Bearer {token}}
     Body: {file: audio.wav, model: 'whisper-large-v3'}
       ↓
[14] Edge Function: Forward to Groq
     POST https://api.groq.com/openai/v1/audio/transcriptions
     Headers: {Authorization: Bearer {api_key}}
       ↓
[15] Groq: Returns transcription
     {text: "Hello world"}
       ↓
[16] Edge Function: Log usage
     INSERT INTO usage_logs (endpoint='transcribe', duration_seconds=10)
     UPDATE profiles SET quota_used = 1
       ↓
[17] Python: Refine transcription
     POST /functions/v1/proxy-refine
     Body: {text: "Hello world", style: "professional"}
       ↓
[18] Edge Function: Forward to Groq Llama
     POST https://api.groq.com/openai/v1/chat/completions
       ↓
[19] Groq: Returns refined text
     {refined_text: "Hello, world!"}
       ↓
[20] Edge Function: Log usage
     UPDATE profiles SET quota_used = 1 (if counting refine separately)
       ↓
[21] Python: Inject refined text into clipboard/app
       ↓
[22] Python: Sync to history
     POST /functions/v1/sync-history
     Body: {entries: [{transcription, refined_text, ...}]}
       ↓
[23] Edge Function: Insert into history table
     INSERT INTO history (user_id, transcription, refined_text, ...)
       ↓
✅ Complete! Quota now: 1/50 riffs used
```

### Example 2: User Upgrades to Pro Tier

```
[1] User clicks "Upgrade to Pro" in app
       ↓
[2] Swift: Create checkout session
    POST /functions/v1/create-checkout
    Body: {price_id: "price_1GHI..."} (Pro monthly)
       ↓
[3] Edge Function: Get/create Stripe customer
    stripe.customers.create({email, metadata: {user_id}})
       ↓
[4] Edge Function: Create checkout session
    stripe.checkout.sessions.create({
      customer: customer_id,
      line_items: [{price: price_id, quantity: 1}],
      success_url: "riff://checkout/success",
      cancel_url: "riff://checkout/cancel"
    })
       ↓
[5] Edge Function: Update profile with customer_id
    UPDATE profiles SET stripe_customer_id = customer_id
       ↓
[6] Edge Function: Return checkout URL
    {url: "https://checkout.stripe.com/..."}
       ↓
[7] Swift: Open checkout URL in browser
       ↓
[8] User completes payment in Stripe
       ↓
[9] Stripe: Creates subscription
       ↓
[10] Stripe: Sends webhook event
     POST /functions/v1/stripe-webhook
     Event: customer.subscription.created
       ↓
[11] Edge Function: Verify webhook signature
       ↓
[12] Edge Function: Update profile
     UPDATE profiles SET
       subscription_tier = 'pro',
       subscription_status = 'active',
       stripe_subscription_id = subscription.id,
       subscription_start_date = ...,
       subscription_end_date = ...,
       quota_limit = NULL  (unlimited)
       ↓
[13] Python: Next validate_subscription() call
     Returns: {tier: 'pro', quota: {riffs_limit: null}}
       ↓
[14] Python: Get API key
     auth_manager.get_effective_api_key()
     └─ Tier is 'pro' → Managed key
     └─ POST /functions/v1/get-api-key
        Returns: {api_key: "riff_managed_..."}
     └─ Cache in Keychain
       ↓
✅ User now on Pro tier with unlimited riffs and managed API key!
```

---

## Security Model

### 1. Authentication Security

**Token Storage**:
- ✅ macOS Keychain (encrypted by OS)
- ❌ NOT in plain text files
- ❌ NOT in UserDefaults (for Python access)

**JWT Tokens**:
- Access token: 1 hour expiry
- Refresh token: 30 days expiry
- Automatic refresh when expired

**Password Requirements**:
- Minimum 8 characters
- Enforced by Supabase Auth

### 2. Row Level Security (RLS)

**All tables have RLS enabled**:
- Users can only access their own data
- Enforced at database level
- No way to bypass (even with direct SQL)

**Example Policy**:
```sql
CREATE POLICY "Users can view own profile"
    ON profiles FOR SELECT
    USING (auth.uid() = id);
```

### 3. API Key Security

**BYOK (Free Tier)**:
- User's API key stored in `config.json`
- Never sent to backend
- Used directly by Python app

**Managed Keys (Paid Tiers)**:
- Backend API key stored in Supabase secrets
- Never exposed to client
- Fetched via authenticated Edge Function
- Cached in Keychain

### 4. Webhook Security

**Stripe Webhooks**:
- Signature verification required
- Uses `STRIPE_WEBHOOK_SECRET`
- Rejects unsigned requests

```typescript
const signature = req.headers.get("Stripe-Signature");
const event = stripe.webhooks.constructEvent(
    body,
    signature,
    webhookSecret
);
```

### 5. Rate Limiting

**Per-user limits**:
- 60 requests/minute for validation
- 30 requests/minute for transcription
- 10 requests/minute for checkout

**Implementation**:
```typescript
const allowed = await checkRateLimit(
    supabase,
    user.id,
    "validate-subscription",
    60,  // limit
    1    // window (minutes)
);
```

### 6. Quota Enforcement

**Multi-layer enforcement**:
1. Client-side check before recording
2. Edge Function check before API call
3. Database-level tracking

**Prevents abuse**:
- Can't bypass quota by calling Edge Function directly
- Can't spoof user_id (verified by JWT)
- Can't manipulate quota_used (RLS prevents updates)

---

## Troubleshooting Guide

### Issue 1: "App keeps loading after signin/signup"

**Symptom**: Login appears to hang, app shows loading indicator

**Root Cause**: Tokens stored in UserDefaults but Python looks in Keychain

**Solution**: Update `SwiftAuthManager.storeTokens()` to use Keychain

**Verify Fix**:
```bash
# Check if token is in Keychain
security find-generic-password -s "riff" -a "supabase_access_token" -w
```

**Expected**: Should print access token
**If empty**: Tokens not being stored correctly

---

### Issue 2: "No access token available"

**Symptom**: Log shows "No access token available"

**Root Cause**:
- Tokens not stored in Keychain
- Keychain access denied
- User not authenticated

**Debug Steps**:
```python
# In Python
import keyring
token = keyring.get_password("riff", "supabase_access_token")
print(f"Token: {token}")
```

**Solution**:
1. Rebuild Swift app with Keychain storage
2. Sign out and sign back in
3. Check `auth_state.json` exists

---

### Issue 3: "Quota exceeded" but quota shows 0/50

**Symptom**: Can't create riff despite quota available

**Root Cause**: Subscription validation failed or cached stale data

**Solution**:
```python
# Force online validation
auth_manager.validate_subscription(force_online=True)
```

**Check Database**:
```sql
SELECT quota_used, quota_limit, quota_reset_date
FROM profiles
WHERE id = 'user-id';
```

---

### Issue 4: "Invalid signature" on Stripe webhook

**Symptom**: Webhook returns 400, logs show signature error

**Root Cause**: Wrong `STRIPE_WEBHOOK_SECRET`

**Solution**:
1. Get webhook signing secret from Stripe Dashboard
2. Update Supabase Edge Function secret
3. Redeploy functions

**Test Webhook**:
```bash
stripe listen --forward-to https://yrsviodciuepunofxoja.supabase.co/functions/v1/stripe-webhook
stripe trigger customer.subscription.created
```

---

### Issue 5: "API key missing" on free tier

**Symptom**: Recording disabled, logs show missing API key

**Root Cause**: User hasn't set BYOK key in config

**Solution**:
1. Add Groq API key to `config.json`:
   ```json
   {
     "api": {
       "api_key": "gsk_..."
     }
   }
   ```
2. Restart app

---

### Issue 6: "Rate limit exceeded"

**Symptom**: Edge Function returns 429

**Root Cause**: Too many requests in short time

**Solution**:
- Wait 1 minute
- Check for infinite loop in code
- Review rate limit settings

**Adjust Rate Limits**:
```typescript
// In Edge Function
const allowed = await checkRateLimit(
    supabase,
    user.id,
    "action-name",
    120,  // Increase limit
    1
);
```

---

### Issue 7: "Database permission denied"

**Symptom**: Edge Function can't query database

**Root Cause**: RLS policy blocking access or service role not used

**Solution**:
```typescript
// Use service role client for admin operations
const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);
```

---

## Common Issues & Solutions

### Development Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "Module not found" | Missing dependency | `pip install -r requirements.txt` |
| "Supabase URL not set" | Missing config | Create `config.json` with credentials |
| "Keychain access denied" | App not signed | Sign app or disable Gatekeeper |
| "Swift build failed" | Xcode version | Update to Xcode 14+ |

### Authentication Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "Invalid token" | Expired access token | Refresh token automatically |
| "User not found" | User deleted from database | Re-signup |
| "Email already registered" | Duplicate signup | Use signin instead |
| "OAuth redirect failed" | URL scheme not registered | Add `riff://` to Info.plist |

### Subscription Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "Subscription not active" | Webhook not received | Manually update profile |
| "Wrong tier after payment" | Webhook failed to process | Check webhook logs, retry |
| "Quota not reset" | Cron job not running | Run `reset_monthly_quotas()` manually |
| "Unlimited showing as 0" | Frontend bug | Check for `null` vs `0` |

### API Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "Groq API error" | Invalid API key | Check key in Supabase secrets |
| "Transcription failed" | Audio format unsupported | Convert to WAV/MP3 |
| "Refinement timeout" | Text too long | Split into chunks |
| "Proxy error 500" | Edge Function crash | Check function logs |

---

## Quick Reference

### Important File Paths

```
~/Library/Application Support/Riff/
├── config.json                    # App configuration
├── auth_state.json               # Swift ↔ Python IPC
└── auth_cache.json               # Subscription cache

Keychain (encrypted):
├── riff:supabase_access_token    # JWT access token
├── riff:supabase_refresh_token   # JWT refresh token
└── riff:managed_groq_key         # Managed API key (paid tiers)
```

### Key URLs

- **Supabase Dashboard**: https://supabase.com/dashboard/project/yrsviodciuepunofxoja
- **Edge Functions**: https://yrsviodciuepunofxoja.supabase.co/functions/v1/
- **Stripe Dashboard**: https://dashboard.stripe.com
- **Groq API**: https://console.groq.com

### Environment Variables

```bash
# Supabase (in config.json)
SUPABASE_URL=https://yrsviodciuepunofxoja.supabase.co
SUPABASE_ANON_KEY=eyJhbGci...

# Supabase Secrets (Edge Functions)
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
GROQ_API_KEY=gsk_...
```

### Testing Commands

```bash
# Test health
./tests/health-check.sh

# Test subscription flow
./tests/subscription-flow-test.sh

# Test webhooks
./tests/webhook-test.sh

# Check Keychain
security find-generic-password -s "riff" -a "supabase_access_token" -w

# Check auth state
cat ~/Library/Application\ Support/Riff/auth_state.json | jq

# View logs
tail -f ~/Documents/Riff/debug.log
```

---

## Summary

This document covers the complete Riff authentication, subscription, and API system:

✅ **Phase 1**: Supabase backend setup
✅ **Phase 2**: PostgreSQL database with RLS
✅ **Phase 3**: 10 Edge Functions for all operations
✅ **Phase 4**: Complete auth flow (signup/signin/OAuth)
✅ **Phase 5**: Swift UI integration with Keychain
✅ **Phase 6**: Python backend integration
✅ **Subscription**: 4-tier system with Stripe
✅ **Quota**: Monthly limits with automatic reset
✅ **Proxy**: Secure API proxying with managed keys
✅ **Security**: RLS, JWT, Keychain, webhook verification
✅ **Troubleshooting**: Common issues and solutions

**This is your complete reference guide for understanding, debugging, and extending the Riff system.** 🚀

---

*Last Updated: 2026-02-28*
*Version: 1.0*
