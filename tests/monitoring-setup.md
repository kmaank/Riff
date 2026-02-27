# Monitoring and Logging Setup for Riff

This guide will help you set up comprehensive monitoring for your Riff subscription backend.

## 📊 1. Supabase Edge Function Logs

### View Real-time Logs

**Dashboard**: https://supabase.com/dashboard/project/yrsviodciuepunofxoja/logs/edge-functions

### Key Metrics to Monitor

- **Request Count**: Total number of function invocations
- **Error Rate**: Percentage of failed requests
- **Response Time**: Average function execution time
- **Memory Usage**: Function memory consumption

### Filter by Function

```sql
-- In Supabase logs, filter by function name
metadata.function_name = "validate-subscription"
metadata.function_name = "stripe-webhook"
metadata.function_name = "proxy-transcribe"
```

### Common Error Patterns to Watch

```
❌ "Unauthorized" - Authentication issues
❌ "Invalid API key" - Missing environment variables
❌ "Rate limit exceeded" - Quota issues
❌ "Webhook signature verification failed" - Stripe webhook issues
```

---

## 🔍 2. Database Monitoring

### Usage Tracking Query

Monitor user quotas and usage:

```sql
-- Check users approaching quota limits
SELECT
    p.id,
    p.email,
    p.subscription_tier,
    p.quota_limit,
    p.quota_used,
    ROUND((p.quota_used::NUMERIC / NULLIF(p.quota_limit, 0)) * 100, 2) as quota_percentage
FROM profiles p
WHERE p.quota_used > (p.quota_limit * 0.8)  -- 80% used
ORDER BY quota_percentage DESC;
```

### Suspicious Activity Monitoring

```sql
-- Check recent suspicious activities
SELECT
    sa.id,
    sa.user_id,
    sa.activity_type,
    sa.details,
    sa.created_at,
    p.email
FROM suspicious_activities sa
JOIN auth.users u ON sa.user_id = u.id
JOIN profiles p ON p.id = u.id
ORDER BY sa.created_at DESC
LIMIT 100;
```

### Active Subscriptions

```sql
-- Monitor active paid subscriptions
SELECT
    p.id,
    p.email,
    p.subscription_tier,
    p.subscription_status,
    p.stripe_customer_id,
    p.subscription_end_date
FROM profiles p
WHERE p.subscription_tier != 'free'
ORDER BY p.subscription_end_date ASC;
```

### Daily Usage Summary

```sql
-- Daily API usage summary
SELECT
    DATE(created_at) as date,
    COUNT(*) as total_requests,
    COUNT(DISTINCT user_id) as unique_users,
    AVG(duration_seconds) as avg_duration,
    SUM(CASE WHEN endpoint = 'transcribe' THEN 1 ELSE 0 END) as transcribe_count,
    SUM(CASE WHEN endpoint = 'refine' THEN 1 ELSE 0 END) as refine_count
FROM usage_logs
WHERE created_at > NOW() - INTERVAL '30 days'
GROUP BY DATE(created_at)
ORDER BY date DESC;
```

---

## 🚨 3. Stripe Dashboard Monitoring

### Important Stripe Metrics

**Dashboard**: https://dashboard.stripe.com

Monitor:
- **Failed Payments**: Check for payment failures
- **Churned Subscriptions**: Track cancellations
- **MRR (Monthly Recurring Revenue)**: Overall revenue
- **New Subscriptions**: Growth tracking

### Webhook Monitoring

**Webhooks Dashboard**: https://dashboard.stripe.com/webhooks

Check:
- **Delivery Status**: Ensure webhooks are being received
- **Failed Events**: Investigate any failures
- **Response Times**: Monitor Edge Function performance

---

## 📈 4. Create Monitoring Dashboard

### Option A: Supabase Dashboard Queries

Save these queries in Supabase SQL Editor:

#### 1. Daily Active Users (DAU)

```sql
-- Save as "Daily Active Users"
SELECT
    DATE(created_at) as date,
    COUNT(DISTINCT user_id) as active_users
FROM usage_logs
WHERE created_at > NOW() - INTERVAL '30 days'
GROUP BY DATE(created_at)
ORDER BY date DESC;
```

#### 2. Quota Usage Distribution

```sql
-- Save as "Quota Usage Distribution"
SELECT
    subscription_tier,
    COUNT(*) as user_count,
    AVG(quota_used) as avg_used,
    AVG(quota_limit) as avg_limit,
    SUM(CASE WHEN quota_used >= quota_limit THEN 1 ELSE 0 END) as users_at_limit
FROM profiles
GROUP BY subscription_tier;
```

#### 3. Recent Errors

```sql
-- Save as "Recent Errors"
SELECT
    created_at,
    user_id,
    activity_type,
    details
FROM suspicious_activities
WHERE created_at > NOW() - INTERVAL '24 hours'
ORDER BY created_at DESC
LIMIT 50;
```

### Option B: External Monitoring (Advanced)

For production, consider:

1. **Sentry** - Error tracking
   - Sign up: https://sentry.io
   - Add to Edge Functions for error reporting

2. **LogDNA / Better Stack** - Log aggregation
   - Centralized logging
   - Alerting on errors

3. **Grafana + Prometheus** - Custom dashboards
   - Advanced metrics
   - Custom alerts

---

## 🔔 5. Set Up Alerts

### Supabase Alerts (if available in your plan)

Go to: https://supabase.com/dashboard/project/yrsviodciuepunofxoja/settings/alerts

Set up alerts for:
- High error rate (> 5%)
- Function timeout (> 10s)
- Database connection issues

### Email Notifications for Critical Events

Create a database trigger to send emails on critical events:

```sql
-- Example: Alert on suspicious activity
CREATE OR REPLACE FUNCTION notify_admin_suspicious_activity()
RETURNS TRIGGER AS $$
BEGIN
    -- You would integrate with an email service here
    -- For now, just log it
    RAISE NOTICE 'Suspicious activity detected: % for user %',
        NEW.activity_type, NEW.user_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER suspicious_activity_alert
AFTER INSERT ON suspicious_activities
FOR EACH ROW
EXECUTE FUNCTION notify_admin_suspicious_activity();
```

---

## 📝 6. Logging Best Practices

### Add Structured Logging to Edge Functions

In your Edge Functions, use structured logging:

```typescript
// Good logging
console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    function: 'validate-subscription',
    user_id: userId,
    tier: subscriptionTier,
    status: 'success',
    duration_ms: Date.now() - startTime
}));

// Error logging
console.error(JSON.stringify({
    timestamp: new Date().toISOString(),
    function: 'validate-subscription',
    user_id: userId,
    error: error.message,
    stack: error.stack
}));
```

### What to Log

✅ **Do Log**:
- Request start/end with timing
- Authentication success/failure
- Quota checks
- External API calls
- Errors with full context

❌ **Don't Log**:
- User passwords
- API keys or secrets
- Full credit card numbers
- Personal sensitive data

---

## 🎯 7. Key Performance Indicators (KPIs)

Track these metrics weekly:

| Metric | Target | Alert If |
|--------|--------|----------|
| API Error Rate | < 1% | > 5% |
| Average Response Time | < 500ms | > 2s |
| Webhook Delivery Rate | > 99% | < 95% |
| Failed Payments | < 2% | > 10% |
| Active Subscriptions | Growing | Declining |
| Quota Limit Hits | < 5% of users | > 20% |

---

## 🛠️ 8. Quick Monitoring Commands

### Check Latest Edge Function Logs

```bash
# Using Supabase CLI (if installed)
supabase functions logs validate-subscription
supabase functions logs stripe-webhook
```

### Check Database Health

```bash
# Connect to database
psql "postgresql://postgres:[YOUR-PASSWORD]@db.yrsviodciuepunofxoja.supabase.co:5432/postgres"

# Run health check queries
\x
SELECT * FROM pg_stat_activity WHERE state = 'active';
```

### Monitor Webhook Deliveries

```bash
# Using Stripe CLI
stripe webhook-endpoints list
stripe events list --limit 10
```

---

## 📋 Daily Monitoring Checklist

- [ ] Check Supabase Edge Function logs for errors
- [ ] Review Stripe webhook delivery status
- [ ] Check for users at quota limits
- [ ] Review suspicious activities log
- [ ] Monitor failed payments
- [ ] Check database performance

---

## 🔗 Quick Links

- **Supabase Dashboard**: https://supabase.com/dashboard/project/yrsviodciuepunofxoja
- **Edge Function Logs**: https://supabase.com/dashboard/project/yrsviodciuepunofxoja/logs/edge-functions
- **Database Logs**: https://supabase.com/dashboard/project/yrsviodciuepunofxoja/logs/database
- **Stripe Dashboard**: https://dashboard.stripe.com
- **Stripe Webhooks**: https://dashboard.stripe.com/webhooks

---

**Next Steps**: Run the monitoring queries and bookmark the important dashboards! 🚀
