-- Wrapped BYOK Groq keys. Clients never read this table; Edge Functions use service_role.

CREATE TABLE IF NOT EXISTS public.user_groq_keys (
    user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    encrypted_key TEXT NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

ALTER TABLE public.user_groq_keys ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.user_groq_keys FROM anon, authenticated, PUBLIC;
GRANT ALL ON public.user_groq_keys TO service_role;

DROP TRIGGER IF EXISTS on_user_groq_keys_updated ON public.user_groq_keys;
CREATE TRIGGER on_user_groq_keys_updated
    BEFORE UPDATE ON public.user_groq_keys
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_updated_at();

COMMENT ON TABLE public.user_groq_keys IS
    'AES-256-GCM wrapped user Groq keys. Unwrap only in Edge Functions after JWT auth.';
