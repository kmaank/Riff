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
    riffs_limit: null,
    seconds_limit: null,
    all_styles: true,
    custom_prompts: true,
    byok: true,
    priority: false,
  },
  starter: {
    riffs_limit: 500,
    seconds_limit: 7200,
    all_styles: true,
    custom_prompts: false,
    byok: true,
    priority: false,
  },
  monthly: {
    riffs_limit: null,
    seconds_limit: null,
    all_styles: true,
    custom_prompts: true,
    byok: true,
    priority: true,
  },
  yearly: {
    riffs_limit: null,
    seconds_limit: null,
    all_styles: true,
    custom_prompts: true,
    byok: true,
    priority: true,
  },
  pro: {
    riffs_limit: null,    // Unlimited
    seconds_limit: null,  // Unlimited
    all_styles: true,
    custom_prompts: true,
    byok: true,
    priority: true,
  },
  lifetime: {
    riffs_limit: null,    // Unlimited
    seconds_limit: null,  // Unlimited
    all_styles: true,
    custom_prompts: true,
    byok: true,
    priority: true,
  },
};

export function getTierFeatures(tier: string): TierLimits {
  return TIER_LIMITS[tier] || TIER_LIMITS.free;
}

/** Alias used by proxy Edge Functions */
export function getTierConfig(tier: string): TierLimits {
  return getTierFeatures(tier);
}

const FREE_STYLES = new Set(["clean", "casual"]);

export function isStyleAllowed(tier: string, style: string): boolean {
  const features = getTierFeatures(tier);
  if (features.all_styles) {
    return true;
  }
  return FREE_STYLES.has(style);
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
