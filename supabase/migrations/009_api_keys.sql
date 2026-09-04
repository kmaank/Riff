-- Migration 009: Managed Groq API keys for paid tiers
-- Dependencies: 001_profiles.sql, 002_subscriptions.sql

CREATE TABLE IF NOT EXISTS public.api_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES public.profiles(id) ON DELETE CASCADE,
    encrypted_key TEXT NOT NULL,
    tier TEXT NOT NULL,
    is_active BOOLEAN DEFAULT true NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_api_keys_user_id ON public.api_keys(user_id);

ALTER TABLE public.api_keys ENABLE ROW LEVEL SECURITY;

-- Users never read keys directly; Edge Functions use the service role
DROP POLICY IF EXISTS "Service role full access on api_keys" ON public.api_keys;
CREATE POLICY "Service role full access on api_keys"
    ON public.api_keys
    FOR ALL
    USING (auth.jwt()->>'role' = 'service_role');

DROP TRIGGER IF EXISTS on_api_keys_updated ON public.api_keys;
CREATE TRIGGER on_api_keys_updated
    BEFORE UPDATE ON public.api_keys
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_updated_at();

GRANT ALL ON public.api_keys TO service_role;
