-- Riff Subscription Backend - Database Schema
-- Phase 1: Complete database setup with all tables, views, triggers, and RLS policies

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- TABLE: profiles
-- Auto-created user profiles (one-to-one with auth.users)
-- ============================================================================

CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    display_name TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Index for faster email lookups
CREATE INDEX idx_profiles_email ON profiles(email);

-- ============================================================================
-- TABLE: subscriptions
-- User subscription information (one per user)
-- ============================================================================

CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,
    tier TEXT NOT NULL DEFAULT 'free',              -- free, starter, pro, lifetime
    status TEXT NOT NULL DEFAULT 'active',           -- active, past_due, canceled, expired
    stripe_customer_id TEXT,
    stripe_subscription_id TEXT,
    current_period_start TIMESTAMPTZ,
    current_period_end TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),

    -- Constraints
    CONSTRAINT valid_tier CHECK (tier IN ('free', 'starter', 'pro', 'lifetime')),
    CONSTRAINT valid_status CHECK (status IN ('active', 'past_due', 'canceled', 'expired'))
);

-- Indexes
CREATE INDEX idx_subscriptions_user_id ON subscriptions(user_id);
CREATE INDEX idx_subscriptions_stripe_customer_id ON subscriptions(stripe_customer_id);
CREATE INDEX idx_subscriptions_stripe_subscription_id ON subscriptions(stripe_subscription_id);

-- ============================================================================
-- TABLE: usage_logs
-- Append-only usage tracking (one row per riff)
-- ============================================================================

CREATE TABLE usage_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    word_count INT NOT NULL DEFAULT 0,
    recording_seconds FLOAT NOT NULL DEFAULT 0,
    style TEXT,
    script_mode TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes for fast monthly aggregation
CREATE INDEX idx_usage_logs_user_id ON usage_logs(user_id);
CREATE INDEX idx_usage_logs_created_at ON usage_logs(created_at);
CREATE INDEX idx_usage_logs_user_month ON usage_logs(user_id, created_at);

-- ============================================================================
-- VIEW: monthly_usage
-- Aggregated monthly usage for quota checks
-- ============================================================================

CREATE VIEW monthly_usage AS
SELECT
    user_id,
    COUNT(*) as riffs_used,
    COALESCE(SUM(word_count), 0) as words_used,
    COALESCE(SUM(recording_seconds), 0) as seconds_used,
    date_trunc('month', now()) as period_start
FROM usage_logs
WHERE created_at >= date_trunc('month', now())
GROUP BY user_id;

-- ============================================================================
-- TABLE: api_keys
-- Encrypted managed API keys for paid users
-- ============================================================================

CREATE TABLE api_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,
    encrypted_key TEXT NOT NULL,            -- AES-256-GCM encrypted Groq API key
    tier TEXT NOT NULL,                      -- Tier when key was provisioned
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    rotated_at TIMESTAMPTZ,

    CONSTRAINT valid_tier CHECK (tier IN ('starter', 'pro', 'lifetime'))
);

-- Index for fast lookups
CREATE INDEX idx_api_keys_user_id ON api_keys(user_id);

-- ============================================================================
-- TRIGGERS: Auto-create profile and subscription on user signup
-- ============================================================================

-- Function to create profile and subscription
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    -- Create profile
    INSERT INTO profiles (id, email, display_name)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1))
    );

    -- Create free tier subscription
    INSERT INTO subscriptions (user_id, tier, status)
    VALUES (NEW.id, 'free', 'active');

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger on auth.users insert
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION handle_new_user();

-- ============================================================================
-- TRIGGER: Update updated_at timestamps
-- ============================================================================

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to profiles
CREATE TRIGGER update_profiles_updated_at
    BEFORE UPDATE ON profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

-- Apply to subscriptions
CREATE TRIGGER update_subscriptions_updated_at
    BEFORE UPDATE ON subscriptions
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

-- ============================================================================
-- ROW LEVEL SECURITY (RLS)
-- Users can only access their own data
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE usage_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE api_keys ENABLE ROW LEVEL SECURITY;

-- Profiles: Users can read and update their own profile
CREATE POLICY "Users can view their own profile"
    ON profiles FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "Users can update their own profile"
    ON profiles FOR UPDATE
    USING (auth.uid() = id);

-- Subscriptions: Users can read their own subscription
CREATE POLICY "Users can view their own subscription"
    ON subscriptions FOR SELECT
    USING (auth.uid() = user_id);

-- Usage logs: Users can read and insert their own usage
CREATE POLICY "Users can view their own usage logs"
    ON usage_logs FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own usage logs"
    ON usage_logs FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- API keys: Users can read their own API key
CREATE POLICY "Users can view their own API key"
    ON api_keys FOR SELECT
    USING (auth.uid() = user_id);

-- ============================================================================
-- FUNCTIONS: Helper functions for Edge Functions
-- ============================================================================

-- Function to get user's current tier and status
CREATE OR REPLACE FUNCTION get_user_subscription(p_user_id UUID)
RETURNS TABLE (
    tier TEXT,
    status TEXT,
    current_period_end TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT s.tier, s.status, s.current_period_end
    FROM subscriptions s
    WHERE s.user_id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to check if user has exceeded quota
CREATE OR REPLACE FUNCTION check_quota(p_user_id UUID, p_tier TEXT)
RETURNS TABLE (
    can_riff BOOLEAN,
    reason TEXT,
    riffs_used INT,
    seconds_used FLOAT
) AS $$
DECLARE
    v_riffs_limit INT;
    v_seconds_limit INT;
    v_riffs_used INT;
    v_seconds_used FLOAT;
BEGIN
    -- Set limits based on tier
    CASE p_tier
        WHEN 'free' THEN
            v_riffs_limit := 100;
            v_seconds_limit := NULL;  -- Unlimited
        WHEN 'starter' THEN
            v_riffs_limit := 500;
            v_seconds_limit := 7200;  -- 2 hours
        WHEN 'pro', 'lifetime' THEN
            v_riffs_limit := NULL;  -- Unlimited
            v_seconds_limit := NULL;  -- Unlimited
    END CASE;

    -- Get current usage
    SELECT
        COALESCE(mu.riffs_used, 0),
        COALESCE(mu.seconds_used, 0)
    INTO v_riffs_used, v_seconds_used
    FROM monthly_usage mu
    WHERE mu.user_id = p_user_id;

    -- If no usage yet, set to 0
    IF v_riffs_used IS NULL THEN
        v_riffs_used := 0;
        v_seconds_used := 0;
    END IF;

    -- Check limits
    IF v_riffs_limit IS NOT NULL AND v_riffs_used >= v_riffs_limit THEN
        RETURN QUERY SELECT FALSE, 'Monthly riff limit reached', v_riffs_used, v_seconds_used;
    ELSIF v_seconds_limit IS NOT NULL AND v_seconds_used >= v_seconds_limit THEN
        RETURN QUERY SELECT FALSE, 'Monthly recording time limit reached', v_riffs_used, v_seconds_used;
    ELSE
        RETURN QUERY SELECT TRUE, 'OK', v_riffs_used, v_seconds_used;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- COMMENTS (Documentation)
-- ============================================================================

COMMENT ON TABLE profiles IS 'User profiles (one-to-one with auth.users)';
COMMENT ON TABLE subscriptions IS 'User subscription tiers and Stripe billing info';
COMMENT ON TABLE usage_logs IS 'Append-only usage tracking for quota enforcement';
COMMENT ON TABLE api_keys IS 'Encrypted managed Groq API keys for paid users';
COMMENT ON VIEW monthly_usage IS 'Aggregated monthly usage for current billing period';

-- ============================================================================
-- COMPLETE
-- ============================================================================

-- Migration complete
-- Run with: supabase db push
