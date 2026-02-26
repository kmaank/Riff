/**
 * create-portal Edge Function
 * Creates a Stripe Customer Portal session for self-service billing
 * Returns portal URL to open in browser
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  getSupabaseServiceClient,
  getStripeClient,
} from "../_shared/clients.ts";
import {
  authenticateUser,
  corsHeaders,
  handleCors,
  jsonResponse,
  errorResponse,
} from "../_shared/auth.ts";
import type { CreatePortalResponse, Subscription } from "../_shared/types.ts";

serve(async (req) => {
  // Handle CORS preflight
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  try {
    // Authenticate user
    const user = await authenticateUser(req);
    const userId = user.id;

    // Get subscription to find Stripe customer ID
    const supabase = getSupabaseServiceClient();
    const { data: subscription, error } = await supabase
      .from("subscriptions")
      .select("*")
      .eq("user_id", userId)
      .single<Subscription>();

    if (error || !subscription) {
      return errorResponse("Subscription not found", 404);
    }

    if (!subscription.stripe_customer_id) {
      return errorResponse(
        "No billing account found. Please upgrade to a paid plan first.",
        400,
        "no_customer_id"
      );
    }

    const stripe = getStripeClient();

    // Create Stripe Customer Portal session
    const session = await stripe.billingPortal.sessions.create({
      customer: subscription.stripe_customer_id,
      return_url: "riff://settings/account",
    });

    if (!session.url) {
      return errorResponse("Failed to create portal session", 500);
    }

    const response: CreatePortalResponse = {
      url: session.url,
    };

    return jsonResponse(response);
  } catch (error: any) {
    console.error("create-portal error:", error);
    return errorResponse(error.message || "Internal server error", 500);
  }
});
