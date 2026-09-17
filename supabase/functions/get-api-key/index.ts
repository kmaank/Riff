// Edge Function: get-api-key
// Unwraps the managed Groq key for an active paid user.
// The Mac caches the plaintext in RAM for 24h and calls Groq directly.
// Ciphertext in Postgres is never readable without the server KEK.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { getSupabaseServiceClient, getUserId, corsHeaders } from "../_shared/clients.ts";
import { isWrapped, unwrapApiKey, wrapApiKey } from "../_shared/crypto.ts";

const LEASE_SECONDS = 24 * 60 * 60;

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const userId = await getUserId(req);

    if (!userId) {
      return new Response(
        JSON.stringify({ error: "Unauthorized" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const supabase = getSupabaseServiceClient();

    const { data: subscription, error: subError } = await supabase
      .from("subscriptions")
      .select("tier, status")
      .eq("user_id", userId)
      .single();

    if (subError || !subscription) {
      return new Response(
        JSON.stringify({ error: "Subscription not found" }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (subscription.tier === "free") {
      return new Response(
        JSON.stringify({ error: "Managed keys not available for free tier" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (subscription.status !== "active") {
      return new Response(
        JSON.stringify({ error: "Subscription not active" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const { data: apiKey, error: keyError } = await supabase
      .from("api_keys")
      .select("id, encrypted_key, is_active")
      .eq("user_id", userId)
      .single();

    if (keyError || !apiKey) {
      return new Response(
        JSON.stringify({ error: "API key not found. Please contact support." }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (!apiKey.is_active) {
      return new Response(
        JSON.stringify({ error: "API key is inactive. Please contact support." }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    let plaintext = await unwrapApiKey(apiKey.encrypted_key);

    // Migrate any leftover plaintext rows to wrapped form.
    if (!isWrapped(apiKey.encrypted_key)) {
      try {
        const wrapped = await wrapApiKey(plaintext);
        await supabase
          .from("api_keys")
          .update({ encrypted_key: wrapped })
          .eq("id", apiKey.id);
      } catch (e) {
        console.error("Failed to re-wrap stored key");
      }
    }

    const expiresAt = new Date(Date.now() + LEASE_SECONDS * 1000).toISOString();

    return new Response(
      JSON.stringify({
        api_key: plaintext,
        lease_seconds: LEASE_SECONDS,
        expires_at: expiresAt,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Error in get-api-key:", error?.message || error);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
