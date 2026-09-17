-- Migration 010: Lock SECURITY DEFINER RPCs to the calling user or service role
-- Dependencies: 004_devices.sql, 005_riff_history.sql, 006_suspicious_activity.sql

CREATE OR REPLACE FUNCTION public._assert_user_or_service(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF auth.jwt()->>'role' = 'service_role' THEN
        RETURN;
    END IF;
    IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id THEN
        RAISE EXCEPTION 'not authorized';
    END IF;
END;
$$;

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
    PERFORM public._assert_user_or_service(p_user_id);

    SELECT * INTO existing_device
    FROM public.devices
    WHERE user_id = p_user_id AND device_id = p_device_id;

    IF FOUND THEN
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

    SELECT COUNT(*) INTO active_device_count
    FROM public.devices
    WHERE user_id = p_user_id AND is_active = true;

    IF active_device_count >= 3 THEN
        result := json_build_object(
            'success', false,
            'device_id', p_device_id,
            'error', 'device_limit_exceeded',
            'message', 'Maximum 3 devices allowed per account. Please deactivate a device first.',
            'active_devices', active_device_count
        );
        RETURN result;
    END IF;

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
    PERFORM public._assert_user_or_service(p_user_id);
    UPDATE public.devices
    SET is_active = false, updated_at = now()
    WHERE user_id = p_user_id AND device_id = p_device_id;
    RETURN FOUND;
END;
$$;

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
    PERFORM public._assert_user_or_service(p_user_id);
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
    LIMIT LEAST(p_limit, 1000)
    OFFSET p_offset;
END;
$$;

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
    PERFORM public._assert_user_or_service(p_user_id);
    INSERT INTO public.riff_history (
        user_id, timestamp, original, refined, style, script_mode, device_id
    ) VALUES (
        p_user_id, p_timestamp, p_original, p_refined, p_style, p_script_mode, p_device_id
    )
    ON CONFLICT (user_id, timestamp)
    DO UPDATE SET
        original = EXCLUDED.original,
        refined = EXCLUDED.refined,
        style = EXCLUDED.style,
        script_mode = EXCLUDED.script_mode,
        device_id = EXCLUDED.device_id;

    SELECT COUNT(*) INTO history_count
    FROM public.riff_history
    WHERE user_id = p_user_id;

    IF history_count > 1000 THEN
        DELETE FROM public.riff_history
        WHERE id IN (
            SELECT id FROM public.riff_history
            WHERE user_id = p_user_id
            ORDER BY "timestamp" ASC
            LIMIT (history_count - 1000)
        );
    END IF;

    result := json_build_object('success', true, 'timestamp', p_timestamp);
    RETURN result;
END;
$$;

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
    PERFORM public._assert_user_or_service(p_user_id);
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

    DELETE FROM public.riff_history
    WHERE id IN (
        SELECT id FROM public.riff_history
        WHERE user_id = p_user_id
        ORDER BY "timestamp" ASC
        OFFSET 1000
    );

    RETURN json_build_object('success', true, 'uploaded', uploaded_count);
END;
$$;

REVOKE ALL ON FUNCTION public.register_device(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.deactivate_device(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_user_history(UUID, INT, INT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.upload_riff_history(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.batch_upload_history(UUID, JSONB) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.register_device(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.deactivate_device(UUID, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_user_history(UUID, INT, INT) TO service_role;
GRANT EXECUTE ON FUNCTION public.upload_riff_history(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.batch_upload_history(UUID, JSONB) TO service_role;
