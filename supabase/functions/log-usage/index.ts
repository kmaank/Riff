/**
 * log-usage Edge Function
 * Logs riff usage (word count, recording seconds, style)
 * Called after each successful transcription
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { getSupabaseServiceClient } from "../_shared/clients.ts";
import {
  authenticateUser,
  corsHeaders,
  handleCors,
  jsonResponse,
  errorResponse,
  verifyRequestSignature,
  getClientIp,
} from "../_shared/auth.ts";
import type { LogUsageResponse, MonthlyUsage } from "../_shared/types.ts";

serve(async (req) => {
  // Handle CORS preflight
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  try {
    // Authenticate user
    const user = await authenticateUser(req);
    const userId = user.id;

    // Verify request signature (HMAC)
    const signatureValid = await verifyRequestSignature(
      req,
      userId,
      "/log-usage"
    );

    if (!signatureValid) {
      // Log suspicious activity
      const supabase = getSupabaseServiceClient();
      await supabase.rpc("log_suspicious_activity", {
        p_user_id: userId,
        p_activity_type: "invalid_signature",
        p_severity: "medium",
        p_description: "Invalid HMAC signature on log-usage request",
        p_ip_address: getClientIp(req),
      });

      return errorResponse("Invalid request signature", 403, "invalid_signature");
    }

    // Parse request body
    const body = await req.json();
    const { word_count, recording_seconds, style, script_mode, device_id } = body;

    if (
      typeof word_count !== "number" ||
      typeof recording_seconds !== "number" ||
      !style
    ) {
      return errorResponse("Missing required fields", 400, "invalid_request");
    }

    // Get Supabase service client
    const supabase = getSupabaseServiceClient();

    // Check for concurrent usage (abuse detection)
    const { data: concurrentUsage } = await supabase.rpc("detect_concurrent_usage", {
      p_user_id: userId,
    });

    if (concurrentUsage === true) {
      // Log suspicious activity
      await supabase.rpc("log_suspicious_activity", {
        p_user_id: userId,
        p_activity_type: "concurrent_usage",
        p_severity: "high",
        p_description: "Multiple riffs within 10 seconds (potential account sharing)",
        p_ip_address: getClientIp(req),
        p_device_id: device_id,
      });
    }

    // Insert usage log
    const { error: insertError } = await supabase.from("usage_logs").insert({
      user_id: userId,
      word_count,
      recording_seconds,
      style,
      script_mode,
    });

    if (insertError) {
      console.error("Failed to insert usage log:", insertError);
      return errorResponse("Failed to log usage", 500);
    }

    // Fetch updated monthly usage
    const { data: usageData } = await supabase
      .from("monthly_usage")
      .select("*")
      .eq("user_id", userId)
      .single<MonthlyUsage>();

    const response: LogUsageResponse = {
      success: true,
      quota: {
        riffs_used: usageData?.riffs_used || 0,
        seconds_used: usageData?.seconds_used || 0,
      },
    };

    return jsonResponse(response);
  } catch (error: any) {
    console.error("log-usage error:", error);
    return errorResponse(error.message || "Internal server error", 500);
  }
});
