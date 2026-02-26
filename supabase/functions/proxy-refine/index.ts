/**
 * proxy-refine Edge Function
 * Proxies Groq LLM API requests with server-side key injection
 * Used for text refinement (style application)
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { getSupabaseServiceClient, getManagedGroqKey } from "../_shared/clients.ts";
import {
  authenticateUser,
  corsHeaders,
  handleCors,
  jsonResponse,
  errorResponse,
  verifyRequestSignature,
  getClientIp,
} from "../_shared/auth.ts";
import { getTierConfig, isStyleAllowed } from "../_shared/tier-limits.ts";
import type { Subscription } from "../_shared/types.ts";

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
      "/proxy-refine"
    );

    if (!signatureValid) {
      const supabase = getSupabaseServiceClient();
      await supabase.rpc("log_suspicious_activity", {
        p_user_id: userId,
        p_activity_type: "invalid_signature",
        p_severity: "high",
        p_description: "Invalid signature on proxy-refine (possible attack)",
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

    // Parse request body
    const body = await req.json();
    const { messages, model, style } = body;

    if (!messages || !Array.isArray(messages)) {
      return errorResponse("Invalid request: messages array required", 400);
    }

    // Validate style is allowed for tier
    if (style && !isStyleAllowed(subscription.tier, style)) {
      return errorResponse(
        `Style '${style}' not available for ${subscription.tier} tier`,
        403,
        "style_not_allowed"
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

    // Forward request to Groq API with managed key
    const groqResponse = await fetch(
      "https://api.groq.com/openai/v1/chat/completions",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${groqApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: model || "llama-3.3-70b-versatile",
          messages,
          temperature: 0.3,
          max_tokens: 2000,
        }),
      }
    );

    if (!groqResponse.ok) {
      const errorText = await groqResponse.text();
      console.error("Groq API error:", errorText);
      return errorResponse("Refinement failed", groqResponse.status);
    }

    // Return Groq response
    const completion = await groqResponse.json();

    return new Response(JSON.stringify(completion), {
      status: 200,
      headers: {
        "Content-Type": "application/json",
        ...corsHeaders,
      },
    });
  } catch (error: any) {
    console.error("proxy-refine error:", error);
    return errorResponse(error.message || "Internal server error", 500);
  }
});
