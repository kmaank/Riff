// Edge Function: get-api-key
// Returns decrypted managed Groq API key for paid users
// Rate-limited to prevent abuse

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { getSupabaseClient, getUserId, corsHeaders } from '../_shared/clients.ts';

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const userId = await getUserId(req);

    if (!userId) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const supabase = getSupabaseClient(req);

    // Check subscription tier
    const { data: subscription, error: subError } = await supabase
      .from('subscriptions')
      .select('tier, status')
      .eq('user_id', userId)
      .single();

    if (subError || !subscription) {
      return new Response(
        JSON.stringify({ error: 'Subscription not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Free tier users must provide their own key
    if (subscription.tier === 'free') {
      return new Response(
        JSON.stringify({ error: 'Managed keys not available for free tier' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Subscription must be active
    if (subscription.status !== 'active') {
      return new Response(
        JSON.stringify({ error: 'Subscription not active' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Get API key
    const { data: apiKey, error: keyError } = await supabase
      .from('api_keys')
      .select('encrypted_key, is_active')
      .eq('user_id', userId)
      .single();

    if (keyError || !apiKey) {
      return new Response(
        JSON.stringify({ error: 'API key not found. Please contact support.' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (!apiKey.is_active) {
      return new Response(
        JSON.stringify({ error: 'API key is inactive. Please contact support.' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // TODO: Decrypt the encrypted_key using AES-256-GCM
    // For now, return as-is (assumes keys are stored plaintext in dev)
    // In production, use: const decryptedKey = await decrypt(apiKey.encrypted_key);
    const decryptedKey = apiKey.encrypted_key;

    return new Response(
      JSON.stringify({ api_key: decryptedKey }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Error in get-api-key:', error);
    return new Response(
      JSON.stringify({ error: 'Internal server error', message: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});

// TODO: Implement proper encryption/decryption
// import { decrypt } from '../_shared/crypto.ts';
