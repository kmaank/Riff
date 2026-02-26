# Riff Subscription Backend - Deployment Guide

This guide covers deploying the complete Riff subscription system with Supabase and Stripe.

---

## Prerequisites

- Supabase account ([supabase.com](https://supabase.com))
- Stripe account ([stripe.com](https://stripe.com))
- Supabase CLI (`brew install supabase/tap/supabase`)
- Python 3.10+
- Xcode Command Line Tools (for Swift compilation)

---

## Part 1: Supabase Project Setup

### 1.1 Create Supabase Project

1. Go to [supabase.com/dashboard](https://supabase.com/dashboard)
2. Click "New Project"
3. Choose organization and project name (e.g., "riff-production")
4. Choose region closest to your users
5. Generate a strong database password
6. Wait for project to provision (~2 minutes)

### 1.2 Get Supabase Credentials

Navigate to **Project Settings > API**:

- `SUPABASE_URL`: e.g., `https://your-project.supabase.co`
- `SUPABASE_ANON_KEY`: Public anon key (safe to embed in client apps)
- `SUPABASE_SERVICE_ROLE_KEY`: Secret key (server-side only, keep secure!)

Save these credentials — you'll need them shortly.

### 1.3 Link Supabase CLI to Project

```bash
cd ~/Riff
supabase link --project-ref your-project-ref
```

Find your project ref in the Supabase dashboard URL: `https://supabase.com/dashboard/project/your-project-ref`

### 1.4 Deploy Database Schema

```bash
cd ~/Riff
supabase db push
```

This runs `supabase/migrations/001_schema.sql` and creates:
- ✅ Tables: `profiles`, `subscriptions`, `usage_logs`, `api_keys`
- ✅ View: `monthly_usage`
- ✅ Triggers: Auto-create profile + subscription on signup
- ✅ RLS policies: Row-level security
- ✅ Helper functions: `get_user_subscription`, `check_quota`

Verify in Supabase Dashboard → **Database** → **Tables**.

---

## Part 2: Supabase Authentication Setup

### 2.1 Enable Auth Providers

Navigate to **Authentication > Providers**:

**Email (Built-in)**:
- Enable "Email provider"
- ✅ Disable "Confirm email" (for faster dev/testing)
- ✅ Disable "Secure email change" (optional)

**Google OAuth**:
1. Create OAuth credentials at [console.cloud.google.com](https://console.cloud.google.com/apis/credentials)
2. Authorized redirect URI: `https://your-project.supabase.co/auth/v1/callback`
3. Copy Client ID and Client Secret
4. Paste into Supabase → Google provider settings
5. Enable Google provider

**GitHub OAuth**:
1. Create OAuth app at [github.com/settings/developers](https://github.com/settings/developers)
2. Authorization callback URL: `https://your-project.supabase.co/auth/v1/callback`
3. Copy Client ID and Client Secret
4. Paste into Supabase → GitHub provider settings
5. Enable GitHub provider

**Apple OAuth** (optional, requires Apple Developer account):
- Follow Supabase docs: [https://supabase.com/docs/guides/auth/social-login/auth-apple](https://supabase.com/docs/guides/auth/social-login/auth-apple)

### 2.2 Configure Redirect URLs

Navigate to **Authentication > URL Configuration**:

Add custom redirect URLs:
```
riff://oauth/callback
http://localhost:3000 (for local testing)
```

---

## Part 3: Supabase Edge Functions

### 3.1 Deploy Edge Functions

Deploy all functions at once:

```bash
cd ~/Riff
supabase functions deploy validate-subscription
supabase functions deploy log-usage
supabase functions deploy get-api-key
supabase functions deploy create-checkout
supabase functions deploy stripe-webhook
supabase functions deploy create-portal
```

### 3.2 Set Edge Function Secrets

```bash
# Supabase credentials (for service role access)
supabase secrets set SUPABASE_SERVICE_ROLE_KEY="your-service-role-key"

# Stripe credentials (get from Part 4)
supabase secrets set STRIPE_SECRET_KEY="sk_live_..."
supabase secrets set STRIPE_WEBHOOK_SECRET="whsec_..."

# Stripe product price IDs (get from Part 4)
supabase secrets set STRIPE_STARTER_PRICE_ID="price_..."
supabase secrets set STRIPE_PRO_PRICE_ID="price_..."
supabase secrets set STRIPE_LIFETIME_PRICE_ID="price_..."

# Managed Groq API key (for paid tier users)
supabase secrets set MANAGED_GROQ_API_KEY="gsk_..."

# App URL for OAuth redirects
supabase secrets set APP_URL="riff://"
```

Verify secrets:
```bash
supabase secrets list
```

---

## Part 4: Stripe Integration

### 4.1 Create Stripe Account

1. Sign up at [stripe.com](https://stripe.com)
2. Activate test mode (toggle in top-right)
3. Complete account verification for live mode later

### 4.2 Create Products & Prices

Navigate to **Products** → **Add Product**:

**Starter Plan**:
- Name: "Riff Starter"
- Description: "500 riffs/mo, 2 hours recording, all styles"
- Price: $9.99 USD / month (recurring)
- Copy **Price ID**: `price_starter123...`

**Pro Plan**:
- Name: "Riff Pro"
- Description: "Unlimited riffs, unlimited recording, custom prompts, priority support"
- Price: $19.99 USD / month (recurring)
- Copy **Price ID**: `price_pro456...`

**Lifetime Plan**:
- Name: "Riff Lifetime"
- Description: "One-time payment, Pro features forever"
- Price: $149 USD (one-time)
- Copy **Price ID**: `price_lifetime789...`

Save all three Price IDs — you'll need them for secrets.

### 4.3 Configure Webhooks

Navigate to **Developers > Webhooks** → **Add endpoint**:

- **Endpoint URL**: `https://your-project.supabase.co/functions/v1/stripe-webhook`
- **Events to send**:
  - `checkout.session.completed`
  - `customer.subscription.updated`
  - `customer.subscription.deleted`
  - `invoice.payment_failed`

After creating, copy the **Signing secret** (`whsec_...`) — you'll need it for secrets.

### 4.4 Configure Customer Portal

Navigate to **Settings > Customer Portal**:

- Enable customer portal
- Allow customers to:
  - ✅ Update payment method
  - ✅ View invoices
  - ✅ Cancel subscription
- Customize branding (logo, colors) to match Riff

Save changes.

### 4.5 Update Edge Function Secrets

```bash
supabase secrets set STRIPE_SECRET_KEY="sk_test_..." # or sk_live_ for production
supabase secrets set STRIPE_WEBHOOK_SECRET="whsec_..."
supabase secrets set STRIPE_STARTER_PRICE_ID="price_starter..."
supabase secrets set STRIPE_PRO_PRICE_ID="price_pro..."
supabase secrets set STRIPE_LIFETIME_PRICE_ID="price_lifetime..."
```

---

## Part 5: Client Configuration (Swift & Python)

### 5.1 Update Swift App Configuration

Edit `config_ui/RiffControlCenter/SwiftAuthManager.swift`:

```swift
// Replace with your Supabase credentials
let url = "https://your-project.supabase.co"
let key = "your-anon-key-here"
```

Or better: read from config.json (already implemented).

### 5.2 Update Python Configuration

Edit `utils/config_manager.py` → `DEFAULT_CONFIG`:

```python
"auth": {
    "supabase_url": "https://your-project.supabase.co",
    "supabase_anon_key": "your-anon-key-here"
}
```

Or: Set via config file after first run:
```bash
# Edit ~/Library/Application Support/Riff/config.json
{
  "auth": {
    "supabase_url": "https://your-project.supabase.co",
    "supabase_anon_key": "eyJ..."
  }
}
```

---

## Part 6: Build & Test

### 6.1 Build Swift UI

```bash
cd ~/Riff/config_ui
./build_ui.sh
```

This creates `build/RiffControlCenter.app` with OAuth URL scheme configured.

### 6.2 Install Python Dependencies

```bash
cd ~/Riff
pip install -r requirements.txt
```

### 6.3 Run Riff

```bash
cd ~/Riff
python main.py
```

**Expected Flow:**

1. Riff Control Center opens → shows **LoginView** (auth gate)
2. Sign up with email + password or OAuth
3. Profile + free subscription auto-created in database
4. Onboarding: Select tier → Enter BYOK API key (free) or skip (paid)
5. Main app unlocked

### 6.4 Test Subscription Flow

**Free Tier Test:**
1. Sign up with new account
2. Complete onboarding (enter Groq API key)
3. Create 5 riffs → check usage in **Account** tab
4. Verify only "clean" and "casual" styles are unlocked

**Upgrade Test:**
1. Click "Upgrade" in Account tab
2. Select "Starter" plan
3. Redirected to Stripe Checkout in browser
4. Use test card: `4242 4242 4242 4242`, any future expiry, any CVC
5. Complete payment
6. Webhook fires → subscription updated to "starter"
7. Return to app → verify tier badge shows "Starter"
8. Verify all 4 styles now unlocked

**Billing Portal Test:**
1. Click "Manage Billing" in Account tab
2. Opens Stripe Customer Portal
3. Update payment method → cancel subscription → view invoices

### 6.5 Test Quota Enforcement

**Free Tier Limit Test:**
1. Create 100 riffs
2. Attempt 101st riff → should show notification: "Monthly riff limit reached (100)"

**Starter Tier Time Limit Test:**
1. Upgrade to Starter tier
2. Create riffs totaling >2 hours of recording
3. Attempt next riff → should show: "Monthly recording time limit reached"

---

## Part 7: Production Checklist

Before launching to users:

### Security
- [ ] Switch Stripe to **Live Mode** (get live API keys)
- [ ] Update `STRIPE_SECRET_KEY` to live key
- [ ] Regenerate webhook secret for live mode
- [ ] Enable **Row Level Security** in Supabase (already done in schema)
- [ ] Enable **Confirm email** in Supabase Auth settings
- [ ] Implement AES-256-GCM encryption for `api_keys.encrypted_key`
- [ ] Move managed Groq key to secure key pool (not single env var)

### Monitoring
- [ ] Set up Supabase monitoring (Dashboard → Monitoring)
- [ ] Configure Stripe email notifications (payment failures, disputes)
- [ ] Set up error logging (Sentry, LogRocket, etc.)
- [ ] Monitor Edge Function logs: `supabase functions logs`

### Performance
- [ ] Test with 1000+ users (load testing)
- [ ] Optimize database queries (add indexes if needed)
- [ ] Set up CDN for assets (if applicable)
- [ ] Enable Supabase connection pooling (auto-enabled)

### Legal & Compliance
- [ ] Add Terms of Service
- [ ] Add Privacy Policy
- [ ] Add GDPR data deletion flow
- [ ] Add refund policy
- [ ] Register with Apple Developer (if distributing via App Store)

---

## Part 8: Database Backups

Supabase automatically backs up your database daily. To manually backup:

```bash
# Export database schema + data
supabase db dump -f backup.sql

# Restore from backup
supabase db reset
psql -h db.your-project.supabase.co -U postgres -f backup.sql
```

---

## Part 9: Monitoring & Debugging

### Edge Function Logs

```bash
# Real-time logs
supabase functions logs validate-subscription --follow

# View recent logs
supabase functions logs stripe-webhook --limit 100
```

### Database Logs

Navigate to Supabase Dashboard → **Logs** → **Postgres Logs**

### Stripe Webhooks

Navigate to Stripe Dashboard → **Developers > Webhooks** → Click endpoint → **View events**

### Test Webhook Locally

```bash
# Forward Stripe webhooks to localhost
stripe listen --forward-to https://your-project.supabase.co/functions/v1/stripe-webhook

# Trigger test events
stripe trigger checkout.session.completed
```

---

## Part 10: Troubleshooting

### Issue: "Unauthorized" errors in Swift

**Fix**: Check access token in Keychain:
```bash
security find-generic-password -a "riff" -s "supabase_access_token" -w
```

If expired, refresh token or re-login.

### Issue: Stripe webhook not firing

**Fix**:
1. Check webhook URL is correct
2. Verify signing secret matches
3. Check Stripe Dashboard → Webhooks → View attempts

### Issue: "Subscription not found" error

**Fix**: Check database:
```sql
SELECT * FROM subscriptions WHERE user_id = 'user-uuid';
```

If missing, trigger signup flow should auto-create.

### Issue: OAuth callback not working

**Fix**:
1. Verify `riff://` URL scheme in `Info.plist`
2. Check redirect URL in Supabase Auth settings
3. Rebuild app: `cd config_ui && ./build_ui.sh`

---

## Support

For issues or questions:

- Supabase Docs: [https://supabase.com/docs](https://supabase.com/docs)
- Stripe Docs: [https://stripe.com/docs](https://stripe.com/docs)
- Riff GitHub Issues: [https://github.com/your-org/riff/issues](https://github.com/your-org/riff/issues)

---

**🎉 Congratulations! Your Riff subscription backend is now live!**
