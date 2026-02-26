-- Migration 004: Device Tracking
-- Creates devices table for device limit enforcement and abuse detection
-- Dependencies: 001_profiles.sql

-- Create devices table
CREATE TABLE IF NOT EXISTS public.devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL,
    device_name TEXT,
    device_type TEXT,  -- 'mac', 'windows', 'ios', 'android'
    os_version TEXT,
    app_version TEXT,
    last_seen_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    last_ip_address TEXT,
    last_location_hint TEXT,  -- City/country from IP geolocation (optional)
    is_active BOOLEAN DEFAULT true NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL,

    -- Constraints
    UNIQUE(user_id, device_id),
    CONSTRAINT valid_device_type CHECK (device_type IN ('mac', 'windows', 'ios', 'android', 'unknown'))
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_devices_user_id ON public.devices(user_id);
CREATE INDEX IF NOT EXISTS idx_devices_device_id ON public.devices(device_id);
CREATE INDEX IF NOT EXISTS idx_devices_user_active ON public.devices(user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_devices_last_seen ON public.devices(last_seen_at DESC);

-- Enable Row-Level Security
ALTER TABLE public.devices ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can read their own devices
CREATE POLICY "Users can read own devices"
    ON public.devices
    FOR SELECT
    USING (auth.uid() = user_id);

-- RLS Policy: Users can update their own devices (for deactivation)
CREATE POLICY "Users can update own devices"
    ON public.devices
    FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- RLS Policy: Service role full access
CREATE POLICY "Service role full access on devices"
    ON public.devices
    FOR ALL
    USING (auth.jwt()->>'role' = 'service_role');

-- Trigger: Auto-update updated_at and last_seen_at
DROP TRIGGER IF EXISTS on_device_updated ON public.devices;
CREATE TRIGGER on_device_updated
    BEFORE UPDATE ON public.devices
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_updated_at();

-- Function: Register or update device (enforces 3-device limit)
CREATE OR REPLACE FUNCTION public.register_device(
    p_user_id UUID,
    p_device_id TEXT,
    p_device_name TEXT DEFAULT NULL,
    p_device_type TEXT DEFAULT 'unknown',
    p_os_version TEXT DEFAULT NULL,
    p_app_version TEXT DEFAULT NULL,
    p_ip_address TEXT DEFAULT NULL,
    p_location_hint TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    active_device_count INT;
    existing_device RECORD;
    result JSON;
BEGIN
    -- Check if device already exists
    SELECT * INTO existing_device
    FROM public.devices
    WHERE user_id = p_user_id AND device_id = p_device_id;

    IF FOUND THEN
        -- Device exists, update last_seen and metadata
        UPDATE public.devices
        SET
            last_seen_at = now(),
            last_ip_address = COALESCE(p_ip_address, last_ip_address),
            last_location_hint = COALESCE(p_location_hint, last_location_hint),
            device_name = COALESCE(p_device_name, device_name),
            os_version = COALESCE(p_os_version, os_version),
            app_version = COALESCE(p_app_version, app_version),
            is_active = true
        WHERE user_id = p_user_id AND device_id = p_device_id;

        result := json_build_object(
            'success', true,
            'device_id', p_device_id,
            'is_new', false,
            'message', 'Device updated'
        );
        RETURN result;
    END IF;

    -- New device - check active device count
    SELECT COUNT(*) INTO active_device_count
    FROM public.devices
    WHERE user_id = p_user_id AND is_active = true;

    IF active_device_count >= 3 THEN
        -- Device limit exceeded
        result := json_build_object(
            'success', false,
            'device_id', p_device_id,
            'error', 'device_limit_exceeded',
            'message', 'Maximum 3 devices allowed per account. Please deactivate a device first.',
            'active_devices', active_device_count
        );
        RETURN result;
    END IF;

    -- Register new device
    INSERT INTO public.devices (
        user_id, device_id, device_name, device_type,
        os_version, app_version, last_ip_address, last_location_hint
    ) VALUES (
        p_user_id, p_device_id, p_device_name, p_device_type,
        p_os_version, p_app_version, p_ip_address, p_location_hint
    );

    result := json_build_object(
        'success', true,
        'device_id', p_device_id,
        'is_new', true,
        'message', 'Device registered successfully'
    );
    RETURN result;
END;
$$;

-- Function: Deactivate device
CREATE OR REPLACE FUNCTION public.deactivate_device(
    p_user_id UUID,
    p_device_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.devices
    SET is_active = false, updated_at = now()
    WHERE user_id = p_user_id AND device_id = p_device_id;

    RETURN FOUND;
END;
$$;

-- Grant permissions
GRANT SELECT, UPDATE ON public.devices TO authenticated;
GRANT ALL ON public.devices TO service_role;

COMMENT ON TABLE public.devices IS 'Registered devices per user (max 3 active devices)';
COMMENT ON FUNCTION public.register_device IS 'Register or update device, enforces 3-device limit';
COMMENT ON FUNCTION public.deactivate_device IS 'Deactivate a device to free up a device slot';
COMMENT ON COLUMN public.devices.device_id IS 'Unique device identifier (UUID or hardware ID)';
COMMENT ON COLUMN public.devices.is_active IS 'Active devices count towards the 3-device limit';
