/**
 * create-checkout Edge Function
 * Creates a Stripe Checkout session for subscription upgrade
 * Returns checkout URL to open in browser
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  getSupabaseServiceClient,
  getStripeClient,
  getStripePriceIds,
} from "../_shared/clients.ts";
import {
  authenticateUser,
  corsHeaders,
  handleCors,
  jsonResponse,
  errorResponse,
} from "../_shared/auth.ts";
import type { CreateCheckoutResponse, Subscription } from "../_shared/types.ts";

serve(async (req) => {
  // Handle CORS preflight
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  try {
    // Authenticate user
    const user = await authenticateUser(req);
    const userId = user.id;
    const userEmail = user.email || "";

    // Parse request body
    const body = await req.json();
    const { tier } = body; // "starter", "pro", or "lifetime"

    if (!tier || !["starter", "pro", "lifetime"].includes(tier)) {
      return errorResponse("Invalid tier. Must be starter, pro, or lifetime", 400);
    }

    // Get Stripe price ID for tier
    const priceIds = getStripePriceIds();
    const priceId =
      tier === "starter"
        ? priceIds.starter
        : tier === "pro"
        ? priceIds.pro
        : priceIds.lifetime;

    if (!priceId) {
      return errorResponse(`Price ID not configured for tier: ${tier}`, 500);
    }

    // Get existing subscription to check for Stripe customer ID
    const supabase = getSupabaseServiceClient();
    const { data: subscription } = await supabase
      .from("subscriptions")
      .select("*")
      .eq("user_id", userId)
      .single<Subscription>();

    const stripe = getStripeClient();

    // Determine mode (subscription vs payment)
    const mode = tier === "lifetime" ? "payment" : "subscription";

    // Create Stripe Checkout session
    const session = await stripe.checkout.sessions.create({
      customer_email: subscription?.stripe_customer_id ? undefined : userEmail,
      customer: subscription?.stripe_customer_id || undefined,
      mode,
      line_items: [
        {
          price: priceId,
          quantity: 1,
        },
      ],
      success_url: `riff://checkout/success?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `riff://checkout/cancel`,
      metadata: {
        user_id: userId,
        tier,
      },
      // Allow promotion codes
      allow_promotion_codes: true,
    });

    if (!session.url) {
      return errorResponse("Failed to create checkout session", 500);
    }

    const response: CreateCheckoutResponse = {
      url: session.url,
      session_id: session.id,
    };

    return jsonResponse(response);
  } catch (error: any) {
    console.error("create-checkout error:", error);
    return errorResponse(error.message || "Internal server error", 500);
  }
});
