/**
 * register-device Edge Function
 * Registers or updates a device for a user (enforces 3-device limit)
 * Called on app startup
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { getSupabaseServiceClient } from "../_shared/clients.ts";
import {
  authenticateUser,
  corsHeaders,
  handleCors,
  jsonResponse,
  errorResponse,
  getClientIp,
} from "../_shared/auth.ts";
import type { RegisterDeviceResponse } from "../_shared/types.ts";

serve(async (req) => {
  // Handle CORS preflight
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  try {
    // Authenticate user
    const user = await authenticateUser(req);
    const userId = user.id;

    // Parse request body
    const body = await req.json();
    const {
      device_id,
      device_name,
      device_type,
      os_version,
      app_version,
    } = body;

    if (!device_id) {
      return errorResponse("device_id is required", 400);
    }

    // Get client IP for logging
    const ipAddress = getClientIp(req);

    // Call register_device stored procedure
    const supabase = getSupabaseServiceClient();
    const { data, error } = await supabase.rpc("register_device", {
      p_user_id: userId,
      p_device_id: device_id,
      p_device_name: device_name || null,
      p_device_type: device_type || "unknown",
      p_os_version: os_version || null,
      p_app_version: app_version || null,
      p_ip_address: ipAddress,
      p_location_hint: null, // Could integrate geolocation API
    });

    if (error) {
      console.error("register_device error:", error);
      return errorResponse("Failed to register device", 500);
    }

    // Log device limit exceeded as suspicious activity
    if (!data.success && data.error === "device_limit_exceeded") {
      await supabase.rpc("log_suspicious_activity", {
        p_user_id: userId,
        p_activity_type: "device_limit_exceeded",
        p_severity: "medium",
        p_description: "Attempted to register more than 3 devices",
        p_ip_address: ipAddress,
        p_device_id: device_id,
      });
    }

    return jsonResponse(data as RegisterDeviceResponse);
  } catch (error: any) {
    console.error("register-device error:", error);
    return errorResponse(error.message || "Internal server error", 500);
  }
});
