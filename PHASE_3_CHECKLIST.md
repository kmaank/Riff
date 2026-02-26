# Phase 3: Swift UI Auth Integration - Implementation Checklist

## Overview
Build login screens, account management UI, and integrate with Python auth layer via IPC.

**Timeline:** Week 3-4
**Status:** 🟡 In Progress

---

## Part 1: Core Auth Manager (Swift) ✅

### config_ui/RiffControlCenter/AuthManager.swift
- [ ] Create SwiftAuthManager ObservableObject
- [ ] Published properties (isAuthenticated, tier, quota, email)
- [ ] Login/signup methods (call Supabase REST API)
- [ ] OAuth flow helpers (open system browser)
- [ ] Read/write auth_state.json for IPC with Python
- [ ] Token storage (UserDefaults or Keychain)
- [ ] Subscription data caching

---

## Part 2: Login & Signup UI 🎨

### config_ui/RiffControlCenter/LoginView.swift
- [ ] Full-screen login/signup view
- [ ] Email + password text fields
- [ ] Sign In / Sign Up toggle
- [ ] "Or" divider with social login
- [ ] OAuth buttons (Google, GitHub, Apple)
- [ ] Error message display
- [ ] Loading state
- [ ] Consistent gray.opacity(0.08) design

---

## Part 3: Account Management UI 💳

### config_ui/RiffControlCenter/AccountView.swift
- [ ] New sidebar tab "Account"
- [ ] User info section (email, member since)
- [ ] Subscription card:
  - Tier badge (Free/Starter/Pro/Lifetime)
  - Status indicator (active/past_due/canceled)
  - Usage progress bars (riffs, recording time)
- [ ] Action buttons:
  - "Upgrade" (for free/starter users)
  - "Manage Billing" (opens Stripe portal)
- [ ] API Key section (BYOK for free tier only)
- [ ] Sign Out button

### config_ui/RiffControlCenter/SubscriptionView.swift
- [ ] Tier selection view
- [ ] Three tier cards side-by-side:
  - Free (BYOK)
  - Starter $9.99/mo
  - Pro $19.99/mo
- [ ] Feature comparison list on each card
- [ ] Current tier highlighted
- [ ] "Upgrade" buttons (opens Stripe Checkout in browser)
- [ ] Optional: Lifetime deal banner

---

## Part 4: Integration with Existing UI 🔧

### config_ui/RiffControlCenter/ContentView.swift
- [ ] Add auth gate before onboarding:
  ```swift
  if !authManager.isAuthenticated {
      LoginView()
  } else if !onboarding_completed {
      OnboardingView()
  } else {
      // Existing tabs
  }
  ```
- [ ] Add "Account" tab to sidebar

### config_ui/RiffControlCenter/OnboardingView.swift
- [ ] Add tier selection step (after welcome, before API key)
- [ ] Make API key step conditional:
  - Show only for free tier
  - Skip for paid users (managed key)
- [ ] Update onboarding flow navigation

### config_ui/RiffControlCenter/ScriptAndStyleView.swift
- [ ] Lock styles by tier:
  - Free: show clean + casual only
  - Paid: show all styles
  - Locked styles show lock icon + "Upgrade" badge

### config_ui/RiffControlCenter/RiffControlCenterApp.swift
- [ ] Add SwiftAuthManager as @StateObject
- [ ] Inject into environment
- [ ] Add .onOpenURL handler for OAuth callback
- [ ] Handle `riff://oauth/callback` URL scheme

---

## Part 5: OAuth Configuration 🔐

### config_ui/build_ui.sh
- [ ] Add CFBundleURLTypes to Info.plist:
  ```xml
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>riff</string>
      </array>
      <key>CFBundleURLName</key>
      <string>com.riff.app</string>
    </dict>
  </array>
  ```

---

## Part 6: IPC with Python 🔄

### auth_state.json format
```json
{
  "authenticated": true,
  "email": "user@example.com",
  "user_id": "uuid",
  "tier": "pro",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Flow:**
1. User logs in via Swift UI
2. Swift writes to auth_state.json
3. Python reads auth_state.json on startup
4. Python validates subscription with backend
5. Both sides poll the file for changes

---

## Part 7: Stripe Integration 💰

### Open Stripe Checkout (from Swift)
```swift
if let url = URL(string: checkoutURL) {
    NSWorkspace.shared.open(url)
}
```

### Open Stripe Customer Portal
```swift
Button("Manage Billing") {
    // Call create-portal Edge Function
    // Open returned URL in browser
}
```

---

## Part 8: Testing ✅

- [ ] Test login flow (email + password)
- [ ] Test OAuth flow (Google, GitHub, Apple)
- [ ] Test tier selection in onboarding
- [ ] Test account view (subscription status, usage bars)
- [ ] Test upgrade flow (Stripe Checkout)
- [ ] Test billing portal
- [ ] Test sign out
- [ ] Test IPC (Swift ↔ Python via auth_state.json)
- [ ] Test style locking by tier

---

## Deliverables

At the end of Phase 3, we will have:

1. ✅ Complete login/signup UI with OAuth
2. ✅ Account management dashboard
3. ✅ Subscription tier selection
4. ✅ Stripe integration (Checkout + Portal)
5. ✅ Auth gate before app access
6. ✅ Conditional onboarding based on tier
7. ✅ Feature gating (styles by tier)
8. ✅ IPC between Swift and Python

---

## Next Phase

**Phase 4: Stripe Integration & Testing** - Deploy backend, test full flow, production readiness

---

## Notes

- Use URLSession for HTTP calls (or async/await in iOS 15+)
- Store tokens securely (Keychain, not UserDefaults)
- Handle OAuth redirects via custom URL scheme
- Poll auth_state.json every 2 seconds (same as config.json)
- Use @Published properties for reactive UI updates
- Match design system (gray.opacity(0.08) backgrounds)
