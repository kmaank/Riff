// Shared tier limits and features configuration
// Used by all Edge Functions for consistent quota enforcement

export interface TierLimits {
  riffs_limit: number | null;   // null = unlimited
  seconds_limit: number | null;  // null = unlimited
  all_styles: boolean;
  custom_prompts: boolean;
  byok: boolean;                 // Bring Your Own Key
  priority: boolean;
}

export const TIER_LIMITS: Record<string, TierLimits> = {
  free: {
    riffs_limit: 100,
    seconds_limit: null,  // Unlimited recording time
    all_styles: false,    // Only clean + casual
    custom_prompts: false,
    byok: true,           // Must provide own API key
    priority: false,
  },
  starter: {
    riffs_limit: 500,
    seconds_limit: 7200,  // 2 hours (in seconds)
    all_styles: true,
    custom_prompts: false,
    byok: false,          // Riff-managed key
    priority: false,
  },
  pro: {
    riffs_limit: null,    // Unlimited
    seconds_limit: null,  // Unlimited
    all_styles: true,
    custom_prompts: true,
    byok: false,
    priority: true,
  },
  lifetime: {
    riffs_limit: null,    // Unlimited
    seconds_limit: null,  // Unlimited
    all_styles: true,
    custom_prompts: true,
    byok: false,
    priority: true,
  },
};

export function getTierFeatures(tier: string): TierLimits {
  return TIER_LIMITS[tier] || TIER_LIMITS.free;
}

// Check if user has exceeded quota for their tier
export function checkQuota(
  tier: string,
  riffsUsed: number,
  secondsUsed: number
): { exceeded: boolean; reason?: string } {
  const limits = getTierFeatures(tier);

  // Check riff limit
  if (limits.riffs_limit !== null && riffsUsed >= limits.riffs_limit) {
    return {
      exceeded: true,
      reason: `Monthly riff limit reached (${limits.riffs_limit} riffs)`,
    };
  }

  // Check seconds limit
  if (limits.seconds_limit !== null && secondsUsed >= limits.seconds_limit) {
    const hours = Math.floor(limits.seconds_limit / 3600);
    return {
      exceeded: true,
      reason: `Monthly recording time limit reached (${hours} hours)`,
    };
  }

  return { exceeded: false };
}
