-- Migration 006: Suspicious Activity Tracking
-- Creates table for abuse detection and security monitoring
-- Dependencies: 001_profiles.sql

-- Create suspicious_activity table
CREATE TABLE IF NOT EXISTS public.suspicious_activity (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    activity_type TEXT NOT NULL,
    severity TEXT NOT NULL DEFAULT 'low',
    description TEXT,
    metadata JSONB,
    ip_address TEXT,
    device_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,

    -- Constraints
    CONSTRAINT valid_activity_type CHECK (activity_type IN (
        'concurrent_usage',
        'device_limit_exceeded',
        'quota_exceeded',
        'invalid_signature',
        'geolocation_anomaly',
        'rapid_requests',
        'token_reuse',
        'failed_auth',
        'other'
    )),
    CONSTRAINT valid_severity CHECK (severity IN ('low', 'medium', 'high', 'critical'))
);

-- Add indexes for performance and security monitoring
CREATE INDEX IF NOT EXISTS idx_suspicious_user_id ON public.suspicious_activity(user_id);
CREATE INDEX IF NOT EXISTS idx_suspicious_type ON public.suspicious_activity(activity_type);
CREATE INDEX IF NOT EXISTS idx_suspicious_severity ON public.suspicious_activity(severity);
CREATE INDEX IF NOT EXISTS idx_suspicious_created_at ON public.suspicious_activity(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_suspicious_user_type ON public.suspicious_activity(user_id, activity_type);

-- Enable Row-Level Security
ALTER TABLE public.suspicious_activity ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users CANNOT read suspicious activity logs (admin-only)
CREATE POLICY "Block user access to suspicious activity"
    ON public.suspicious_activity
    FOR SELECT
    USING (false);

-- RLS Policy: Service role full access (for logging and admin dashboard)
CREATE POLICY "Service role full access on suspicious activity"
    ON public.suspicious_activity
    FOR ALL
    USING (auth.jwt()->>'role' = 'service_role');

-- Function: Log suspicious activity
CREATE OR REPLACE FUNCTION public.log_suspicious_activity(
    p_user_id UUID,
    p_activity_type TEXT,
    p_severity TEXT DEFAULT 'low',
    p_description TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT NULL,
    p_ip_address TEXT DEFAULT NULL,
    p_device_id TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    activity_id UUID;
BEGIN
    INSERT INTO public.suspicious_activity (
        user_id, activity_type, severity, description,
        metadata, ip_address, device_id
    ) VALUES (
        p_user_id, p_activity_type, p_severity, p_description,
        p_metadata, p_ip_address, p_device_id
    )
    RETURNING id INTO activity_id;

    RETURN activity_id;
END;
$$;

-- Function: Get suspicious activity count for user (last 24h)
CREATE OR REPLACE FUNCTION public.get_recent_suspicious_activity_count(
    p_user_id UUID,
    p_activity_type TEXT DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    activity_count INT;
BEGIN
    IF p_activity_type IS NULL THEN
        SELECT COUNT(*) INTO activity_count
        FROM public.suspicious_activity
        WHERE user_id = p_user_id
          AND created_at >= now() - INTERVAL '24 hours';
    ELSE
        SELECT COUNT(*) INTO activity_count
        FROM public.suspicious_activity
        WHERE user_id = p_user_id
          AND activity_type = p_activity_type
          AND created_at >= now() - INTERVAL '24 hours';
    END IF;

    RETURN COALESCE(activity_count, 0);
END;
$$;

-- Function: Check if user should be flagged/blocked
CREATE OR REPLACE FUNCTION public.should_block_user(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    critical_count INT;
    high_count INT;
    concurrent_count INT;
BEGIN
    -- Count critical severity events in last 24h
    SELECT COUNT(*) INTO critical_count
    FROM public.suspicious_activity
    WHERE user_id = p_user_id
      AND severity = 'critical'
      AND created_at >= now() - INTERVAL '24 hours';

    -- Count high severity events in last 24h
    SELECT COUNT(*) INTO high_count
    FROM public.suspicious_activity
    WHERE user_id = p_user_id
      AND severity = 'high'
      AND created_at >= now() - INTERVAL '24 hours';

    -- Count concurrent usage events in last hour
    SELECT COUNT(*) INTO concurrent_count
    FROM public.suspicious_activity
    WHERE user_id = p_user_id
      AND activity_type = 'concurrent_usage'
      AND created_at >= now() - INTERVAL '1 hour';

    -- Block if: 1+ critical, 5+ high, or 10+ concurrent usage
    RETURN (critical_count >= 1 OR high_count >= 5 OR concurrent_count >= 10);
END;
$$;

-- Grant permissions
GRANT INSERT ON public.suspicious_activity TO service_role;
GRANT SELECT ON public.suspicious_activity TO service_role;

COMMENT ON TABLE public.suspicious_activity IS 'Abuse detection and security monitoring log (admin-only access)';
COMMENT ON FUNCTION public.log_suspicious_activity IS 'Log suspicious activity event';
COMMENT ON FUNCTION public.get_recent_suspicious_activity_count IS 'Get count of suspicious events for user in last 24h';
COMMENT ON FUNCTION public.should_block_user IS 'Determine if user should be blocked based on suspicious activity patterns';
