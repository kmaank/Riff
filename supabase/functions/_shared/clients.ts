/**
 * Shared Clients for Supabase Edge Functions
 * Provides initialized Supabase and Stripe clients
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import Stripe from "https://esm.sh/stripe@14.10.0";

/**
 * Create Supabase client with service role key
 * Use this for server-side operations that bypass RLS
 */
export function getSupabaseServiceClient() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_KEY");

  if (!supabaseUrl || !supabaseServiceKey) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_KEY");
  }

  return createClient(supabaseUrl, supabaseServiceKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

/**
 * Create Supabase client with anon key (for user-scoped operations)
 * This respects Row-Level Security policies
 */
export function getSupabaseAnonClient() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");

  if (!supabaseUrl || !supabaseAnonKey) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_ANON_KEY");
  }

  return createClient(supabaseUrl, supabaseAnonKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

/**
 * Create Stripe client
 */
export function getStripeClient() {
  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");

  if (!stripeKey) {
    throw new Error("Missing STRIPE_SECRET_KEY");
  }

  return new Stripe(stripeKey, {
    apiVersion: "2023-10-16",
    httpClient: Stripe.createFetchHttpClient(),
  });
}

/**
 * Get Stripe Price IDs from environment
 */
export function getStripePriceIds() {
  return {
    starter: Deno.env.get("STRIPE_PRICE_ID_STARTER"),
    pro: Deno.env.get("STRIPE_PRICE_ID_PRO"),
    lifetime: Deno.env.get("STRIPE_PRICE_ID_LIFETIME"),
  };
}

/**
 * Get managed Groq API key for a given tier
 */
export function getManagedGroqKey(tier: string): string | null {
  switch (tier) {
    case "starter":
      return Deno.env.get("GROQ_API_KEY_STARTER") || null;
    case "pro":
      return Deno.env.get("GROQ_API_KEY_PRO") || null;
    case "lifetime":
      return Deno.env.get("GROQ_API_KEY_LIFETIME") || null;
    default:
      return null;
  }
}

/**
 * Get HMAC secret for request signing verification
 */
export function getHmacSecret(): string {
  const secret = Deno.env.get("HMAC_SECRET");
  if (!secret) {
    throw new Error("Missing HMAC_SECRET");
  }
  return secret;
}

/**
 * Get encryption secret for API key encryption
 */
export function getEncryptionSecret(): string {
  const secret = Deno.env.get("ENCRYPTION_SECRET");
  if (!secret) {
    throw new Error("Missing ENCRYPTION_SECRET");
  }
  return secret;
}
