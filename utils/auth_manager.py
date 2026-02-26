"""
Authentication Manager for Riff
Handles Supabase authentication, subscription validation, quota enforcement, and usage logging
"""

import json
import os
import time
from datetime import datetime, timedelta
from typing import Optional, Tuple, Dict, Any
import platform

try:
    import httpx
    import jwt
    import keyring
except ImportError:
    print("Warning: auth dependencies not installed. Run: pip install httpx PyJWT keyring")
    httpx = None
    jwt = None
    keyring = None

from utils.subscription_config import (
    check_quota,
    get_tier_config,
    is_byok_tier,
    is_managed_key_tier,
)
from utils.request_signer import create_signed_headers


class AuthManager:
    """
    Manages authentication, subscription validation, and quota enforcement.
    """

    KEYRING_SERVICE = "com.riff.app"
    KEYRING_ACCESS_TOKEN = "access_token"
    KEYRING_REFRESH_TOKEN = "refresh_token"
    KEYRING_USER_ID = "user_id"

    def __init__(self, config_manager):
        """
        Initialize AuthManager.

        Args:
            config_manager: ConfigManager instance
        """
        self.config = config_manager
        self.supabase_url = self.config.get("auth.supabase_url", "")
        self.supabase_anon_key = self.config.get("auth.supabase_anon_key", "")

        # Cache file for offline mode
        self.cache_path = os.path.join(
            os.path.dirname(self.config.config_path),
            "auth_cache.json"
        )

        # Auth state file for IPC with Swift UI
        self.auth_state_path = os.path.join(
            os.path.dirname(self.config.config_path),
            "auth_state.json"
        )

        # HTTP client
        self.client = httpx.Client(timeout=30.0) if httpx else None

        # In-memory cache
        self._subscription_cache = None
        self._last_validated = 0

    # ============================================
    # Properties
    # ============================================

    @property
    def is_authenticated(self) -> bool:
        """Check if user is authenticated (has valid cached tokens)."""
        try:
            access_token = self._get_access_token()
            if not access_token:
                return False

            # Try to decode token (basic validation)
            if jwt:
                try:
                    jwt.decode(access_token, options={"verify_signature": False})
                    return True
                except:
                    return False

            # If PyJWT not available, just check if token exists
            return True
        except:
            return False

    @property
    def user_id(self) -> Optional[str]:
        """Get current user's ID."""
        return self._get_user_id()

    # ============================================
    # Authentication Methods
    # ============================================

    def login(self, email: str, password: str) -> Tuple[bool, str]:
        """
        Login with email and password.

        Returns:
            (success: bool, message: str)
        """
        if not self.client:
            return False, "HTTP client not available"

        try:
            response = self.client.post(
                f"{self.supabase_url}/auth/v1/token?grant_type=password",
                json={"email": email, "password": password},
                headers={
                    "apikey": self.supabase_anon_key,
                    "Content-Type": "application/json",
                }
            )

            if response.status_code == 200:
                data = response.json()
                self._store_tokens(
                    data["access_token"],
                    data["refresh_token"],
                    data["user"]["id"]
                )
                self._write_auth_state(authenticated=True, email=email, user_id=data["user"]["id"])
                return True, "Login successful"
            else:
                error = response.json().get("error_description", "Login failed")
                return False, error

        except Exception as e:
            return False, f"Login error: {str(e)}"

    def signup(self, email: str, password: str) -> Tuple[bool, str]:
        """
        Sign up with email and password.

        Returns:
            (success: bool, message: str)
        """
        if not self.client:
            return False, "HTTP client not available"

        try:
            response = self.client.post(
                f"{self.supabase_url}/auth/v1/signup",
                json={"email": email, "password": password},
                headers={
                    "apikey": self.supabase_anon_key,
                    "Content-Type": "application/json",
                }
            )

            if response.status_code in [200, 201]:
                data = response.json()
                # Check if email confirmation is required
                if data.get("user") and data.get("access_token"):
                    self._store_tokens(
                        data["access_token"],
                        data["refresh_token"],
                        data["user"]["id"]
                    )
                    self._write_auth_state(authenticated=True, email=email, user_id=data["user"]["id"])
                    return True, "Signup successful"
                else:
                    return True, "Signup successful. Please check your email to confirm."
            else:
                error = response.json().get("error_description", "Signup failed")
                return False, error

        except Exception as e:
            return False, f"Signup error: {str(e)}"

    def logout(self):
        """Logout and clear all stored auth data."""
        # Clear tokens from keychain
        if keyring:
            try:
                keyring.delete_password(self.KEYRING_SERVICE, self.KEYRING_ACCESS_TOKEN)
                keyring.delete_password(self.KEYRING_SERVICE, self.KEYRING_REFRESH_TOKEN)
                keyring.delete_password(self.KEYRING_SERVICE, self.KEYRING_USER_ID)
            except:
                pass

        # Clear cache
        if os.path.exists(self.cache_path):
            os.remove(self.cache_path)

        # Update auth state
        self._write_auth_state(authenticated=False)

        self._subscription_cache = None
        self._last_validated = 0

    def refresh_token(self) -> bool:
        """
        Refresh access token using refresh token.

        Returns:
            True if refresh succeeded, False otherwise
        """
        refresh_token = self._get_refresh_token()
        if not refresh_token or not self.client:
            return False

        try:
            response = self.client.post(
                f"{self.supabase_url}/auth/v1/token?grant_type=refresh_token",
                json={"refresh_token": refresh_token},
                headers={
                    "apikey": self.supabase_anon_key,
                    "Content-Type": "application/json",
                }
            )

            if response.status_code == 200:
                data = response.json()
                self._store_tokens(
                    data["access_token"],
                    data["refresh_token"],
                    data["user"]["id"]
                )
                return True
            else:
                print(f"Token refresh failed: {response.status_code}")
                return False

        except Exception as e:
            print(f"Token refresh error: {e}")
            return False

    # ============================================
    # Subscription & Quota Methods
    # ============================================

    def validate_subscription(self, force: bool = False) -> Optional[Dict[str, Any]]:
        """
        Validate subscription status and quota.

        Args:
            force: Force online validation (ignore cache)

        Returns:
            Subscription data dict or None if failed
        """
        # Use cache if available and recent (< 24 hours)
        if not force and self._subscription_cache and self._last_validated:
            age = time.time() - self._last_validated
            if age < 86400:  # 24 hours
                return self._subscription_cache

        # Try online validation
        access_token = self._get_access_token()
        if not access_token or not self.client:
            return self._load_cached_subscription()

        try:
            response = self.client.post(
                f"{self.supabase_url}/functions/v1/validate-subscription",
                headers={
                    "Authorization": f"Bearer {access_token}",
                    "apikey": self.supabase_anon_key,
                }
            )

            if response.status_code == 200:
                data = response.json()
                self._subscription_cache = data
                self._last_validated = time.time()
                self._save_cached_subscription(data)
                return data
            elif response.status_code == 401:
                # Token expired, try refresh
                if self.refresh_token():
                    return self.validate_subscription(force=True)
                else:
                    return self._load_cached_subscription()
            else:
                print(f"Subscription validation failed: {response.status_code}")
                return self._load_cached_subscription()

        except Exception as e:
            print(f"Subscription validation error: {e}")
            return self._load_cached_subscription()

    def can_riff(self) -> Tuple[bool, str]:
        """
        Check if user can perform a riff (quota enforcement).

        Returns:
            (allowed: bool, reason: str)
        """
        # Check authentication
        if not self.is_authenticated:
            return False, "Not authenticated. Please login."

        # Validate subscription
        subscription = self.validate_subscription()

        if not subscription:
            # Offline fallback - check cache age
            cache_age = time.time() - self._last_validated
            if cache_age > 604800:  # 7 days
                return False, "Unable to validate subscription. Please connect to internet."
            # Within 7-day grace period, allow with warning
            return True, ""

        # Check if subscription is valid
        if not subscription.get("valid", False):
            status = subscription.get("status", "unknown")
            if status == "past_due":
                return False, "Payment failed. Please update your payment method."
            elif status == "canceled":
                return False, "Subscription canceled. Please renew."
            elif status == "expired":
                return False, "Subscription expired. Please upgrade."
            else:
                return False, "Subscription not active."

        # Check quota
        tier = subscription.get("tier", "free")
        quota = subscription.get("quota", {})
        riffs_used = quota.get("riffs_used", 0)
        seconds_used = quota.get("seconds_used", 0)

        quota_check = check_quota(tier, riffs_used, seconds_used)
        if quota_check["exceeded"]:
            return False, quota_check["reason"]

        return True, ""

    def log_usage(
        self,
        word_count: int,
        recording_seconds: float,
        style: str,
        script_mode: str
    ) -> bool:
        """
        Log riff usage to backend.

        Args:
            word_count: Number of words transcribed
            recording_seconds: Recording duration in seconds
            style: Style used
            script_mode: Script mode used

        Returns:
            True if logged successfully, False otherwise
        """
        access_token = self._get_access_token()
        user_id = self.user_id

        if not access_token or not user_id or not self.client:
            return False

        try:
            # Create signed headers
            headers = create_signed_headers(user_id, "/log-usage", access_token)
            headers["apikey"] = self.supabase_anon_key

            # Get device ID
            device_id = self._get_device_id()

            response = self.client.post(
                f"{self.supabase_url}/functions/v1/log-usage",
                json={
                    "word_count": word_count,
                    "recording_seconds": recording_seconds,
                    "style": style,
                    "script_mode": script_mode,
                    "device_id": device_id,
                },
                headers=headers
            )

            if response.status_code == 200:
                # Update cached quota
                data = response.json()
                if self._subscription_cache and data.get("quota"):
                    self._subscription_cache["quota"]["riffs_used"] = data["quota"]["riffs_used"]
                    self._subscription_cache["quota"]["seconds_used"] = data["quota"]["seconds_used"]
                return True
            else:
                print(f"Usage logging failed: {response.status_code}")
                return False

        except Exception as e:
            print(f"Usage logging error: {e}")
            return False

    def get_tier(self) -> str:
        """Get current subscription tier."""
        subscription = self.validate_subscription()
        if subscription:
            return subscription.get("tier", "free")
        return "free"

    def get_features(self) -> Dict[str, bool]:
        """Get current subscription features."""
        subscription = self.validate_subscription()
        if subscription:
            return subscription.get("features", {})
        return {
            "all_styles": False,
            "custom_prompts": False,
            "priority": False,
            "byok": True,
        }

    # ============================================
    # API Key Methods
    # ============================================

    def get_effective_api_key(self) -> Optional[str]:
        """
        Get the effective API key to use (BYOK or proxy).

        Returns:
            API key for BYOK users, None for managed key users (use proxy)
        """
        tier = self.get_tier()

        if is_byok_tier(tier):
            # Free tier - use user's own key
            return self.config.get("api.api_key")
        else:
            # Paid tiers - use proxy (no key needed)
            return None

    def should_use_proxy(self) -> bool:
        """Check if API requests should go through proxy."""
        tier = self.get_tier()
        return is_managed_key_tier(tier)

    # ============================================
    # Device Registration
    # ============================================

    def register_device(self) -> Tuple[bool, str]:
        """
        Register current device with backend.

        Returns:
            (success: bool, message: str)
        """
        access_token = self._get_access_token()
        user_id = self.user_id

        if not access_token or not user_id or not self.client:
            return False, "Not authenticated"

        try:
            device_id = self._get_device_id()
            device_info = self._get_device_info()

            response = self.client.post(
                f"{self.supabase_url}/functions/v1/register-device",
                json={
                    "device_id": device_id,
                    **device_info,
                },
                headers={
                    "Authorization": f"Bearer {access_token}",
                    "apikey": self.supabase_anon_key,
                    "Content-Type": "application/json",
                }
            )

            if response.status_code == 200:
                data = response.json()
                if data.get("success"):
                    return True, data.get("message", "Device registered")
                else:
                    return False, data.get("message", "Device registration failed")
            else:
                return False, f"Registration failed: {response.status_code}"

        except Exception as e:
            return False, f"Registration error: {e}"

    # ============================================
    # Private Helper Methods
    # ============================================

    def _get_access_token(self) -> Optional[str]:
        """Get access token from keychain."""
        if not keyring:
            return None
        try:
            return keyring.get_password(self.KEYRING_SERVICE, self.KEYRING_ACCESS_TOKEN)
        except:
            return None

    def _get_refresh_token(self) -> Optional[str]:
        """Get refresh token from keychain."""
        if not keyring:
            return None
        try:
            return keyring.get_password(self.KEYRING_SERVICE, self.KEYRING_REFRESH_TOKEN)
        except:
            return None

    def _get_user_id(self) -> Optional[str]:
        """Get user ID from keychain."""
        if not keyring:
            return None
        try:
            return keyring.get_password(self.KEYRING_SERVICE, self.KEYRING_USER_ID)
        except:
            return None

    def _store_tokens(self, access_token: str, refresh_token: str, user_id: str):
        """Store tokens in keychain."""
        if not keyring:
            return

        try:
            keyring.set_password(self.KEYRING_SERVICE, self.KEYRING_ACCESS_TOKEN, access_token)
            keyring.set_password(self.KEYRING_SERVICE, self.KEYRING_REFRESH_TOKEN, refresh_token)
            keyring.set_password(self.KEYRING_SERVICE, self.KEYRING_USER_ID, user_id)
        except Exception as e:
            print(f"Failed to store tokens in keychain: {e}")

    def _save_cached_subscription(self, data: Dict[str, Any]):
        """Save subscription data to cache file."""
        try:
            cache = {
                "subscription": data,
                "timestamp": time.time(),
            }
            with open(self.cache_path, 'w') as f:
                json.dump(cache, f, indent=2)
        except Exception as e:
            print(f"Failed to save subscription cache: {e}")

    def _load_cached_subscription(self) -> Optional[Dict[str, Any]]:
        """Load subscription data from cache file."""
        try:
            if not os.path.exists(self.cache_path):
                return None

            with open(self.cache_path, 'r') as f:
                cache = json.load(f)

            # Check cache age
            timestamp = cache.get("timestamp", 0)
            age = time.time() - timestamp

            if age > 1209600:  # 14 days - too old, reject
                return None

            self._subscription_cache = cache.get("subscription")
            self._last_validated = timestamp

            return self._subscription_cache
        except:
            return None

    def _write_auth_state(self, authenticated: bool, email: str = "", user_id: str = ""):
        """Write auth state to file for IPC with Swift UI."""
        try:
            state = {
                "authenticated": authenticated,
                "email": email,
                "user_id": user_id,
                "timestamp": datetime.now().isoformat(),
            }
            with open(self.auth_state_path, 'w') as f:
                json.dump(state, f, indent=2)
        except Exception as e:
            print(f"Failed to write auth state: {e}")

    def _get_device_id(self) -> str:
        """Get or generate device ID."""
        # Use MAC address or machine ID
        import uuid
        device_id_key = "device_id"

        # Try to get from config
        device_id = self.config.get(f"device.{device_id_key}")
        if not device_id:
            # Generate new one
            device_id = str(uuid.uuid4())
            self.config.set(f"device.{device_id_key}", device_id)

        return device_id

    def _get_device_info(self) -> Dict[str, str]:
        """Get device information."""
        system = platform.system().lower()
        device_type = "mac" if system == "darwin" else "windows" if system == "windows" else "unknown"

        return {
            "device_name": platform.node(),
            "device_type": device_type,
            "os_version": platform.release(),
            "app_version": "1.0.0",  # TODO: Get from actual version
        }
