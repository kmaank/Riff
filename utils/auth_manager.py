"""
Authentication Manager for Riff
Handles Supabase authentication, subscription validation, quota enforcement, and usage logging
"""

import json
import logging
import httpx
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional, Dict, Any, Tuple
import keyring

from utils.subscription_config import get_tier_features

logger = logging.getLogger(__name__)

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
        
        # Cached state
        self._cached_subscription: Optional[Dict[str, Any]] = None
        self._last_validated: Optional[datetime] = None
        self._access_token: Optional[str] = None
        self._refresh_token: Optional[str] = None
        
        # Load cached state
        self._load_cached_state()
        self._load_auth_state()
    
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
        if self._access_token:
            return self._access_token
        
        try:
            token = keyring.get_password("riff", "supabase_access_token")
            if token:
                self._access_token = token
            return token
        except Exception as e:
            logger.error(f"Error getting access token: {e}")
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
        url = f"{self.supabase_url}/auth/v1/token?grant_type=password"
        headers = {
            "apikey": self.supabase_anon_key,
            "Content-Type": "application/json"
        }
        data = {"email": email, "password": password}
        
        try:
            response = httpx.post(url, headers=headers, json=data, timeout=10.0)
            response.raise_for_status()
            
            result = response.json()
            self._store_tokens(result["access_token"], result["refresh_token"])
            self._write_auth_state(True, result["user"]["email"], result["user"]["id"])
            
            logger.info(f"Login successful for {email}")
            return {"success": True, "user": result["user"]}
        except httpx.HTTPError as e:
            logger.error(f"Login failed: {e}")
            return {"success": False, "error": str(e)}
    
    def signup(self, email: str, password: str) -> Dict[str, Any]:
        """Sign up with email and password"""
        url = f"{self.supabase_url}/auth/v1/signup"
        headers = {
            "apikey": self.supabase_anon_key,
            "Content-Type": "application/json"
        }
        data = {"email": email, "password": password}
        
        try:
            response = httpx.post(url, headers=headers, json=data, timeout=10.0)
            response.raise_for_status()
            
            result = response.json()
            self._store_tokens(result["access_token"], result["refresh_token"])
            self._write_auth_state(True, result["user"]["email"], result["user"]["id"])
            
            logger.info(f"Signup successful for {email}")
            return {"success": True, "user": result["user"]}
        except httpx.HTTPError as e:
            logger.error(f"Signup failed: {e}")
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
        refresh_token = self._get_refresh_token()
        if not refresh_token:
            return False
        
        url = f"{self.supabase_url}/auth/v1/token?grant_type=refresh_token"
        headers = {
            "apikey": self.supabase_anon_key,
            "Content-Type": "application/json"
        }
        data = {"refresh_token": refresh_token}
        
        try:
            response = httpx.post(url, headers=headers, json=data, timeout=10.0)
            response.raise_for_status()
            
            result = response.json()
            self._store_tokens(result["access_token"], result["refresh_token"])
            logger.info("Token refreshed successfully")
            return True
        except httpx.HTTPError as e:
            logger.error(f"Token refresh failed: {e}")
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
            logger.error("No access token available")
            return None
        
        url = f"{self.supabase_url}/functions/v1/validate-subscription"
        headers = {
            "Authorization": f"Bearer {access_token}",
            "apikey": self.supabase_anon_key
        }
        
        try:
            response = httpx.post(url, headers=headers, timeout=10.0)
            response.raise_for_status()
            
            result = response.json()
            self._cached_subscription = result
            self._last_validated = datetime.now()
            self._save_cache()
            
            logger.info(f"Subscription validated: tier={result.get('tier')}, status={result.get('status')}")
            return result
        except httpx.HTTPError as e:
            logger.error(f"Subscription validation failed: {e}")
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
            "script_mode": script_mode
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
        """Load auth state from auth_state.json (written by Swift)"""
        try:
            if self.auth_state_path.exists():
                with open(self.auth_state_path, 'r') as f:
                    state = json.load(f)
                    logger.info(f"Loaded auth state: authenticated={state.get('authenticated')}")
        except Exception as e:
            logger.error(f"Error loading auth state: {e}")
    
    def _write_auth_state(self, authenticated: bool, email: str, user_id: str):
        """Write auth state to auth_state.json for Swift"""
        state = {
            "authenticated": authenticated,
            "email": email,
            "user_id": user_id,
            "timestamp": datetime.now().isoformat()
        }
        try:
            with open(self.auth_state_path, 'w') as f:
                json.dump(state, f, indent=2)
        except Exception as e:
            logger.error(f"Error writing auth state: {e}")
    
    def _load_cached_state(self):
        """Load cached subscription data"""
        try:
            if self.auth_cache_path.exists():
                with open(self.auth_cache_path, 'r') as f:
                    cache = json.load(f)
                    self._cached_subscription = cache.get("subscription")
                    if cache.get("last_validated"):
                        self._last_validated = datetime.fromisoformat(cache["last_validated"])
        except Exception as e:
            logger.error(f"Error loading cache: {e}")
    
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
