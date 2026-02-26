"""
Subscription tier limits and features configuration
Shared source of truth for quota enforcement (mirrors Edge Functions)
"""

from typing import Optional, Dict, Any

class TierLimits:
    """Tier limits and features"""
    def __init__(
        self,
        riffs_limit: Optional[int],
        seconds_limit: Optional[int],
        all_styles: bool,
        custom_prompts: bool,
        byok: bool,
        priority: bool
    ):
        self.riffs_limit = riffs_limit
        self.seconds_limit = seconds_limit
        self.all_styles = all_styles
        self.custom_prompts = custom_prompts
        self.byok = byok
        self.priority = priority

# Tier definitions
TIER_LIMITS: Dict[str, TierLimits] = {
    "free": TierLimits(
        riffs_limit=100,
        seconds_limit=None,  # Unlimited recording time
        all_styles=False,    # Only clean + casual
        custom_prompts=False,
        byok=True,           # Bring Your Own Key
        priority=False
    ),
    "starter": TierLimits(
        riffs_limit=500,
        seconds_limit=7200,  # 2 hours (in seconds)
        all_styles=True,
        custom_prompts=False,
        byok=False,          # Riff-managed key
        priority=False
    ),
    "pro": TierLimits(
        riffs_limit=None,    # Unlimited
        seconds_limit=None,  # Unlimited
        all_styles=True,
        custom_prompts=True,
        byok=False,
        priority=True
    ),
    "lifetime": TierLimits(
        riffs_limit=None,    # Unlimited
        seconds_limit=None,  # Unlimited
        all_styles=True,
        custom_prompts=True,
        byok=False,
        priority=True
    ),
}

def get_tier_features(tier: str) -> TierLimits:
    """Get features for a given tier"""
    return TIER_LIMITS.get(tier, TIER_LIMITS["free"])
