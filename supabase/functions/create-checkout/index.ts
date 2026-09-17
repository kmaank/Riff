// Edge Function: create-checkout
// Creates Stripe Checkout session for tier upgrades

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { getSupabaseClient, getSupabaseServiceClient, getStripeClient, getUserId, corsHeaders } from '../_shared/clients.ts';

interface CheckoutRequest {
  tier: 'monthly' | 'yearly' | 'starter' | 'pro' | 'lifetime';
}

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
    const stripe = getStripeClient();

    // Parse request
    const body: CheckoutRequest = await req.json();
    
    if (!['monthly', 'yearly', 'starter', 'pro', 'lifetime'].includes(body.tier)) {
      return new Response(
        JSON.stringify({ error: 'Invalid tier' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Get user profile
    const { data: profile } = await supabase
      .from('profiles')
      .select('email')
      .eq('id', userId)
      .single();

    // Get or create Stripe customer
    const { data: subscription } = await supabase
      .from('subscriptions')
      .select('stripe_customer_id')
      .eq('user_id', userId)
      .single();

    let customerId = subscription?.stripe_customer_id;

    if (!customerId) {
      const customer = await stripe.customers.create({
        email: profile?.email,
        metadata: { user_id: userId },
      });
      customerId = customer.id;

      // Update subscription with customer ID
      await getSupabaseServiceClient()
        .from('subscriptions')
        .update({ stripe_customer_id: customerId })
        .eq('user_id', userId);
    }

    // Get price IDs from environment
    const priceIds: Record<string, string | undefined> = {
      monthly: Deno.env.get('STRIPE_MONTHLY_PRICE_ID') || Deno.env.get('STRIPE_STARTER_PRICE_ID') || Deno.env.get('STRIPE_PRICE_ID_STARTER'),
      yearly: Deno.env.get('STRIPE_YEARLY_PRICE_ID') || Deno.env.get('STRIPE_PRO_PRICE_ID') || Deno.env.get('STRIPE_PRICE_ID_PRO'),
      starter: Deno.env.get('STRIPE_STARTER_PRICE_ID') || Deno.env.get('STRIPE_PRICE_ID_STARTER'),
      pro: Deno.env.get('STRIPE_PRO_PRICE_ID') || Deno.env.get('STRIPE_PRICE_ID_PRO'),
      lifetime: Deno.env.get('STRIPE_LIFETIME_PRICE_ID') || Deno.env.get('STRIPE_PRICE_ID_LIFETIME'),
    };

    const priceId = priceIds[body.tier];

    if (!priceId) {
      return new Response(
        JSON.stringify({ error: 'Price ID not configured' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Create Checkout session
    const mode = body.tier === 'lifetime' ? 'payment' : 'subscription';
    
    const session = await stripe.checkout.sessions.create({
      customer: customerId,
      mode,
      line_items: [{ price: priceId, quantity: 1 }],
      success_url: `${Deno.env.get('APP_URL') || 'riff://'}?checkout=success`,
      cancel_url: `${Deno.env.get('APP_URL') || 'riff://'}?checkout=cancel`,
      metadata: {
        user_id: userId,
        tier: body.tier,
      },
    });

    return new Response(
      JSON.stringify({ url: session.url, session_id: session.id }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Error creating checkout:', error);
    return new Response(
      JSON.stringify({ error: 'Internal server error', message: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
