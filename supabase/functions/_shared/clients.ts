// Shared Supabase and Stripe client initialization
// Used by all Edge Functions

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import Stripe from 'https://esm.sh/stripe@14.11.0';

// Get authenticated Supabase client from request
export function getSupabaseClient(req: Request) {
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';

  // Get auth token from request header
  const authHeader = req.headers.get('Authorization') ?? '';

  return createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
}

// Get Supabase service role client (bypasses RLS)
export function getSupabaseServiceClient() {
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

  return createClient(supabaseUrl, supabaseServiceKey, {
    auth: { persistSession: false },
  });
}

// Get Stripe client (server-side only)
export function getStripeClient() {
  const stripeKey = Deno.env.get('STRIPE_SECRET_KEY') ?? '';
  return new Stripe(stripeKey, {
    apiVersion: '2023-10-16',
    httpClient: Stripe.createFetchHttpClient(),
  });
}

// Get user ID from JWT token in request
// Must pass JWT explicitly - getUser() without token does not work reliably in Edge Functions
export async function getUserId(req: Request): Promise<string | null> {
  const authHeader = req.headers.get('Authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return null;
  }

  const token = authHeader.replace('Bearer ', '');
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';

  const supabase = createClient(supabaseUrl, supabaseAnonKey);
  const { data: { user }, error } = await supabase.auth.getUser(token);

  if (error || !user) {
    return null;
  }

  return user.id;
}

// Get managed Groq API key based on tier
export function getManagedGroqKey(tier: string): string | null {
  // Free tier users bring their own key
  if (tier === 'free') {
    return null;
  }

  // For paid tiers, use managed keys
  // In production, you might have different keys per tier for rate limiting
  const groqApiKey = Deno.env.get('GROQ_API_KEY');
  return groqApiKey || null;
}

// CORS headers for all Edge Functions
export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
