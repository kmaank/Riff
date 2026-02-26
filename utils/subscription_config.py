"""
Subscription Tier Configuration
Single source of truth for tier limits and features
Must match TypeScript supabase/functions/_shared/tier-limits.ts
"""

from typing import Optional, Dict, List, Any

# Tier limit and feature definitions
TIER_LIMITS = {
    "free": {
        "riffs_limit": 100,
        "seconds_limit": None,  # Unlimited
        "all_styles": False,
        "custom_prompts": False,
        "priority": False,
        "byok": True,  # Bring Your Own Key
    },
    "starter": {
        "riffs_limit": 500,
        "seconds_limit": 7200,  # 2 hours = 7200 seconds
        "all_styles": True,
        "custom_prompts": False,
        "priority": False,
        "byok": False,
    },
    "pro": {
        "riffs_limit": None,  # Unlimited
        "seconds_limit": None,  # Unlimited
        "all_styles": True,
        "custom_prompts": True,
        "priority": True,
        "byok": False,
    },
    "lifetime": {
        "riffs_limit": None,  # Unlimited
        "seconds_limit": None,  # Unlimited
        "all_styles": True,
        "custom_prompts": True,
        "priority": True,
        "byok": False,
    },
}

# Tier display names
TIER_DISPLAY_NAMES = {
    "free": "Free (BYOK)",
    "starter": "Starter",
    "pro": "Pro",
    "lifetime": "Lifetime",
}

# Tier prices (for display)
TIER_PRICES = {
    "free": "$0",
    "starter": "$9.99/mo",
    "pro": "$19.99/mo",
    "lifetime": "$149",
}


def get_tier_config(tier: str) -> Dict[str, Any]:
    """Get complete tier configuration."""
    return TIER_LIMITS.get(tier, TIER_LIMITS["free"])


def get_tier_limits(tier: str) -> Dict[str, Optional[int]]:
    """Get tier limits only (riffs and seconds)."""
    config = get_tier_config(tier)
    return {
        "riffs_limit": config["riffs_limit"],
        "seconds_limit": config["seconds_limit"],
    }


def get_tier_features(tier: str) -> Dict[str, bool]:
    """Get tier features only."""
    config = get_tier_config(tier)
    return {
        "all_styles": config["all_styles"],
        "custom_prompts": config["custom_prompts"],
        "priority": config["priority"],
        "byok": config["byok"],
    }


def check_quota(tier: str, riffs_used: int, seconds_used: float) -> Dict[str, Any]:
    """
    Check if quota is exceeded.

    Returns:
        {
            "exceeded": bool,
            "reason": str (if exceeded)
        }
    """
    limits = get_tier_limits(tier)

    # Check riffs limit
    if limits["riffs_limit"] is not None and riffs_used >= limits["riffs_limit"]:
        return {
            "exceeded": True,
            "reason": f"Monthly riff limit reached ({limits['riffs_limit']} riffs)",
        }

    # Check seconds limit
    if limits["seconds_limit"] is not None and seconds_used >= limits["seconds_limit"]:
        hours_limit = limits["seconds_limit"] // 3600
        return {
            "exceeded": True,
            "reason": f"Monthly recording time limit reached ({hours_limit} hours)",
        }

    return {"exceeded": False}


def get_allowed_styles(tier: str) -> List[str]:
    """Get list of allowed styles for tier."""
    features = get_tier_features(tier)

    if features["all_styles"]:
        return ["clean", "casual", "formal", "riff"]
    else:
        # Free tier: clean and casual only
        return ["clean", "casual"]


def is_style_allowed(tier: str, style: str) -> bool:
    """Check if style is allowed for tier."""
    return style in get_allowed_styles(tier)


def is_byok_tier(tier: str) -> bool:
    """Check if tier uses Bring Your Own Key."""
    features = get_tier_features(tier)
    return features["byok"]


def is_managed_key_tier(tier: str) -> bool:
    """Check if tier uses managed API key (proxy)."""
    return not is_byok_tier(tier)


def get_tier_display_name(tier: str) -> str:
    """Get human-readable tier name."""
    return TIER_DISPLAY_NAMES.get(tier, tier.capitalize())


def get_tier_price(tier: str) -> str:
    """Get tier price string."""
    return TIER_PRICES.get(tier, "")


if __name__ == "__main__":
    # Test tier configs
    print("Tier Configurations:")
    for tier in ["free", "starter", "pro", "lifetime"]:
        print(f"\n{tier.upper()}:")
        print(f"  Display: {get_tier_display_name(tier)}")
        print(f"  Price: {get_tier_price(tier)}")
        print(f"  Limits: {get_tier_limits(tier)}")
        print(f"  Features: {get_tier_features(tier)}")
        print(f"  Allowed Styles: {get_allowed_styles(tier)}")
        print(f"  BYOK: {is_byok_tier(tier)}")
