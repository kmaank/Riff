-- Allow monthly/yearly paid keys. Users still cannot read this table (service_role only).

ALTER TABLE public.api_keys
    DROP CONSTRAINT IF EXISTS valid_tier;

ALTER TABLE public.api_keys
    ADD CONSTRAINT valid_tier CHECK (
        tier IN ('monthly', 'yearly', 'starter', 'pro', 'lifetime')
    );

REVOKE ALL ON public.api_keys FROM anon, authenticated, PUBLIC;
GRANT ALL ON public.api_keys TO service_role;

COMMENT ON COLUMN public.api_keys.encrypted_key IS
    'AES-256-GCM wrapped Groq key (v1.iv.ciphertext). Unwrap only in Edge Functions.';
