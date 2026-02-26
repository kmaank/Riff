/**
 * Tier Limits and Feature Definitions
 * Single source of truth for subscription tiers
 * Must match Python's utils/subscription_config.py
 */

export interface TierFeatures {
  all_styles: boolean;
  custom_prompts: boolean;
  priority: boolean;
  byok: boolean; // Bring Your Own Key
}

export interface TierLimits {
  riffs_limit: number | null; // null = unlimited
  seconds_limit: number | null; // null = unlimited
}

export interface TierConfig extends TierLimits, TierFeatures {}

/**
 * Tier definitions
 */
export const TIER_CONFIGS: Record<string, TierConfig> = {
  free: {
    riffs_limit: 100,
    seconds_limit: null,
    all_styles: false,
    custom_prompts: false,
    priority: false,
    byok: true,
  },
  starter: {
    riffs_limit: 500,
    seconds_limit: 7200, // 2 hours = 7200 seconds
    all_styles: true,
    custom_prompts: false,
    priority: false,
    byok: false,
  },
  pro: {
    riffs_limit: null, // Unlimited
    seconds_limit: null, // Unlimited
    all_styles: true,
    custom_prompts: true,
    priority: true,
    byok: false,
  },
  lifetime: {
    riffs_limit: null, // Unlimited
    seconds_limit: null, // Unlimited
    all_styles: true,
    custom_prompts: true,
    priority: true,
    byok: false,
  },
};

/**
 * Get tier configuration
 */
export function getTierConfig(tier: string): TierConfig {
  return TIER_CONFIGS[tier] || TIER_CONFIGS.free;
}

/**
 * Get tier limits only
 */
export function getTierLimits(tier: string): TierLimits {
  const config = getTierConfig(tier);
  return {
    riffs_limit: config.riffs_limit,
    seconds_limit: config.seconds_limit,
  };
}

/**
 * Get tier features only
 */
export function getTierFeatures(tier: string): TierFeatures {
  const config = getTierConfig(tier);
  return {
    all_styles: config.all_styles,
    custom_prompts: config.custom_prompts,
    priority: config.priority,
    byok: config.byok,
  };
}

/**
 * Check if user has exceeded quota
 * @returns { exceeded: boolean, reason?: string }
 */
export function checkQuota(
  tier: string,
  riffsUsed: number,
  secondsUsed: number
): { exceeded: boolean; reason?: string } {
  const limits = getTierLimits(tier);

  // Check riffs limit
  if (limits.riffs_limit !== null && riffsUsed >= limits.riffs_limit) {
    return {
      exceeded: true,
      reason: `Monthly riff limit reached (${limits.riffs_limit} riffs)`,
    };
  }

  // Check seconds limit
  if (limits.seconds_limit !== null && secondsUsed >= limits.seconds_limit) {
    const hoursLimit = Math.floor(limits.seconds_limit / 3600);
    return {
      exceeded: true,
      reason: `Monthly recording time limit reached (${hoursLimit} hours)`,
    };
  }

  return { exceeded: false };
}

/**
 * Get allowed styles for tier
 */
export function getAllowedStyles(tier: string): string[] {
  const features = getTierFeatures(tier);

  if (features.all_styles) {
    return ["clean", "casual", "formal", "riff"];
  } else {
    // Free tier: clean and casual only
    return ["clean", "casual"];
  }
}

/**
 * Check if style is allowed for tier
 */
export function isStyleAllowed(tier: string, style: string): boolean {
  return getAllowedStyles(tier).includes(style);
}

/**
 * Tier display names
 */
export const TIER_DISPLAY_NAMES: Record<string, string> = {
  free: "Free (BYOK)",
  starter: "Starter",
  pro: "Pro",
  lifetime: "Lifetime",
};

/**
 * Tier prices (for display)
 */
export const TIER_PRICES: Record<string, string> = {
  free: "$0",
  starter: "$9.99/mo",
  pro: "$19.99/mo",
  lifetime: "$149",
};
