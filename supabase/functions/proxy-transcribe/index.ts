/**
 * proxy-transcribe Edge Function
 * Proxies Groq Whisper API requests with server-side key injection
 * Prevents API key extraction by paid users
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { getSupabaseServiceClient, getManagedGroqKey } from "../_shared/clients.ts";
import {
  authenticateUser,
  corsHeaders,
  handleCors,
  errorResponse,
  verifyRequestSignature,
  getClientIp,
} from "../_shared/auth.ts";
import { getTierConfig, checkQuota } from "../_shared/tier-limits.ts";
import type { Subscription, MonthlyUsage } from "../_shared/types.ts";

serve(async (req) => {
  // Handle CORS preflight
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  try {
    // Authenticate user
    const user = await authenticateUser(req);
    const userId = user.id;

    // Verify request signature
    const signatureValid = await verifyRequestSignature(
      req,
      userId,
      "/proxy-transcribe"
    );

    if (!signatureValid) {
      const supabase = getSupabaseServiceClient();
      await supabase.rpc("log_suspicious_activity", {
        p_user_id: userId,
        p_activity_type: "invalid_signature",
        p_severity: "high",
        p_description: "Invalid signature on proxy-transcribe (possible attack)",
        p_ip_address: getClientIp(req),
      });

      return errorResponse("Invalid request signature", 403, "invalid_signature");
    }

    // Get subscription
    const supabase = getSupabaseServiceClient();
    const { data: subscription } = await supabase
      .from("subscriptions")
      .select("*")
      .eq("user_id", userId)
      .single<Subscription>();

    if (!subscription || subscription.status !== "active") {
      return errorResponse("Subscription not active", 403, "subscription_inactive");
    }

    // Check quota
    const { data: usageData } = await supabase
      .from("monthly_usage")
      .select("*")
      .eq("user_id", userId)
      .single<MonthlyUsage>();

    const riffsUsed = usageData?.riffs_used || 0;
    const secondsUsed = usageData?.seconds_used || 0;

    const quotaCheck = checkQuota(subscription.tier, riffsUsed, secondsUsed);
    if (quotaCheck.exceeded) {
      // Log quota exceeded attempt
      await supabase.rpc("log_suspicious_activity", {
        p_user_id: userId,
        p_activity_type: "quota_exceeded",
        p_severity: "low",
        p_description: quotaCheck.reason,
      });

      return errorResponse(
        quotaCheck.reason || "Quota exceeded",
        403,
        "quota_exceeded"
      );
    }

    // Get managed API key for tier
    const groqApiKey = getManagedGroqKey(subscription.tier);

    if (!groqApiKey) {
      return errorResponse(
        "No managed API key available for your tier",
        500,
        "no_managed_key"
      );
    }

    // Parse multipart form data (audio file)
    const contentType = req.headers.get("content-type") || "";
    if (!contentType.includes("multipart/form-data")) {
      return errorResponse("Expected multipart/form-data", 400);
    }

    // Forward request to Groq API with managed key
    const groqResponse = await fetch(
      "https://api.groq.com/openai/v1/audio/transcriptions",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${groqApiKey}`,
          // Forward content-type (includes boundary)
        },
        body: req.body,
      }
    );

    if (!groqResponse.ok) {
      const errorText = await groqResponse.text();
      console.error("Groq API error:", errorText);
      return errorResponse("Transcription failed", groqResponse.status);
    }

    // Return Groq response
    const transcription = await groqResponse.json();

    return new Response(JSON.stringify(transcription), {
      status: 200,
      headers: {
        "Content-Type": "application/json",
        ...corsHeaders,
      },
    });
  } catch (error: any) {
    console.error("proxy-transcribe error:", error);
    return errorResponse(error.message || "Internal server error", 500);
  }
});
