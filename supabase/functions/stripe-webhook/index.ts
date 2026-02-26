// Edge Function: stripe-webhook
// Handles Stripe webhook events (payment success, subscription changes)

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { getSupabaseClient, getStripeClient, corsHeaders } from '../_shared/clients.ts';

serve(async (req) => {
  try {
    const stripe = getStripeClient();
    const signature = req.headers.get('stripe-signature');
    const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET');

    if (!signature || !webhookSecret) {
      return new Response('Missing signature or secret', { status: 400 });
    }

    // Verify webhook signature
    const body = await req.text();
    let event;

    try {
      event = await stripe.webhooks.constructEventAsync(
        body,
        signature,
        webhookSecret
      );
    } catch (err) {
      console.error('Webhook signature verification failed:', err.message);
      return new Response('Invalid signature', { status: 400 });
    }

    // Get service role Supabase client (bypasses RLS)
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Handle different event types
    switch (event.type) {
      case 'checkout.session.completed': {
        const session = event.data.object;
        const userId = session.metadata?.user_id;
        const tier = session.metadata?.tier;

        if (!userId || !tier) {
          console.error('Missing metadata in checkout session');
          break;
        }

        // Update subscription
        const updates: any = {
          tier,
          status: 'active',
        };

        if (tier !== 'lifetime') {
          updates.stripe_subscription_id = session.subscription;
          updates.current_period_start = new Date(session.created * 1000).toISOString();
        }

        await supabase
          .from('subscriptions')
          .update(updates)
          .eq('user_id', userId);

        // Provision managed API key for paid tiers
        if (tier !== 'free') {
          await provisionManagedKey(supabase, userId, tier);
        }

        console.log(`Checkout completed for user ${userId}, tier ${tier}`);
        break;
      }

      case 'customer.subscription.updated': {
        const subscription = event.data.object;
        const customerId = subscription.customer;

        // Find user by customer ID
        const { data: sub } = await supabase
          .from('subscriptions')
          .select('user_id')
          .eq('stripe_customer_id', customerId)
          .single();

        if (!sub) {
          console.error('Subscription not found for customer:', customerId);
          break;
        }

        // Update subscription status and period
        await supabase
          .from('subscriptions')
          .update({
            status: subscription.status,
            current_period_start: new Date(subscription.current_period_start * 1000).toISOString(),
            current_period_end: new Date(subscription.current_period_end * 1000).toISOString(),
          })
          .eq('user_id', sub.user_id);

        console.log(`Subscription updated for customer ${customerId}`);
        break;
      }

      case 'customer.subscription.deleted': {
        const subscription = event.data.object;
        const customerId = subscription.customer;

        // Find user
        const { data: sub } = await supabase
          .from('subscriptions')
          .select('user_id')
          .eq('stripe_customer_id', customerId)
          .single();

        if (!sub) {
          console.error('Subscription not found for customer:', customerId);
          break;
        }

        // Downgrade to free tier
        await supabase
          .from('subscriptions')
          .update({
            tier: 'free',
            status: 'expired',
            stripe_subscription_id: null,
            current_period_end: null,
          })
          .eq('user_id', sub.user_id);

        // Deactivate managed key
        await supabase
          .from('api_keys')
          .update({ is_active: false })
          .eq('user_id', sub.user_id);

        console.log(`Subscription canceled for customer ${customerId}`);
        break;
      }

      case 'invoice.payment_failed': {
        const invoice = event.data.object;
        const customerId = invoice.customer;

        // Find user
        const { data: sub } = await supabase
          .from('subscriptions')
          .select('user_id')
          .eq('stripe_customer_id', customerId)
          .single();

        if (!sub) break;

        // Mark as past_due
        await supabase
          .from('subscriptions')
          .update({ status: 'past_due' })
          .eq('user_id', sub.user_id);

        console.log(`Payment failed for customer ${customerId}`);
        break;
      }

      default:
        console.log(`Unhandled event type: ${event.type}`);
    }

    return new Response(JSON.stringify({ received: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });

  } catch (error) {
    console.error('Error in stripe-webhook:', error);
    return new Response('Internal error', { status: 500 });
  }
});

// Helper: Provision managed API key for paid tier
async function provisionManagedKey(supabase: any, userId: string, tier: string) {
  // Check if key already exists
  const { data: existing } = await supabase
    .from('api_keys')
    .select('id')
    .eq('user_id', userId)
    .single();

  if (existing) {
    // Reactivate existing key
    await supabase
      .from('api_keys')
      .update({ is_active: true, tier })
      .eq('user_id', userId);
  } else {
    // Create new key
    // TODO: In production, fetch a real Groq key from pool and encrypt it
    const managedKey = Deno.env.get('MANAGED_GROQ_API_KEY') ?? 'gsk_managed_key_placeholder';
    
    await supabase
      .from('api_keys')
      .insert({
        user_id: userId,
        encrypted_key: managedKey,  // TODO: Encrypt this
        tier,
        is_active: true,
      });
  }
}

// Import needed for Supabase client
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
