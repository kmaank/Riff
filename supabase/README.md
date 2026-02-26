# Riff Backend - Supabase Setup Guide

This directory contains the complete Supabase backend infrastructure for Riff, including:
- Database schema (PostgreSQL migrations)
- Edge Functions (Deno runtime)
- Stripe integration for billing
- Multi-tier subscription management
- Device tracking and abuse detection

---

## Prerequisites

1. **Supabase Account**: Create a free account at [supabase.com](https://supabase.com)
2. **Stripe Account**: Create account at [stripe.com](https://stripe.com) (start with test mode)
3. **Supabase CLI**: Install globally
   ```bash
   npm install -g supabase
   ```
4. **Groq API Keys**: Get 3 separate keys for starter/pro/lifetime tiers from [console.groq.com](https://console.groq.com)

---

## Quick Start

### 1. Create Supabase Project

```bash
# Login to Supabase CLI
supabase login

# Initialize local Supabase (optional, for local dev)
supabase init

# Link to your cloud project
supabase link --project-ref your-project-id
```

Or create a new project via CLI:
```bash
supabase projects create riff-backend --org-id your-org-id --region us-west-1
```

### 2. Configure Environment Variables

Create `supabase/.env` from the template:
```bash
cp supabase/.env.example supabase/.env
```

Fill in the values:
```bash
# Get from Supabase Dashboard > Settings > API
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=eyJ...
SUPABASE_SERVICE_KEY=eyJ...

# Generate secrets
openssl rand -hex 32  # For ENCRYPTION_SECRET
openssl rand -hex 32  # For HMAC_SECRET

# Get from Stripe Dashboard
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...  # Configure after deploying webhook function

# Stripe Price IDs (create products first)
STRIPE_PRICE_ID_STARTER=price_...
STRIPE_PRICE_ID_PRO=price_...
STRIPE_PRICE_ID_LIFETIME=price_...

# Your Groq API keys
GROQ_API_KEY_STARTER=gsk_...
GROQ_API_KEY_PRO=gsk_...
GROQ_API_KEY_LIFETIME=gsk_...
```

### 3. Run Database Migrations

```bash
# Apply all migrations to your cloud project
supabase db push

# Or run migrations one by one
supabase migration up
```

Verify migrations:
```bash
# List all tables
supabase db remote list
```

### 4. Deploy Edge Functions

Set all environment secrets:
```bash
supabase secrets set SUPABASE_URL=https://your-project.supabase.co
supabase secrets set SUPABASE_ANON_KEY=eyJ...
supabase secrets set SUPABASE_SERVICE_KEY=eyJ...
supabase secrets set STRIPE_SECRET_KEY=sk_test_...
supabase secrets set ENCRYPTION_SECRET=$(openssl rand -hex 32)
supabase secrets set HMAC_SECRET=$(openssl rand -hex 32)
supabase secrets set GROQ_API_KEY_STARTER=gsk_...
supabase secrets set GROQ_API_KEY_PRO=gsk_...
supabase secrets set GROQ_API_KEY_LIFETIME=gsk_...
# Add Stripe Price IDs and webhook secret after products are created
```

Deploy all functions:
```bash
supabase functions deploy validate-subscription
supabase functions deploy log-usage
supabase functions deploy proxy-transcribe
supabase functions deploy proxy-refine
supabase functions deploy register-device
supabase functions deploy sync-history
supabase functions deploy create-checkout
supabase functions deploy stripe-webhook
supabase functions deploy create-portal
```

### 5. Configure Stripe

#### Create Products and Prices

In Stripe Dashboard > Products:

1. **Starter Plan**
   - Name: "Riff Starter"
   - Price: $9.99/month recurring
   - Copy Price ID to `STRIPE_PRICE_ID_STARTER`

2. **Pro Plan**
   - Name: "Riff Pro"
   - Price: $19.99/month recurring
   - Copy Price ID to `STRIPE_PRICE_ID_PRO`

3. **Lifetime Plan**
   - Name: "Riff Lifetime"
   - Price: $149.00 one-time payment
   - Copy Price ID to `STRIPE_PRICE_ID_LIFETIME`

Update secrets:
```bash
supabase secrets set STRIPE_PRICE_ID_STARTER=price_...
supabase secrets set STRIPE_PRICE_ID_PRO=price_...
supabase secrets set STRIPE_PRICE_ID_LIFETIME=price_...
```

#### Configure Webhook

1. In Stripe Dashboard > Developers > Webhooks, click "Add endpoint"
2. URL: `https://your-project.supabase.co/functions/v1/stripe-webhook`
3. Events to listen:
   - `checkout.session.completed`
   - `invoice.payment_succeeded`
   - `invoice.payment_failed`
   - `customer.subscription.deleted`
   - `customer.subscription.updated`
4. Copy webhook signing secret to:
   ```bash
   supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_...
   ```

#### Test Webhooks Locally

```bash
# Install Stripe CLI
brew install stripe/stripe-cli/stripe

# Login
stripe login

# Forward webhooks to local function
stripe listen --forward-to http://localhost:54321/functions/v1/stripe-webhook
```

### 6. Configure OAuth Providers

In Supabase Dashboard > Authentication > Providers, enable:

- **Google**: Add OAuth Client ID and Secret
- **GitHub**: Add OAuth App credentials
- **Apple**: Add Service ID and Key
- Redirect URLs: Set to `riff://oauth/callback`

### 7. Verify Deployment

Test each Edge Function:

```bash
# Get your access token (login via Supabase client first)
export ACCESS_TOKEN="eyJ..."

# Test validate-subscription
curl -X POST https://your-project.supabase.co/functions/v1/validate-subscription \
  -H "Authorization: Bearer $ACCESS_TOKEN"

# Test register-device
curl -X POST https://your-project.supabase.co/functions/v1/register-device \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"device_id":"test-device-123","device_type":"mac"}'

# Test sync-history (download)
curl -X GET https://your-project.supabase.co/functions/v1/sync-history \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

---

## Database Schema

### Tables

| Table | Purpose | RLS Enabled |
|---|---|---|
| `profiles` | User profile data | ✅ |
| `subscriptions` | Subscription status and billing | ✅ |
| `usage_logs` | Per-riff usage tracking | ✅ |
| `devices` | Device registration (max 3) | ✅ |
| `riff_history` | Cloud-synced history | ✅ |
| `suspicious_activity` | Abuse detection logs | ✅ (admin-only) |

### Views

- `monthly_usage` - Aggregated quota for current month

### Functions (PostgreSQL)

- `register_device()` - Register/update device, enforce 3-device limit
- `get_monthly_usage()` - Get user's current month usage
- `detect_concurrent_usage()` - Detect account sharing
- `log_suspicious_activity()` - Log security events
- `should_block_user()` - Check if user should be blocked

---

## Edge Functions Reference

### Authentication

All Edge Functions (except `stripe-webhook`) require:
- **Authorization**: `Bearer <access_token>`
- **HMAC Signature** (for sensitive operations): `X-Request-Signature: timestamp:signature`

### validate-subscription

**Method**: `POST`
**Auth**: Required
**Returns**: Subscription status, tier, quota, features

```typescript
{
  valid: boolean,
  tier: "free" | "starter" | "pro" | "lifetime",
  status: "active" | "past_due" | "canceled" | "expired",
  quota: {
    riffs_limit: number | null,
    riffs_used: number,
    seconds_limit: number | null,
    seconds_used: number
  },
  features: {
    all_styles: boolean,
    custom_prompts: boolean,
    priority: boolean,
    byok: boolean
  },
  managed_key_available: boolean
}
```

### log-usage

**Method**: `POST`
**Auth**: Required + HMAC signature
**Body**:
```json
{
  "word_count": 150,
  "recording_seconds": 12.5,
  "style": "casual",
  "script_mode": "english_mixed",
  "device_id": "mac-abc123"
}
```

### proxy-transcribe

**Method**: `POST`
**Auth**: Required + HMAC signature
**Body**: `multipart/form-data` with audio file
**Returns**: Groq Whisper transcription response

### proxy-refine

**Method**: `POST`
**Auth**: Required + HMAC signature
**Body**:
```json
{
  "messages": [...],
  "model": "llama-3.3-70b-versatile",
  "style": "casual"
}
```
**Returns**: Groq LLM completion response

### register-device

**Method**: `POST`
**Auth**: Required
**Body**:
```json
{
  "device_id": "mac-abc123",
  "device_name": "MacBook Pro",
  "device_type": "mac",
  "os_version": "14.2",
  "app_version": "1.0.0"
}
```

### sync-history

**GET**: Download history
**POST**: Upload history (single or batch)

**Upload Body**:
```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "original": "raw text",
  "refined": "refined text",
  "style": "casual",
  "script_mode": "english_mixed"
}
```

### create-checkout

**Method**: `POST`
**Auth**: Required
**Body**:
```json
{
  "tier": "starter" | "pro" | "lifetime"
}
```
**Returns**: `{ url: string, session_id: string }`

### stripe-webhook

**Method**: `POST`
**Auth**: Stripe signature header
**Handles**: All Stripe subscription lifecycle events

### create-portal

**Method**: `POST`
**Auth**: Required
**Returns**: `{ url: string }`

---

## Security Features

### Row-Level Security (RLS)
- All tables have RLS enabled
- Users can only access their own data
- Service role bypasses RLS for Edge Functions

### Request Signing (HMAC)
- Sensitive operations require HMAC signature
- Prevents replay attacks (5-minute timestamp window)
- Prevents patched client abuse

### Device Tracking
- Max 3 active devices per account
- Concurrent usage detection (account sharing)
- Geolocation anomaly detection

### API Key Protection
- Paid users never receive Groq API key
- All requests proxied through Edge Functions
- Keys stored encrypted in environment (not database)

### Suspicious Activity Monitoring
- Failed auth attempts
- Quota exceeded attempts
- Invalid signatures
- Device limit exceeded
- Concurrent usage patterns

---

## Local Development

Run Supabase locally:

```bash
# Start local Supabase (Docker required)
supabase start

# Apply migrations
supabase db reset

# Serve functions locally
supabase functions serve --env-file supabase/.env

# Test function
curl http://localhost:54321/functions/v1/validate-subscription \
  -H "Authorization: Bearer eyJ..."
```

---

## Monitoring & Logs

### View Edge Function Logs

```bash
# Real-time logs
supabase functions logs validate-subscription --tail

# Last 100 lines
supabase functions logs validate-subscription -n 100
```

### View Database Logs

Supabase Dashboard > Database > Logs

### Monitor Stripe Events

Stripe Dashboard > Developers > Events

---

## Troubleshooting

### "Missing Supabase configuration" error
- Ensure all secrets are set: `supabase secrets list`
- Redeploy function after setting secrets

### Webhook signature verification failed
- Check `STRIPE_WEBHOOK_SECRET` matches Stripe Dashboard
- Ensure webhook endpoint URL is correct

### RLS policy blocking query
- Check user is authenticated
- Verify JWT token is valid
- Ensure service role key is used for Edge Functions

### Migration failed
- Check for syntax errors in SQL
- Ensure previous migrations succeeded
- Use `supabase db reset` to start fresh (⚠️ deletes all data)

---

## Production Checklist

Before going live:

- [ ] Switch Stripe to live mode (update keys and webhook)
- [ ] Update OAuth redirect URLs to production app scheme
- [ ] Enable email confirmations in Supabase Auth settings
- [ ] Set up monitoring alerts (Supabase + Stripe)
- [ ] Test full subscription flow (signup → upgrade → billing → cancel)
- [ ] Test offline grace period (24h validation, 7-day grace)
- [ ] Verify all Edge Function secrets are set
- [ ] Review RLS policies for security
- [ ] Enable rate limiting on Edge Functions
- [ ] Set up database backups (automatic in Supabase)

---

## Support

For issues or questions:
- Supabase Docs: https://supabase.com/docs
- Stripe Docs: https://stripe.com/docs
- Groq API Docs: https://console.groq.com/docs

