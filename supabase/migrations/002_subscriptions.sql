-- Migration 002: Subscriptions
-- Creates subscriptions table and auto-trigger for free tier
-- Dependencies: 001_profiles.sql

-- Create subscriptions table
CREATE TABLE IF NOT EXISTS public.subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES public.profiles(id) ON DELETE CASCADE,
    tier TEXT NOT NULL DEFAULT 'free',
    status TEXT NOT NULL DEFAULT 'active',
    stripe_customer_id TEXT,
    stripe_subscription_id TEXT,
    current_period_start TIMESTAMPTZ,
    current_period_end TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL,

    -- Constraints
    CONSTRAINT valid_tier CHECK (tier IN ('free', 'starter', 'pro', 'lifetime')),
    CONSTRAINT valid_status CHECK (status IN ('active', 'past_due', 'canceled', 'expired'))
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_subscriptions_user_id ON public.subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_stripe_customer ON public.subscriptions(stripe_customer_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_stripe_sub ON public.subscriptions(stripe_subscription_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status ON public.subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_subscriptions_tier ON public.subscriptions(tier);

-- Enable Row-Level Security
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can read their own subscription
CREATE POLICY "Users can read own subscription"
    ON public.subscriptions
    FOR SELECT
    USING (auth.uid() = user_id);

-- RLS Policy: Service role can do anything (for Edge Functions)
CREATE POLICY "Service role full access"
    ON public.subscriptions
    FOR ALL
    USING (auth.jwt()->>'role' = 'service_role');

-- Function: Auto-create free subscription on profile creation
CREATE OR REPLACE FUNCTION public.handle_new_subscription()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.subscriptions (user_id, tier, status)
    VALUES (NEW.id, 'free', 'active');
    RETURN NEW;
END;
$$;

-- Trigger: Call handle_new_subscription() after profile insert
DROP TRIGGER IF EXISTS on_profile_created ON public.profiles;
CREATE TRIGGER on_profile_created
    AFTER INSERT ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_subscription();

-- Trigger: Auto-update updated_at on subscription changes
DROP TRIGGER IF EXISTS on_subscription_updated ON public.subscriptions;
CREATE TRIGGER on_subscription_updated
    BEFORE UPDATE ON public.subscriptions
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_updated_at();

-- Grant permissions
GRANT SELECT ON public.subscriptions TO authenticated;
GRANT ALL ON public.subscriptions TO service_role;

COMMENT ON TABLE public.subscriptions IS 'User subscription status and Stripe billing information';
COMMENT ON COLUMN public.subscriptions.tier IS 'Subscription tier: free, starter, pro, lifetime';
COMMENT ON COLUMN public.subscriptions.status IS 'Subscription status: active, past_due, canceled, expired';
COMMENT ON COLUMN public.subscriptions.stripe_customer_id IS 'Stripe customer ID for billing';
COMMENT ON COLUMN public.subscriptions.stripe_subscription_id IS 'Stripe subscription ID (null for free/lifetime)';
COMMENT ON COLUMN public.subscriptions.current_period_start IS 'Billing period start (null for free/lifetime)';
COMMENT ON COLUMN public.subscriptions.current_period_end IS 'Billing period end (null for free/lifetime)';
