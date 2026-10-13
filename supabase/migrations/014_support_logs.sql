-- Support log snapshots sent from Home. Transcript text is stripped on the device
-- before insert. Developers read rows in the Supabase dashboard (service role).
-- Users can insert only their own row and cannot read anyone else's.

CREATE TABLE IF NOT EXISTS public.support_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT,
    app_version TEXT,
    macos TEXT,
    body TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_support_logs_created_at ON public.support_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_support_logs_user_id ON public.support_logs(user_id);

ALTER TABLE public.support_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users insert own support logs" ON public.support_logs;
CREATE POLICY "Users insert own support logs"
    ON public.support_logs
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Service role full access on support_logs" ON public.support_logs;
CREATE POLICY "Service role full access on support_logs"
    ON public.support_logs
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

GRANT INSERT ON public.support_logs TO authenticated;
GRANT ALL ON public.support_logs TO service_role;
