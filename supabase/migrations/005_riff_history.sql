-- Migration 005: Cloud-Synced Riff History
-- Creates riff_history table for cross-device history sync
-- Dependencies: 001_profiles.sql

-- Create riff_history table
CREATE TABLE IF NOT EXISTS public.riff_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    "timestamp" TEXT NOT NULL,  -- ISO timestamp string (matches client format)
    original TEXT NOT NULL,
    refined TEXT NOT NULL,
    style TEXT NOT NULL,
    script_mode TEXT,
    device_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,

    -- Constraints
    UNIQUE(user_id, "timestamp")  -- Prevent duplicate entries
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_riff_history_user_id ON public.riff_history(user_id);
CREATE INDEX IF NOT EXISTS idx_riff_history_user_timestamp ON public.riff_history(user_id, "timestamp" DESC);
CREATE INDEX IF NOT EXISTS idx_riff_history_created_at ON public.riff_history(created_at DESC);

-- Enable Row-Level Security
ALTER TABLE public.riff_history ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can read their own history
CREATE POLICY "Users can read own history"
    ON public.riff_history
    FOR SELECT
    USING (auth.uid() = user_id);

-- RLS Policy: Users can insert their own history
CREATE POLICY "Users can insert own history"
    ON public.riff_history
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- RLS Policy: Users can delete their own history
CREATE POLICY "Users can delete own history"
    ON public.riff_history
    FOR DELETE
    USING (auth.uid() = user_id);

-- RLS Policy: Service role full access
CREATE POLICY "Service role full access on history"
    ON public.riff_history
    FOR ALL
    USING (auth.jwt()->>'role' = 'service_role');

-- Function: Get user's history (paginated, last 1000 entries max)
CREATE OR REPLACE FUNCTION public.get_user_history(
    p_user_id UUID,
    p_limit INT DEFAULT 1000,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    id UUID,
    "timestamp" TEXT,
    original TEXT,
    refined TEXT,
    style TEXT,
    script_mode TEXT,
    device_id TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        h.id,
        h."timestamp",
        h.original,
        h.refined,
        h.style,
        h.script_mode,
        h.device_id
    FROM public.riff_history h
    WHERE h.user_id = p_user_id
    ORDER BY h."timestamp" DESC
    LIMIT LEAST(p_limit, 1000)  -- Max 1000 entries
    OFFSET p_offset;
END;
$$;

-- Function: Upload riff history entry (upsert)
CREATE OR REPLACE FUNCTION public.upload_riff_history(
    p_user_id UUID,
    p_timestamp TEXT,
    p_original TEXT,
    p_refined TEXT,
    p_style TEXT,
    p_script_mode TEXT DEFAULT NULL,
    p_device_id TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    history_count INT;
    result JSON;
BEGIN
    -- Insert or update (upsert) based on user_id + timestamp
    INSERT INTO public.riff_history (
        user_id, timestamp, original, refined, style, script_mode, device_id
    ) VALUES (
        p_user_id, p_timestamp, p_original, p_refined, p_style, p_script_mode, p_device_id
    )
    ON CONFLICT (user_id, "timestamp")
    DO UPDATE SET
        original = EXCLUDED.original,
        refined = EXCLUDED.refined,
        style = EXCLUDED.style,
        script_mode = EXCLUDED.script_mode,
        device_id = EXCLUDED.device_id;

    -- Check total history count and trim if needed (keep last 1000)
    SELECT COUNT(*) INTO history_count
    FROM public.riff_history
    WHERE user_id = p_user_id;

    IF history_count > 1000 THEN
        -- Delete oldest entries beyond 1000
        DELETE FROM public.riff_history
        WHERE id IN (
            SELECT id FROM public.riff_history
            WHERE user_id = p_user_id
            ORDER BY "timestamp" ASC
            LIMIT (history_count - 1000)
        );
    END IF;

    result := json_build_object(
        'success', true,
        'timestamp', p_timestamp
    );
    RETURN result;
END;
$$;

-- Function: Batch upload history (for initial sync)
CREATE OR REPLACE FUNCTION public.batch_upload_history(
    p_user_id UUID,
    p_entries JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    entry JSONB;
    uploaded_count INT := 0;
BEGIN
    FOR entry IN SELECT * FROM jsonb_array_elements(p_entries)
    LOOP
        INSERT INTO public.riff_history (
            user_id, "timestamp", original, refined, style, script_mode, device_id
        ) VALUES (
            p_user_id,
            entry->>'timestamp',
            entry->>'original',
            entry->>'refined',
            entry->>'style',
            entry->>'script_mode',
            entry->>'device_id'
        )
        ON CONFLICT (user_id, "timestamp") DO NOTHING;

        uploaded_count := uploaded_count + 1;
    END LOOP;

    -- Trim to last 1000 entries
    DELETE FROM public.riff_history
    WHERE id IN (
        SELECT id FROM public.riff_history
        WHERE user_id = p_user_id
        ORDER BY "timestamp" ASC
        OFFSET 1000
    );

    RETURN json_build_object(
        'success', true,
        'uploaded', uploaded_count
    );
END;
$$;

-- Grant permissions
GRANT SELECT, INSERT, DELETE ON public.riff_history TO authenticated;
GRANT ALL ON public.riff_history TO service_role;

COMMENT ON TABLE public.riff_history IS 'Cloud-synced riff history across all user devices (max 1000 entries)';
COMMENT ON FUNCTION public.get_user_history IS 'Get paginated history for a user';
COMMENT ON FUNCTION public.upload_riff_history IS 'Upload single history entry (upsert), auto-trims to 1000';
COMMENT ON FUNCTION public.batch_upload_history IS 'Batch upload history entries for initial sync';
