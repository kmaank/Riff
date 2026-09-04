"""
Authentication Manager for Riff
Handles Supabase authentication, subscription validation, quota enforcement, and usage logging
"""

import json
import logging
import platform
from urllib.parse import parse_qs, quote, urlparse
import httpx
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional, Dict, Any, Tuple
import keyring

from utils.subscription_config import get_tier_features

logger = logging.getLogger(__name__)

AUTH_EMAIL_REDIRECT = "riff://auth/callback"
OAUTH_REDIRECT = "riff://oauth/callback"

class AuthManager:
    """Manages authentication, subscription, and quota for Riff"""

    def __init__(self, config_manager):
        self.config = config_manager
        self.support_dir = Path.home() / "Library" / "Application Support" / "Riff"
        self.support_dir.mkdir(parents=True, exist_ok=True)

        # File paths
        self.auth_state_path = self.support_dir / "auth_state.json"
        self.auth_cache_path = self.support_dir / "auth_cache.json"

        # Supabase configuration
        self.supabase_url = self.config.config.get("auth", {}).get("supabase_url", "")
        self.supabase_anon_key = self.config.config.get("auth", {}).get("supabase_anon_key", "")

        logger.info(f"[Auth] Supabase URL: {self.supabase_url}")
        if "your-project" in self.supabase_url or "your-anon-key" in self.supabase_anon_key:
            logger.error("[Auth] Supabase credentials are still placeholder defaults! Auth will not work.")
        else:
            logger.info(f"[Auth] Supabase anon key: {self.supabase_anon_key[:10]}...")

        # Auth state from IPC (set by Swift UI via auth_state.json)
        self._auth_email: str = ""
        self._auth_user_id: str = ""
        self._auth_authenticated: bool = False

        # Cached state
        self._cached_subscription: Optional[Dict[str, Any]] = None
        self._last_validated: Optional[datetime] = None
        self._access_token: Optional[str] = None
        self._refresh_token: Optional[str] = None

        # Load cached state
        self._load_cached_state()
        self._load_auth_state()

        logger.info(f"[Auth] Init complete. authenticated={self.is_authenticated}, "
                     f"email={self._auth_email}, has_cached_sub={self._cached_subscription is not None}")
    
    # ========================================================================
    # Authentication Methods
    # ========================================================================
    
    @property
    def is_authenticated(self) -> bool:
        """Check if user is authenticated (has valid tokens)"""
        # Check for stored tokens
        access_token = self._get_access_token()
        return access_token is not None
    
    def _get_access_token(self) -> Optional[str]:
        """Get access token from keychain or memory"""
        # Respect auth_state.json from Swift - if user logged out, clear cache
        try:
            if self.auth_state_path.exists():
                with open(self.auth_state_path, 'r') as f:
                    state = json.load(f)
                if not state.get("authenticated", False):
                    self._access_token = None
                    self._refresh_token = None
                    return None
        except Exception:
            pass

        if self._access_token:
            logger.debug("[Auth] Using cached in-memory access token")
            return self._access_token

        try:
            token = keyring.get_password("riff", "supabase_access_token")
            if token:
                self._access_token = token
                logger.info(f"[Auth] Access token loaded from keychain ({token[:10]}...)")
            else:
                logger.warning("[Auth] No access token found in keychain")
            return token
        except Exception as e:
            logger.error(f"[Auth] Error reading access token from keychain: {e}")
            return None
    
    def _get_refresh_token(self) -> Optional[str]:
        """Get refresh token from keychain"""
        if self._refresh_token:
            return self._refresh_token
        
        try:
            token = keyring.get_password("riff", "supabase_refresh_token")
            if token:
                self._refresh_token = token
            return token
        except Exception as e:
            logger.error(f"Error getting refresh token: {e}")
            return None
    
    def _store_tokens(self, access_token: str, refresh_token: str):
        """Store tokens securely in macOS Keychain"""
        try:
            keyring.set_password("riff", "supabase_access_token", access_token)
            keyring.set_password("riff", "supabase_refresh_token", refresh_token)
            self._access_token = access_token
            self._refresh_token = refresh_token
            logger.info("Tokens stored securely")
        except Exception as e:
            logger.error(f"Error storing tokens: {e}")
    
    def login(self, email: str, password: str) -> Dict[str, Any]:
        """Login with email and password"""
        logger.info(f"[Auth] login() called for email: {email}")

        if "your-project" in self.supabase_url:
            logger.error("[Auth] Cannot login — Supabase URL is a placeholder")
            return {"success": False, "error": "Supabase credentials not configured"}

        url = f"{self.supabase_url}/auth/v1/token?grant_type=password"
        headers = {
            "apikey": self.supabase_anon_key,
            "Authorization": f"Bearer {self.supabase_anon_key}",
            "Content-Type": "application/json"
        }
        data = {"email": email, "password": password}

        logger.info(f"[Auth] POST {url}")

        try:
            response = httpx.post(url, headers=headers, json=data, timeout=15.0)
            logger.info(f"[Auth] Login response status: {response.status_code}")

            if response.status_code != 200:
                error_body = response.text
                logger.error(f"[Auth] Login failed with status {response.status_code}: {error_body}")
                return {"success": False, "error": f"Login failed (HTTP {response.status_code}): {error_body}"}

            response.raise_for_status()

            result = response.json()
            self._store_tokens(result["access_token"], result["refresh_token"])
            self._write_auth_state(True, result["user"]["email"], result["user"]["id"])
            self._auth_authenticated = True
            self._auth_email = result["user"]["email"]
            self._auth_user_id = result["user"]["id"]

            logger.info(f"[Auth] Login successful for {email}, user_id={result['user']['id']}")
            return {"success": True, "user": result["user"]}
        except httpx.TimeoutException as e:
            logger.error(f"[Auth] Login timed out: {e}")
            return {"success": False, "error": "Request timed out — please try again"}
        except httpx.ConnectError as e:
            logger.error(f"[Auth] Login connection error: {e}")
            return {"success": False, "error": f"Cannot connect to server: {e}"}
        except httpx.HTTPError as e:
            logger.error(f"[Auth] Login HTTP error: {e}")
            return {"success": False, "error": str(e)}
        except Exception as e:
            logger.error(f"[Auth] Login unexpected error: {e}", exc_info=True)
            return {"success": False, "error": str(e)}
    
    def signup(self, email: str, password: str) -> Dict[str, Any]:
        """Sign up with email and password"""
        logger.info(f"[Auth] signup() called for email: {email}")

        if "your-project" in self.supabase_url:
            logger.error("[Auth] Cannot signup — Supabase URL is a placeholder")
            return {"success": False, "error": "Supabase credentials not configured"}

        url = f"{self.supabase_url}/auth/v1/signup?redirect_to={quote(AUTH_EMAIL_REDIRECT, safe='')}"
        headers = {
            "apikey": self.supabase_anon_key,
            "Authorization": f"Bearer {self.supabase_anon_key}",
            "Content-Type": "application/json"
        }
        data = {"email": email, "password": password}

        logger.info("[Auth] POST %s", url)

        try:
            response = httpx.post(url, headers=headers, json=data, timeout=30.0)
            logger.info(f"[Auth] Signup response status: {response.status_code}")

            if response.status_code not in (200, 201):
                error_body = response.text
                logger.error(f"[Auth] Signup failed with status {response.status_code}: {error_body}")
                return {"success": False, "error": f"Signup failed (HTTP {response.status_code}): {error_body}"}

            result = response.json()

            # Check if email confirmation is required (no tokens returned)
            access_token = result.get("access_token", "")
            if not access_token:
                logger.info(f"[Auth] Signup successful but email confirmation required for {email}")
                return {"success": True, "confirmation_required": True,
                        "message": f"Check your email! Confirmation link sent to {email}."}

            self._store_tokens(result["access_token"], result["refresh_token"])
            self._write_auth_state(True, result["user"]["email"], result["user"]["id"])
            self._auth_authenticated = True
            self._auth_email = result["user"]["email"]
            self._auth_user_id = result["user"]["id"]

            logger.info(f"[Auth] Signup successful for {email}, user_id={result['user']['id']}")
            return {"success": True, "user": result["user"]}
        except httpx.TimeoutException as e:
            logger.error(f"[Auth] Signup timed out: {e}")
            return {"success": False, "error": "Request timed out — please try again"}
        except httpx.ConnectError as e:
            logger.error(f"[Auth] Signup connection error: {e}")
            return {"success": False, "error": f"Cannot connect to server: {e}"}
        except httpx.HTTPError as e:
            logger.error(f"[Auth] Signup HTTP error: {e}")
            return {"success": False, "error": str(e)}
        except Exception as e:
            logger.error(f"[Auth] Signup unexpected error: {e}", exc_info=True)
            return {"success": False, "error": str(e)}
    
    def logout(self):
        """Logout and clear tokens"""
        try:
            keyring.delete_password("riff", "supabase_access_token")
            keyring.delete_password("riff", "supabase_refresh_token")
            keyring.delete_password("riff", "managed_groq_key")
        except Exception:
            pass
        
        self._access_token = None
        self._refresh_token = None
        self._cached_subscription = None
        self._write_auth_state(False, "", "")
        logger.info("Logged out successfully")
    
    def refresh_token(self) -> bool:
        """Refresh access token using refresh token"""
        logger.info("[Auth] Attempting token refresh")
        refresh_token = self._get_refresh_token()
        if not refresh_token:
            logger.warning("[Auth] No refresh token available — cannot refresh")
            return False

        url = f"{self.supabase_url}/auth/v1/token?grant_type=refresh_token"
        headers = {
            "apikey": self.supabase_anon_key,
            "Authorization": f"Bearer {self.supabase_anon_key}",
            "Content-Type": "application/json"
        }
        data = {"refresh_token": refresh_token}

        try:
            response = httpx.post(url, headers=headers, json=data, timeout=15.0)
            logger.info(f"[Auth] Token refresh response status: {response.status_code}")
            response.raise_for_status()

            result = response.json()
            self._store_tokens(result["access_token"], result["refresh_token"])
            logger.info("[Auth] Token refreshed successfully")
            return True
        except httpx.TimeoutException as e:
            logger.error(f"[Auth] Token refresh timed out: {e}")
            return False
        except httpx.HTTPError as e:
            logger.error(f"[Auth] Token refresh failed: {e}")
            return False
    
    # ========================================================================
    # Subscription & Quota Methods
    # ========================================================================
    
    def validate_subscription(self, force_online: bool = False) -> Dict[str, Any]:
        """
        Validate subscription (online or cached)
        
        Offline strategy:
        - < 7 days old: use cache
        - 7-14 days: try online, fallback to cache with warning
        - > 14 days: require online validation
        """
        # Check cache freshness
        if not force_online and self._cached_subscription and self._last_validated:
            age = datetime.now() - self._last_validated
            
            if age < timedelta(days=7):
                logger.info("Using cached subscription (< 7 days old)")
                return self._cached_subscription
            elif age < timedelta(days=14):
                logger.info("Attempting online validation (cache 7-14 days old)")
                online_result = self._validate_online()
                if online_result:
                    return online_result
                logger.warning("Online validation failed, using stale cache")
                return {**self._cached_subscription, "warning": "Using stale cache (offline)"}
            else:
                logger.warning("Cache too old (> 14 days), requiring online validation")
                return self._validate_online() or {"error": "Subscription validation required (offline)"}
        
        # Force online validation
        return self._validate_online() or self._cached_subscription or {"error": "No subscription found"}
    
    def _validate_online(self) -> Optional[Dict[str, Any]]:
        """Call validate-subscription Edge Function"""
        access_token = self._get_access_token()
        if not access_token:
            logger.error("[Auth] No access token available for subscription validation")
            return None

        url = f"{self.supabase_url}/functions/v1/validate-subscription"
        headers = {
            "Authorization": f"Bearer {access_token}",
            "apikey": self.supabase_anon_key
        }

        logger.info(f"[Auth] POST {url}")

        try:
            response = httpx.post(url, headers=headers, timeout=15.0)
            logger.info(f"[Auth] Subscription validation response status: {response.status_code}")

            if response.status_code == 401:
                logger.warning("[Auth] Token expired (401), attempting refresh...")
                if self.refresh_token():
                    # Retry with new token
                    access_token = self._get_access_token()
                    headers["Authorization"] = f"Bearer {access_token}"
                    response = httpx.post(url, headers=headers, timeout=15.0)
                    logger.info(f"[Auth] Retry response status: {response.status_code}")
                else:
                    logger.error("[Auth] Token refresh failed — user needs to re-login")
                    return None

            response.raise_for_status()

            result = response.json()
            self._cached_subscription = result
            self._last_validated = datetime.now()
            self._save_cache()

            logger.info(f"[Auth] Subscription validated: tier={result.get('tier')}, status={result.get('status')}, "
                        f"riffs_used={result.get('quota', {}).get('riffs_used', 'N/A')}")
            return result
        except httpx.TimeoutException as e:
            logger.error(f"[Auth] Subscription validation timed out: {e}")
            return None
        except httpx.HTTPError as e:
            logger.error(f"[Auth] Subscription validation failed: {e}")
            return None
    
    def can_riff(self) -> Tuple[bool, str]:
        """
        Check if user can create a riff (quota check)
        Returns: (allowed: bool, reason: str)
        """
        if not self.is_authenticated:
            return False, "Not authenticated"
        
        subscription = self.validate_subscription()
        
        if subscription.get("error"):
            return False, subscription["error"]
        
        if subscription.get("status") != "active":
            return False, "Subscription not active"
        
        # Check quota
        quota = subscription.get("quota", {})
        tier = subscription.get("tier", "free")
        features = get_tier_features(tier)
        
        # Check riff limit
        if features.riffs_limit is not None:
            riffs_used = quota.get("riffs_used", 0)
            if riffs_used >= features.riffs_limit:
                return False, f"Monthly riff limit reached ({features.riffs_limit})"
        
        # Check recording time limit
        if features.seconds_limit is not None:
            seconds_used = quota.get("seconds_used", 0)
            if seconds_used >= features.seconds_limit:
                hours = features.seconds_limit / 3600
                return False, f"Monthly recording time limit reached ({hours:.1f} hours)"
        
        return True, "OK"
    
    def get_tier(self) -> str:
        """Get current subscription tier"""
        subscription = self.validate_subscription()
        return subscription.get("tier", "free")
    
    def get_features(self) -> Dict[str, Any]:
        """Get current tier features"""
        subscription = self.validate_subscription()
        return subscription.get("features", {})
    
    # ========================================================================
    # Usage Logging
    # ========================================================================
    
    def log_usage(self, word_count: int, recording_seconds: float, style: str, script_mode: str):
        """Log riff usage to backend"""
        access_token = self._get_access_token()
        if not access_token:
            logger.warning("Cannot log usage: not authenticated")
            return
        
        url = f"{self.supabase_url}/functions/v1/log-usage"
        headers = {
            "Authorization": f"Bearer {access_token}",
            "apikey": self.supabase_anon_key,
            "Content-Type": "application/json"
        }
        data = {
            "word_count": word_count,
            "recording_seconds": recording_seconds,
            "style": style,
            "script_mode": script_mode,
            "device_id": self.config.config.get("device", {}).get("device_id"),
        }
        
        try:
            response = httpx.post(url, headers=headers, json=data, timeout=10.0)
            response.raise_for_status()
            logger.info(f"Usage logged: {word_count} words, {recording_seconds:.1f}s")
        except httpx.HTTPError as e:
            logger.error(f"Failed to log usage: {e}")
    
    # ========================================================================
    # API Key Management
    # ========================================================================
    
    def get_effective_api_key(self) -> Optional[str]:
        """
        Get effective API key based on tier
        - Free tier: user's BYOK key from config
        - Paid tiers: managed key from backend
        """
        tier = self.get_tier()
        features = get_tier_features(tier)
        
        if features.byok:
            # Free tier: use BYOK
            return self.config.config.get("api", {}).get("api_key", "")
        else:
            # Paid tiers: fetch managed key
            return self._fetch_managed_key()
    
    def _fetch_managed_key(self) -> Optional[str]:
        """Fetch managed Groq API key from backend"""
        # Check keychain cache first
        try:
            cached_key = keyring.get_password("riff", "managed_groq_key")
            if cached_key:
                logger.info("Using cached managed key")
                return cached_key
        except Exception:
            pass
        
        # Fetch from backend
        access_token = self._get_access_token()
        if not access_token:
            logger.error("Cannot fetch managed key: not authenticated")
            return None
        
        url = f"{self.supabase_url}/functions/v1/get-api-key"
        headers = {
            "Authorization": f"Bearer {access_token}",
            "apikey": self.supabase_anon_key
        }
        
        try:
            response = httpx.post(url, headers=headers, timeout=10.0)
            response.raise_for_status()
            
            result = response.json()
            api_key = result.get("api_key")
            
            if api_key:
                # Cache in keychain
                try:
                    keyring.set_password("riff", "managed_groq_key", api_key)
                except Exception as e:
                    logger.warning(f"Could not cache managed key: {e}")
                
                logger.info("Managed key fetched successfully")
                return api_key
        except httpx.HTTPError as e:
            logger.error(f"Failed to fetch managed key: {e}")
        
        return None
    
    # ========================================================================
    # IPC with Swift UI
    # ========================================================================
    
    def _load_auth_state(self):
        """Load auth state from auth_state.json (written by Swift UI)"""
        try:
            if self.auth_state_path.exists():
                with open(self.auth_state_path, 'r') as f:
                    state = json.load(f)

                self._auth_authenticated = state.get("authenticated", False)
                self._auth_email = state.get("email", "")
                self._auth_user_id = state.get("user_id", "")
                timestamp = state.get("timestamp", "unknown")

                logger.info(f"[Auth] Loaded auth_state.json: authenticated={self._auth_authenticated}, "
                            f"email={self._auth_email}, user_id={self._auth_user_id}, timestamp={timestamp}")
            else:
                logger.info("[Auth] No auth_state.json found — user has not logged in via Swift UI yet")
        except json.JSONDecodeError as e:
            logger.error(f"[Auth] auth_state.json is corrupted (invalid JSON): {e}")
        except Exception as e:
            logger.error(f"[Auth] Error loading auth_state.json: {e}")
    
    def _write_auth_state(self, authenticated: bool, email: str, user_id: str):
        """Write auth state to auth_state.json for Swift UI IPC"""
        state = {
            "authenticated": authenticated,
            "email": email,
            "user_id": user_id,
            "timestamp": datetime.now().isoformat()
        }
        try:
            with open(self.auth_state_path, 'w') as f:
                json.dump(state, f, indent=2)
            logger.info(f"[Auth] Wrote auth_state.json: authenticated={authenticated}, email={email}")
        except Exception as e:
            logger.error(f"[Auth] Error writing auth_state.json: {e}")
    
    def _load_cached_state(self):
        """Load cached subscription data"""
        try:
            if self.auth_cache_path.exists():
                with open(self.auth_cache_path, 'r') as f:
                    cache = json.load(f)
                    self._cached_subscription = cache.get("subscription")
                    if cache.get("last_validated"):
                        self._last_validated = datetime.fromisoformat(cache["last_validated"])
                    logger.info(f"[Auth] Loaded subscription cache: tier={self._cached_subscription.get('tier') if self._cached_subscription else 'None'}, "
                                f"last_validated={self._last_validated}")
            else:
                logger.info("[Auth] No subscription cache file found")
        except json.JSONDecodeError as e:
            logger.error(f"[Auth] Subscription cache is corrupted (invalid JSON): {e}")
        except Exception as e:
            logger.error(f"[Auth] Error loading subscription cache: {e}")
    
    def _save_cache(self):
        """Save subscription cache"""
        cache = {
            "subscription": self._cached_subscription,
            "last_validated": self._last_validated.isoformat() if self._last_validated else None
        }
        try:
            with open(self.auth_cache_path, 'w') as f:
                json.dump(cache, f, indent=2)
        except Exception as e:
            logger.error(f"Error saving cache: {e}")

    def handle_auth_callback_url(self, url: str) -> Dict[str, Any]:
        """Parse riff:// callback, store tokens, write auth_state.json."""
        parsed = urlparse(url)
        params: Dict[str, str] = {}
        if parsed.query:
            for key, values in parse_qs(parsed.query, keep_blank_values=True).items():
                if values:
                    params[key] = values[0]
        if parsed.fragment:
            for key, values in parse_qs(parsed.fragment, keep_blank_values=True).items():
                if values:
                    params[key] = values[0]

        if params.get("error_description") or params.get("error"):
            err = params.get("error_description") or params.get("error")
            logger.error("[Auth] Callback error: %s", err)
            return {"success": False, "error": err}

        access_token = params.get("access_token")
        refresh_token = params.get("refresh_token")
        if not access_token or not refresh_token:
            return {"success": False, "error": "Missing tokens in callback"}

        self._store_tokens(access_token, refresh_token)
        email, user_id = self._identity_from_access_token(access_token)
        self._write_auth_state(True, email, user_id)
        self._auth_authenticated = True
        self._auth_email = email
        self._auth_user_id = user_id
        self.log_login_event("email_confirm" if parsed.netloc == "auth" else "oauth_google", True)
        logger.info("[Auth] Callback stored session for %s", email)
        return {"success": True, "email": email, "user_id": user_id}

    def _identity_from_access_token(self, access_token: str) -> Tuple[str, str]:
        try:
            import base64
            parts = access_token.split(".")
            padded = parts[1] + "=" * (-len(parts[1]) % 4)
            payload = json.loads(base64.urlsafe_b64decode(padded))
            return payload.get("email", ""), payload.get("sub", "")
        except Exception as e:
            logger.warning("[Auth] JWT decode failed: %s", e)
            return "", ""

    def _auth_headers(self) -> Optional[Dict[str, str]]:
        token = self._get_access_token()
        if not token:
            return None
        return {
            "Authorization": f"Bearer {token}",
            "apikey": self.supabase_anon_key,
            "Content-Type": "application/json",
        }

    def register_this_device(self) -> None:
        headers = self._auth_headers()
        if not headers:
            return
        device_id = self.config.config.get("device", {}).get("device_id") or ""
        if not device_id:
            return
        url = f"{self.supabase_url}/functions/v1/register-device"
        body = {
            "device_id": device_id,
            "device_name": platform.node() or "Mac",
            "device_type": "mac",
            "os_version": platform.mac_ver()[0],
            "app_version": "1.2.5",
        }
        try:
            response = httpx.post(url, headers=headers, json=body, timeout=15.0)
            logger.info("[Auth] register-device status=%s body=%s", response.status_code, response.text[:200])
        except Exception as e:
            logger.warning("[Auth] register-device failed: %s", e)

    def upload_history_entry(self, timestamp: str, original: str, refined: str, style: str, script_mode: str) -> None:
        headers = self._auth_headers()
        if not headers:
            return
        device_id = self.config.config.get("device", {}).get("device_id")
        url = f"{self.supabase_url}/functions/v1/sync-history"
        body = {
            "timestamp": timestamp,
            "original": original,
            "refined": refined,
            "style": style,
            "script_mode": script_mode,
            "device_id": device_id,
        }
        try:
            httpx.post(url, headers=headers, json=body, timeout=15.0)
        except Exception as e:
            logger.warning("[Auth] history upload failed: %s", e)

    def download_history(self) -> list:
        headers = self._auth_headers()
        if not headers:
            return []
        url = f"{self.supabase_url}/functions/v1/sync-history"
        try:
            response = httpx.get(url, headers=headers, timeout=20.0)
            if response.status_code == 200:
                return response.json().get("history") or []
        except Exception as e:
            logger.warning("[Auth] history download failed: %s", e)
        return []

    def sync_user_settings(self, hotkey: str, style: str, script_mode: str, onboarding_completed: bool) -> None:
        headers = self._auth_headers()
        if not headers:
            return
        user_id = self._auth_user_id
        if not user_id:
            return
        url = f"{self.supabase_url}/rest/v1/user_settings?on_conflict=user_id"
        body = {
            "user_id": user_id,
            "hotkey": hotkey,
            "style": style,
            "script_mode": script_mode,
            "onboarding_completed": onboarding_completed,
        }
        headers = {**headers, "Prefer": "resolution=merge-duplicates"}
        try:
            httpx.post(url, headers=headers, json=body, timeout=10.0)
        except Exception as e:
            logger.warning("[Auth] settings sync failed: %s", e)

    def pull_user_settings(self) -> Optional[Dict[str, Any]]:
        headers = self._auth_headers()
        if not headers:
            return None
        url = f"{self.supabase_url}/rest/v1/user_settings?select=hotkey,style,script_mode,onboarding_completed"
        try:
            response = httpx.get(url, headers=headers, timeout=10.0)
            if response.status_code == 200:
                rows = response.json()
                return rows[0] if rows else None
        except Exception as e:
            logger.warning("[Auth] settings pull failed: %s", e)
        return None

    def log_login_event(self, method: str, success: bool, error: str = None) -> None:
        headers = self._auth_headers()
        if not headers:
            return
        url = f"{self.supabase_url}/rest/v1/login_events"
        body = {
            "user_id": self._auth_user_id or None,
            "email": self._auth_email,
            "method": method,
            "success": success,
            "device_id": self.config.config.get("device", {}).get("device_id"),
            "error": error,
        }
        headers = {**headers, "Prefer": "return=minimal"}
        try:
            httpx.post(url, headers=headers, json=body, timeout=8.0)
        except Exception as e:
            logger.debug("[Auth] login_events insert failed: %s", e)
