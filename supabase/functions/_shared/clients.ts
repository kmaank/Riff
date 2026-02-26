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

// Get Stripe client (server-side only)
export function getStripeClient() {
  const stripeKey = Deno.env.get('STRIPE_SECRET_KEY') ?? '';
  return new Stripe(stripeKey, {
    apiVersion: '2023-10-16',
    httpClient: Stripe.createFetchHttpClient(),
  });
}

// Get user ID from JWT token
export async function getUserId(supabase: any): Promise<string | null> {
  const { data: { user }, error } = await supabase.auth.getUser();
  
  if (error || !user) {
    return null;
  }
  
  return user.id;
}

// CORS headers for all Edge Functions
export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
