-- Migration 008: Login / auth event audit log
-- Dependencies: 001_profiles.sql

CREATE TABLE IF NOT EXISTS public.login_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    email TEXT,
    method TEXT NOT NULL,
    success BOOLEAN NOT NULL DEFAULT true,
    device_id TEXT,
    error TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    CONSTRAINT valid_login_method CHECK (
        method IN ('email_signup', 'email_signin', 'email_confirm', 'oauth_google', 'oauth_github', 'oauth_apple', 'sign_out', 'token_refresh')
    )
);

CREATE INDEX IF NOT EXISTS idx_login_events_user_id ON public.login_events(user_id);
CREATE INDEX IF NOT EXISTS idx_login_events_created_at ON public.login_events(created_at DESC);

ALTER TABLE public.login_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own login events" ON public.login_events;
CREATE POLICY "Users can read own login events"
    ON public.login_events
    FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own login events" ON public.login_events;
CREATE POLICY "Users can insert own login events"
    ON public.login_events
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Service role full access on login_events" ON public.login_events;
CREATE POLICY "Service role full access on login_events"
    ON public.login_events
    FOR ALL
    USING (auth.jwt()->>'role' = 'service_role');

GRANT SELECT, INSERT ON public.login_events TO authenticated;
GRANT ALL ON public.login_events TO service_role;
