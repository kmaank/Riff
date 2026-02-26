/**
 * stripe-webhook Edge Function
 * Handles Stripe webhook events for subscription lifecycle
 * Updates subscriptions table based on payment events
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { getSupabaseServiceClient, getStripeClient } from "../_shared/clients.ts";
import { corsHeaders, jsonResponse, errorResponse } from "../_shared/auth.ts";
import type Stripe from "https://esm.sh/stripe@14.10.0";

serve(async (req) => {
  try {
    const signature = req.headers.get("stripe-signature");

    if (!signature) {
      return errorResponse("Missing stripe-signature header", 400);
    }

    const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
    if (!webhookSecret) {
      throw new Error("Missing STRIPE_WEBHOOK_SECRET");
    }

    const stripe = getStripeClient();
    const body = await req.text();

    // Verify webhook signature
    let event: Stripe.Event;
    try {
      event = await stripe.webhooks.constructEventAsync(
        body,
        signature,
        webhookSecret
      );
    } catch (err: any) {
      console.error("Webhook signature verification failed:", err.message);
      return errorResponse("Invalid signature", 400);
    }

    console.log(`Processing Stripe event: ${event.type}`);

    const supabase = getSupabaseServiceClient();

    // Handle different event types
    switch (event.type) {
      case "checkout.session.completed": {
        const session = event.data.object as Stripe.Checkout.Session;
        const userId = session.metadata?.user_id;
        const tier = session.metadata?.tier;

        if (!userId || !tier) {
          console.error("Missing metadata in checkout session");
          break;
        }

        // Update subscription
        const updateData: any = {
          tier,
          status: "active",
          stripe_customer_id: session.customer as string,
          updated_at: new Date().toISOString(),
        };

        // For recurring subscriptions, add subscription ID and period
        if (session.subscription) {
          updateData.stripe_subscription_id = session.subscription as string;

          // Fetch subscription details for period dates
          const subscription = await stripe.subscriptions.retrieve(
            session.subscription as string
          );
          updateData.current_period_start = new Date(
            subscription.current_period_start * 1000
          ).toISOString();
          updateData.current_period_end = new Date(
            subscription.current_period_end * 1000
          ).toISOString();
        } else {
          // Lifetime purchase (no subscription)
          updateData.stripe_subscription_id = null;
          updateData.current_period_start = null;
          updateData.current_period_end = null;
        }

        const { error } = await supabase
          .from("subscriptions")
          .update(updateData)
          .eq("user_id", userId);

        if (error) {
          console.error("Failed to update subscription:", error);
        } else {
          console.log(`Subscription upgraded to ${tier} for user ${userId}`);
        }

        break;
      }

      case "invoice.payment_succeeded": {
        const invoice = event.data.object as Stripe.Invoice;
        const subscriptionId = invoice.subscription as string;

        if (!subscriptionId) break;

        // Fetch subscription details
        const subscription = await stripe.subscriptions.retrieve(subscriptionId);

        // Update subscription period
        const { error } = await supabase
          .from("subscriptions")
          .update({
            status: "active",
            current_period_start: new Date(
              subscription.current_period_start * 1000
            ).toISOString(),
            current_period_end: new Date(
              subscription.current_period_end * 1000
            ).toISOString(),
            updated_at: new Date().toISOString(),
          })
          .eq("stripe_subscription_id", subscriptionId);

        if (error) {
          console.error("Failed to update subscription on payment success:", error);
        } else {
          console.log(`Subscription renewed: ${subscriptionId}`);
        }

        break;
      }

      case "invoice.payment_failed": {
        const invoice = event.data.object as Stripe.Invoice;
        const subscriptionId = invoice.subscription as string;

        if (!subscriptionId) break;

        // Mark subscription as past_due
        const { error } = await supabase
          .from("subscriptions")
          .update({
            status: "past_due",
            updated_at: new Date().toISOString(),
          })
          .eq("stripe_subscription_id", subscriptionId);

        if (error) {
          console.error("Failed to update subscription on payment failure:", error);
        } else {
          console.log(`Subscription past_due: ${subscriptionId}`);
        }

        break;
      }

      case "customer.subscription.deleted": {
        const subscription = event.data.object as Stripe.Subscription;

        // Downgrade to free tier
        const { error } = await supabase
          .from("subscriptions")
          .update({
            tier: "free",
            status: "expired",
            stripe_subscription_id: null,
            current_period_start: null,
            current_period_end: null,
            updated_at: new Date().toISOString(),
          })
          .eq("stripe_subscription_id", subscription.id);

        if (error) {
          console.error("Failed to downgrade subscription:", error);
        } else {
          console.log(`Subscription canceled and downgraded: ${subscription.id}`);
        }

        break;
      }

      case "customer.subscription.updated": {
        const subscription = event.data.object as Stripe.Subscription;

        // Update status and period
        const status =
          subscription.status === "active"
            ? "active"
            : subscription.status === "past_due"
            ? "past_due"
            : subscription.status === "canceled"
            ? "canceled"
            : "expired";

        const { error } = await supabase
          .from("subscriptions")
          .update({
            status,
            current_period_start: new Date(
              subscription.current_period_start * 1000
            ).toISOString(),
            current_period_end: new Date(
              subscription.current_period_end * 1000
            ).toISOString(),
            updated_at: new Date().toISOString(),
          })
          .eq("stripe_subscription_id", subscription.id);

        if (error) {
          console.error("Failed to update subscription:", error);
        } else {
          console.log(`Subscription updated: ${subscription.id} -> ${status}`);
        }

        break;
      }

      default:
        console.log(`Unhandled event type: ${event.type}`);
    }

    return jsonResponse({ received: true });
  } catch (error: any) {
    console.error("stripe-webhook error:", error);
    return errorResponse(error.message || "Internal server error", 500);
  }
});
