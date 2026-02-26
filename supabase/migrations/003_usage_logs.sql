-- Migration 003: Usage Logs and Quota Tracking
-- Creates usage_logs table and monthly_usage view for quota enforcement
-- Dependencies: 001_profiles.sql

-- Create usage_logs table (append-only)
CREATE TABLE IF NOT EXISTS public.usage_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    word_count INT NOT NULL DEFAULT 0,
    recording_seconds FLOAT NOT NULL DEFAULT 0,
    style TEXT,
    script_mode TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,

    -- Constraints
    CONSTRAINT positive_word_count CHECK (word_count >= 0),
    CONSTRAINT positive_recording_seconds CHECK (recording_seconds >= 0)
);

-- Add indexes for performance (critical for quota queries)
CREATE INDEX IF NOT EXISTS idx_usage_logs_user_id ON public.usage_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_usage_logs_created_at ON public.usage_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_logs_user_date ON public.usage_logs(user_id, created_at DESC);

-- Enable Row-Level Security
ALTER TABLE public.usage_logs ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can read their own usage logs
CREATE POLICY "Users can read own usage logs"
    ON public.usage_logs
    FOR SELECT
    USING (auth.uid() = user_id);

-- RLS Policy: Service role can insert and read (for Edge Functions)
CREATE POLICY "Service role can insert usage"
    ON public.usage_logs
    FOR INSERT
    WITH CHECK (auth.jwt()->>'role' = 'service_role');

CREATE POLICY "Service role can read all usage"
    ON public.usage_logs
    FOR SELECT
    USING (auth.jwt()->>'role' = 'service_role');

-- Create monthly_usage view for quota enforcement
CREATE OR REPLACE VIEW public.monthly_usage AS
SELECT
    user_id,
    COUNT(*) as riffs_used,
    COALESCE(SUM(word_count), 0)::INT as words_used,
    COALESCE(SUM(recording_seconds), 0)::FLOAT as seconds_used,
    date_trunc('month', now()) as period_start
FROM public.usage_logs
WHERE created_at >= date_trunc('month', now())
GROUP BY user_id;

-- Grant permissions on view
GRANT SELECT ON public.monthly_usage TO authenticated, service_role;

-- Grant permissions on table
GRANT SELECT ON public.usage_logs TO authenticated;
GRANT INSERT, SELECT ON public.usage_logs TO service_role;

-- Function: Get user's current month usage
CREATE OR REPLACE FUNCTION public.get_monthly_usage(p_user_id UUID)
RETURNS TABLE (
    riffs_used INT,
    words_used INT,
    seconds_used FLOAT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        COALESCE(mu.riffs_used, 0)::INT,
        COALESCE(mu.words_used, 0)::INT,
        COALESCE(mu.seconds_used, 0)::FLOAT
    FROM public.monthly_usage mu
    WHERE mu.user_id = p_user_id;

    -- If no usage found, return zeros
    IF NOT FOUND THEN
        RETURN QUERY SELECT 0, 0, 0.0;
    END IF;
END;
$$;

-- Function: Detect concurrent usage (multiple riffs within short time window)
CREATE OR REPLACE FUNCTION public.detect_concurrent_usage(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    recent_count INT;
BEGIN
    -- Check for multiple riffs in last 10 seconds
    SELECT COUNT(*) INTO recent_count
    FROM public.usage_logs
    WHERE user_id = p_user_id
      AND created_at >= now() - INTERVAL '10 seconds';

    RETURN recent_count >= 2;
END;
$$;

COMMENT ON TABLE public.usage_logs IS 'Append-only log of all riff usage for quota tracking and analytics';
COMMENT ON VIEW public.monthly_usage IS 'Aggregated usage per user for current month (for quota enforcement)';
COMMENT ON FUNCTION public.get_monthly_usage IS 'Returns current month usage stats for a user';
COMMENT ON FUNCTION public.detect_concurrent_usage IS 'Detects potential account sharing (multiple riffs within 10s)';
