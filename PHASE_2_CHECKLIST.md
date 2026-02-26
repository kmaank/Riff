# Phase 2: Python Auth Layer - Implementation Checklist

## Overview
Integrate Riff's Python client with the Supabase backend. Add authentication, subscription validation, quota enforcement, and usage logging.

**Timeline:** Week 2-3
**Status:** 🟡 In Progress

---

## Part 1: Core Auth Module ✅

### utils/auth_manager.py
- [ ] Create AuthManager class
- [ ] Implement login/signup (email + password)
- [ ] Implement OAuth flow helpers
- [ ] JWT token storage in macOS Keychain (keyring)
- [ ] Token refresh logic
- [ ] Subscription validation (online + offline cache)
- [ ] Quota enforcement (can_riff method)
- [ ] Usage logging after each riff
- [ ] Device registration on startup
- [ ] HMAC request signing
- [ ] Offline cache strategy (24h check, 7-day grace)

### utils/subscription_config.py
- [ ] Define TIER_LIMITS dictionary (mirror TypeScript tier-limits.ts)
- [ ] Helper functions for tier checks
- [ ] Style validation by tier

### utils/request_signer.py
- [ ] HMAC signing function
- [ ] Signature verification for testing

---

## Part 2: Config Updates 📝

### utils/config_manager.py
- [ ] Add `auth` section to DEFAULT_CONFIG
- [ ] Add Supabase URL and anon key
- [ ] Keep existing metrics structure

### requirements.txt
- [ ] Add httpx (HTTP client for Supabase)
- [ ] Add PyJWT (JWT token decoding)
- [ ] Add keyring (secure token storage)

---

## Part 3: Main App Integration 🔧

### main.py
- [ ] Import AuthManager
- [ ] Initialize AuthManager in RiffApp.__init__
- [ ] Pass AuthManager to ProcessingThread
- [ ] Add auth check in main() - launch settings if not authenticated
- [ ] Add periodic subscription revalidation (every 60 minutes)

### ProcessingThread
- [ ] Add quota gate at start of _process_audio_file()
- [ ] Call auth_manager.log_usage() after successful riff
- [ ] Update to use proxy endpoints for paid users
- [ ] Handle quota exceeded gracefully with notification

---

## Part 4: Build & Deployment 🏗️

### Riff.spec
- [ ] Add httpx to hiddenimports
- [ ] Add PyJWT to hiddenimports
- [ ] Add keyring to hiddenimports

### utils/logger.py
- [ ] Add Supabase token patterns to SENSITIVE_PATTERNS
- [ ] Add HMAC signature patterns

---

## Part 5: Testing ✅

### tests/test_auth_manager.py
- [ ] Test login/signup flows
- [ ] Test token refresh
- [ ] Test subscription validation
- [ ] Test quota enforcement
- [ ] Test offline cache fallback
- [ ] Test HMAC signing
- [ ] Mock HTTP responses

---

## Part 6: Documentation 📚

- [ ] Update main README.md with auth flow
- [ ] Document environment variables
- [ ] Add troubleshooting section for auth errors

---

## Deliverables

At the end of Phase 2, we will have:

1. ✅ Complete Python auth module with Supabase integration
2. ✅ Quota enforcement before every riff
3. ✅ Usage logging after every riff
4. ✅ Offline cache with 24h validation + 7-day grace
5. ✅ HMAC request signing for security
6. ✅ Device registration and tracking
7. ✅ Proxy endpoints for paid users (API key protection)
8. ✅ Graceful auth failure handling

---

## Next Phase

**Phase 3: Swift UI Auth** - Build login screens and account management UI

---

## Notes

- Use httpx for async HTTP requests (better than requests)
- Store tokens in macOS Keychain using keyring library
- Cache subscription data in auth_cache.json for offline
- Mock Supabase endpoints for testing (don't hit live API)
- Ensure backward compatibility with existing BYOK users
