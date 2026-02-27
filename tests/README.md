# Riff Testing Suite

Comprehensive testing tools for your Riff subscription backend.

## 📋 Quick Start

All test scripts are executable and ready to run:

```bash
# 1. Run health check first
./health-check.sh

# 2. Test individual Edge Functions
./edge-functions-test.sh

# 3. Test complete subscription flow
./subscription-flow-test.sh

# 4. Learn about webhook testing
./webhook-test.sh
```

---

## 🧪 Test Scripts

### 1. `health-check.sh` - System Health Check

**What it does:**
- Checks Supabase API connectivity
- Tests all 10 Edge Functions
- Verifies authentication service
- Tests database connection
- Provides overall health status

**When to run:**
- Daily as part of monitoring
- After deploying changes
- When troubleshooting issues
- Before production releases

**Example output:**
```
═══════════════════════════════════════════════════
  Riff Backend Health Check
═══════════════════════════════════════════════════

[1] Supabase API
  ✓ Supabase API responding

[2] Edge Functions
  validate-subscription... ✓ OK (401)
  log-usage... ✓ OK (401)
  register-device... ✓ OK (401)
  ...

✓ Healthy: 14
! Warnings: 0
✗ Errors: 0

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✓ ALL SYSTEMS OPERATIONAL ✓
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

### 2. `edge-functions-test.sh` - Edge Function Tests

**What it does:**
- Tests all 10 Edge Functions individually
- Verifies error handling (unauthenticated requests)
- Tests endpoint availability
- Validates response formats

**What it tests:**
- ✓ Authentication endpoints
- ✓ Device registration
- ✓ Usage logging
- ✓ History sync
- ✓ Stripe checkout/portal
- ✓ Webhook handling
- ✓ Transcribe/refine proxies

**Expected behavior:**
- Most endpoints return 401 (Unauthorized) without auth - this is correct!
- Webhook endpoint returns 400 (Bad Request) without signature - this is correct!

**Run it:**
```bash
./edge-functions-test.sh
```

---

### 3. `subscription-flow-test.sh` - End-to-End Flow Test

**What it does:**
- Creates a real test user
- Tests complete subscription workflow
- Validates all user-facing operations
- Provides test credentials for manual testing

**The complete flow:**
1. ✓ User signup
2. ✓ Subscription validation (free tier)
3. ✓ Device registration
4. ✓ API key retrieval
5. ✓ Usage logging
6. ✓ History sync
7. ~ Checkout session creation

**Run it:**
```bash
./subscription-flow-test.sh
```

**Output includes:**
- Test user email and password
- User ID for database queries
- Access token for API testing
- Response from each step

**⚠️ Note:** Creates a real user in your database each time!

---

### 4. `webhook-test.sh` - Webhook Testing Guide

**What it does:**
- Explains webhook testing methods
- Tests webhook endpoint availability
- Provides Stripe CLI commands
- Shows how to use Stripe Dashboard

**Three testing methods:**

#### Method 1: Stripe CLI (Recommended)
```bash
# Install Stripe CLI
brew install stripe/stripe-cli/stripe  # Mac
# or download from https://stripe.com/docs/stripe-cli

# Login
stripe login

# Forward webhooks
stripe listen --forward-to https://yrsviodciuepunofxoja.supabase.co/functions/v1/stripe-webhook

# Trigger events (in another terminal)
stripe trigger customer.subscription.created
stripe trigger invoice.payment_succeeded
```

#### Method 2: Stripe Dashboard
1. Go to https://dashboard.stripe.com/webhooks
2. Click your endpoint
3. Click "Send test webhook"
4. Select event type and send

#### Method 3: Manual Testing
```bash
./webhook-test.sh  # Tests endpoint availability
```

---

## 📊 Monitoring

### View Logs in Real-Time

**Supabase Dashboard:**
```
https://supabase.com/dashboard/project/yrsviodciuepunofxoja/logs/edge-functions
```

**Filter by function:**
- Click on function name to see only its logs
- Filter by date/time range
- Search for errors or specific messages

### Monitor Database

**Run SQL queries:**
```
https://supabase.com/dashboard/project/yrsviodciuepunofxoja/editor
```

**Useful queries:**
```sql
-- See recent usage
SELECT * FROM usage_logs
ORDER BY created_at DESC
LIMIT 100;

-- Check quota usage
SELECT
    p.email,
    p.subscription_tier,
    p.quota_used,
    p.quota_limit,
    ROUND((p.quota_used::NUMERIC / NULLIF(p.quota_limit, 0)) * 100, 2) as quota_percent
FROM profiles p
ORDER BY quota_percent DESC;

-- Recent suspicious activities
SELECT * FROM suspicious_activities
ORDER BY created_at DESC
LIMIT 50;
```

---

## 🔧 Troubleshooting

### All tests fail with "connection refused"

**Problem:** Can't reach Supabase
**Solution:**
- Check internet connection
- Verify Supabase project is active
- Check if URL is correct

### Tests return 401 (Unauthorized)

**Problem:** Missing or invalid auth token
**Solution:**
- This is expected for `edge-functions-test.sh`!
- For authenticated tests, run `subscription-flow-test.sh`

### Webhook tests fail with 400

**Problem:** Missing Stripe signature
**Solution:**
- This is expected for basic tests!
- Use Stripe CLI or Dashboard for real webhook testing

### "STRIPE_SECRET_KEY not set"

**Problem:** Stripe env var not configured
**Solution:**
```bash
# Set in Supabase Dashboard:
# https://supabase.com/dashboard/project/yrsviodciuepunofxoja/settings/functions

# Add secret:
# Name: STRIPE_SECRET_KEY
# Value: sk_test_... or sk_live_...
```

---

## 📝 Test Results Interpretation

### Health Check Results

| Status | Meaning | Action |
|--------|---------|--------|
| ✓ OK | Function responding correctly | None needed |
| ! WARNING | Unexpected response | Check logs |
| ✗ ERROR | Function not responding | Investigate immediately |

### Expected Status Codes

| Endpoint | No Auth | With Auth |
|----------|---------|-----------|
| validate-subscription | 401 | 200 |
| log-usage | 401 | 200 |
| register-device | 401 | 200 |
| sync-history | 401 | 200 |
| get-api-key | 401 | 200 |
| proxy-transcribe | 401 | 200 |
| proxy-refine | 401 | 200 |
| create-checkout | 401 | 200 |
| create-portal | 401 | 200 |
| stripe-webhook | 400 | N/A |

---

## 🎯 Testing Checklist

**Before deploying to production:**

- [ ] All health checks pass
- [ ] Edge function tests complete successfully
- [ ] Subscription flow works end-to-end
- [ ] Webhooks deliver successfully
- [ ] Database queries return expected results
- [ ] Stripe integration tested
- [ ] Error handling works correctly
- [ ] Logs are clean (no unexpected errors)
- [ ] Quotas enforce correctly
- [ ] RLS policies prevent unauthorized access

---

## 🔗 Quick Links

- **Supabase Dashboard**: https://supabase.com/dashboard/project/yrsviodciuepunofxoja
- **Edge Function Logs**: https://supabase.com/dashboard/project/yrsviodciuepunofxoja/logs/edge-functions
- **Database Editor**: https://supabase.com/dashboard/project/yrsviodciuepunofxoja/editor
- **Stripe Dashboard**: https://dashboard.stripe.com
- **Stripe Webhooks**: https://dashboard.stripe.com/webhooks

---

## 📚 Additional Documentation

- **API Integration Guide**: `/docs/API_INTEGRATION.md` - Complete API reference for Mac/Android
- **Monitoring Guide**: `/tests/monitoring-setup.md` - Comprehensive monitoring setup

---

## 💡 Tips

1. **Run health checks daily** - Catch issues early
2. **Keep test users** - Use them for debugging
3. **Monitor webhook deliveries** - Check Stripe dashboard regularly
4. **Review logs weekly** - Look for patterns or errors
5. **Test before deploying** - Always run the full test suite

---

**Need help?** All scripts include detailed output and error messages to help you troubleshoot! 🚀
