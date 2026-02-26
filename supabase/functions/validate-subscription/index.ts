// Edge Function: validate-subscription
// Returns user's subscription tier, status, quota, and features

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { getSupabaseClient, getUserId, corsHeaders } from '../_shared/clients.ts';
import { getTierFeatures } from '../_shared/tier-limits.ts';

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabase = getSupabaseClient(req);
    const userId = await getUserId(supabase);

    if (!userId) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Get subscription info
    const { data: subscription, error: subError } = await supabase
      .from('subscriptions')
      .select('tier, status, current_period_end')
      .eq('user_id', userId)
      .single();

    if (subError || !subscription) {
      return new Response(
        JSON.stringify({ error: 'Subscription not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Get monthly usage
    const { data: usage, error: usageError } = await supabase
      .from('monthly_usage')
      .select('riffs_used, seconds_used')
      .eq('user_id', userId)
      .single();

    const riffsUsed = usage?.riffs_used || 0;
    const secondsUsed = usage?.seconds_used || 0;

    // Get tier features and limits
    const features = getTierFeatures(subscription.tier);

    // Check if managed key is available (for paid tiers)
    let managedKeyAvailable = false;
    if (!features.byok) {
      const { data: apiKey } = await supabase
        .from('api_keys')
        .select('is_active')
        .eq('user_id', userId)
        .single();
      
      managedKeyAvailable = apiKey?.is_active || false;
    }

    // Build response
    const response = {
      valid: subscription.status === 'active',
      tier: subscription.tier,
      status: subscription.status,
      quota: {
        riffs_limit: features.riffs_limit,
        riffs_used: riffsUsed,
        seconds_limit: features.seconds_limit,
        seconds_used: secondsUsed,
      },
      features: {
        all_styles: features.all_styles,
        custom_prompts: features.custom_prompts,
        priority: features.priority,
        byok: features.byok,
      },
      managed_key_available: managedKeyAvailable,
      current_period_end: subscription.current_period_end,
    };

    return new Response(
      JSON.stringify(response),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Error validating subscription:', error);
    return new Response(
      JSON.stringify({ error: 'Internal server error', message: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
