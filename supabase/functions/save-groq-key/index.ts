// Edge Function: save-groq-key
// Wraps the signed-in user's Groq key and stores it on their account.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { getSupabaseServiceClient, getUserId, corsHeaders } from "../_shared/clients.ts";
import { wrapApiKey } from "../_shared/crypto.ts";

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

    const body = await req.json().catch(() => ({}));
    const apiKey = typeof body.api_key === "string" ? body.api_key.trim() : "";
    if (!apiKey.startsWith("gsk_")) {
      return new Response(
        JSON.stringify({ error: "A Groq key starting with gsk_ is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const wrapped = await wrapApiKey(apiKey);
    const supabase = getSupabaseServiceClient();
    const { error } = await supabase
      .from("user_groq_keys")
      .upsert({ user_id: userId, encrypted_key: wrapped }, { onConflict: "user_id" });

    if (error) {
      console.error("save-groq-key upsert failed");
      return new Response(
        JSON.stringify({ error: "Internal server error" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    return new Response(
      JSON.stringify({ ok: true }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Error in save-groq-key:", error?.message || error);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
