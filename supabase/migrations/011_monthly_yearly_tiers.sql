-- Migration 011: Free / monthly / yearly product plans
-- Extends subscription tiers without dropping existing starter/pro/lifetime rows

ALTER TABLE public.subscriptions
    DROP CONSTRAINT IF EXISTS valid_tier;

ALTER TABLE public.subscriptions
    ADD CONSTRAINT valid_tier CHECK (
        tier IN ('free', 'monthly', 'yearly', 'starter', 'pro', 'lifetime')
    );

COMMENT ON COLUMN public.subscriptions.tier IS 'free, monthly, yearly (plus legacy starter/pro/lifetime)';
