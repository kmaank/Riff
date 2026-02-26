/**
 * validate-subscription Edge Function
 * Returns subscription status, tier, quota, and features
 * Called on app startup and periodically (every 24h)
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { getSupabaseServiceClient } from "../_shared/clients.ts";
import {
  authenticateUser,
  corsHeaders,
  handleCors,
  jsonResponse,
  errorResponse,
} from "../_shared/auth.ts";
import {
  getTierConfig,
  checkQuota,
} from "../_shared/tier-limits.ts";
import type {
  Subscription,
  MonthlyUsage,
  ValidateSubscriptionResponse,
} from "../_shared/types.ts";

serve(async (req) => {
  // Handle CORS preflight
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  try {
    // Authenticate user
    const user = await authenticateUser(req);
    const userId = user.id;

    // Get Supabase service client
    const supabase = getSupabaseServiceClient();

    // Fetch subscription
    const { data: subscription, error: subError } = await supabase
      .from("subscriptions")
      .select("*")
      .eq("user_id", userId)
      .single<Subscription>();

    if (subError || !subscription) {
      return errorResponse("Subscription not found", 404, "subscription_not_found");
    }

    // Fetch monthly usage
    const { data: usageData, error: usageError } = await supabase
      .from("monthly_usage")
      .select("*")
      .eq("user_id", userId)
      .single<MonthlyUsage>();

    // Default to zero usage if no data
    const riffsUsed = usageData?.riffs_used || 0;
    const secondsUsed = usageData?.seconds_used || 0;

    // Get tier config
    const tierConfig = getTierConfig(subscription.tier);

    // Check if subscription is valid
    const isValid =
      subscription.status === "active" &&
      !checkQuota(subscription.tier, riffsUsed, secondsUsed).exceeded;

    // Build response
    const response: ValidateSubscriptionResponse = {
      valid: isValid,
      tier: subscription.tier,
      status: subscription.status,
      quota: {
        riffs_limit: tierConfig.riffs_limit,
        riffs_used: riffsUsed,
        seconds_limit: tierConfig.seconds_limit,
        seconds_used: secondsUsed,
      },
      features: {
        all_styles: tierConfig.all_styles,
        custom_prompts: tierConfig.custom_prompts,
        priority: tierConfig.priority,
        byok: tierConfig.byok,
      },
      managed_key_available: !tierConfig.byok,
    };

    return jsonResponse(response);
  } catch (error: any) {
    console.error("validate-subscription error:", error);
    return errorResponse(error.message || "Internal server error", 500);
  }
});
