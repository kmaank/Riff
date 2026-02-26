# Phase 1: Backend Infrastructure - Implementation Checklist

## Overview
This phase creates the complete Supabase backend infrastructure including database schema, Edge Functions, and Stripe integration foundation.

**Timeline:** Week 1-2
**Status:** 🟡 In Progress

---

## Part 1: Project Setup ✅

- [x] Create `supabase/` directory structure
- [ ] Create Supabase project config (`supabase/config.toml`)
- [ ] Document Supabase project URL and anon key placeholders
- [ ] Update `.gitignore` for sensitive files

---

## Part 2: Database Schema 📊

### Migration Files to Create:

#### 001_profiles.sql
- [ ] Create `profiles` table
- [ ] Add indexes on email
- [ ] Create auto-trigger for profile creation on signup
- [ ] Add Row-Level Security (RLS) policies

#### 002_subscriptions.sql
- [ ] Create `subscriptions` table
- [ ] Add indexes on user_id, stripe_customer_id
- [ ] Create auto-trigger for free subscription on signup
- [ ] Add RLS policies (users can only read their own)

#### 003_usage_logs.sql
- [ ] Create `usage_logs` table (append-only)
- [ ] Add indexes on user_id, created_at
- [ ] Create `monthly_usage` view for quota aggregation
- [ ] Add RLS policies

#### 004_devices.sql
- [ ] Create `devices` table for device tracking
- [ ] Add indexes on user_id, device_id
- [ ] Add RLS policies
- [ ] Create function to enforce 3-device limit

#### 005_riff_history.sql
- [ ] Create `riff_history` table for cloud sync
- [ ] Add indexes on user_id, timestamp
- [ ] Add RLS policies
- [ ] Create function to limit history to last 1000 entries

#### 006_suspicious_activity.sql
- [ ] Create `suspicious_activity` table for abuse detection
- [ ] Add indexes on user_id, activity_type, created_at
- [ ] Add RLS policies (admin-only read)

---

## Part 3: Edge Functions 🔧

### Shared Utilities (supabase/functions/_shared/)

- [ ] **clients.ts** - Supabase and Stripe client initialization
- [ ] **tier-limits.ts** - Tier definitions and quota constants
- [ ] **auth.ts** - JWT verification and user authentication
- [ ] **types.ts** - TypeScript interfaces for database models

### Core Functions

#### validate-subscription/
- [ ] Create `index.ts`
- [ ] Implement subscription status check
- [ ] Implement quota calculation from monthly_usage view
- [ ] Return features based on tier
- [ ] Add error handling and logging

#### log-usage/
- [ ] Create `index.ts`
- [ ] Validate request signature (HMAC)
- [ ] Insert into usage_logs table
- [ ] Return updated quota
- [ ] Add concurrent usage detection

#### proxy-transcribe/
- [ ] Create `index.ts`
- [ ] Validate subscription and quota
- [ ] Retrieve managed Groq key from environment
- [ ] Proxy request to Groq Whisper API
- [ ] Log usage server-side
- [ ] Add rate limiting

#### proxy-refine/
- [ ] Create `index.ts`
- [ ] Validate subscription and quota
- [ ] Retrieve managed Groq key from environment
- [ ] Proxy request to Groq LLM API
- [ ] Return refined text
- [ ] Add rate limiting

#### register-device/
- [ ] Create `index.ts`
- [ ] Check device count for user
- [ ] Enforce 3-device limit
- [ ] Insert or update device record
- [ ] Return device registration status

#### sync-history/
- [ ] Create `index.ts`
- [ ] Support upload (POST) and download (GET) modes
- [ ] Limit to last 1000 entries per user
- [ ] Return history array with pagination

#### create-checkout/
- [ ] Create `index.ts`
- [ ] Initialize Stripe client
- [ ] Create Stripe Checkout session (starter/pro/lifetime)
- [ ] Return checkout URL
- [ ] Handle errors gracefully

#### stripe-webhook/
- [ ] Create `index.ts`
- [ ] Verify Stripe signature
- [ ] Handle `checkout.session.completed`
- [ ] Handle `invoice.payment_succeeded`
- [ ] Handle `invoice.payment_failed`
- [ ] Handle `customer.subscription.deleted`
- [ ] Update subscriptions table accordingly
- [ ] Provision managed API key on upgrade
- [ ] Add logging for all events

#### create-portal/
- [ ] Create `index.ts`
- [ ] Create Stripe Customer Portal session
- [ ] Return portal URL
- [ ] Add error handling

---

## Part 4: Configuration & Secrets 🔐

- [ ] Create `supabase/.env.example` template
- [ ] Document required environment variables:
  - `SUPABASE_URL`
  - `SUPABASE_ANON_KEY`
  - `SUPABASE_SERVICE_KEY`
  - `STRIPE_SECRET_KEY`
  - `STRIPE_WEBHOOK_SECRET`
  - `GROQ_API_KEY_STARTER`
  - `GROQ_API_KEY_PRO`
  - `GROQ_API_KEY_LIFETIME`
- [ ] Update main `.gitignore` to exclude `supabase/.env`

---

## Part 5: Stripe Setup 💳

- [ ] Create Stripe account (test mode)
- [ ] Create Products:
  - Starter ($9.99/month recurring)
  - Pro ($19.99/month recurring)
  - Lifetime ($149.00 one-time)
- [ ] Copy Price IDs to config
- [ ] Configure webhook endpoint (will point to stripe-webhook function)
- [ ] Copy webhook signing secret

---

## Part 6: Testing & Validation ✅

- [ ] Test database migrations locally (Supabase CLI)
- [ ] Test each Edge Function with curl/Postman:
  - validate-subscription
  - log-usage
  - proxy-transcribe
  - proxy-refine
  - register-device
  - sync-history
- [ ] Test Stripe webhook with Stripe CLI (`stripe listen --forward-to`)
- [ ] Verify RLS policies prevent unauthorized access
- [ ] Test device limit enforcement
- [ ] Test quota enforcement

---

## Part 7: Documentation 📝

- [ ] Create `supabase/README.md` with setup instructions
- [ ] Document API endpoints and request/response formats
- [ ] Create example curl commands for each Edge Function
- [ ] Document database schema with ER diagram
- [ ] Add Stripe integration guide

---

## Deliverables

At the end of Phase 1, we will have:

1. ✅ Complete Supabase project with all tables and RLS policies
2. ✅ 9 working Edge Functions (auth, proxy, billing, sync)
3. ✅ Stripe products configured and webhook integration
4. ✅ Managed API key infrastructure (encrypted storage)
5. ✅ Device tracking and concurrent usage detection
6. ✅ Cloud history sync foundation
7. ✅ Full documentation for backend setup

---

## Next Phase

**Phase 2: Python Auth Layer** - Build `utils/auth_manager.py` to integrate with this backend.

---

## Notes

- Use Supabase CLI for local development and testing
- All Edge Functions use Deno runtime
- Database migrations are version-controlled and reversible
- Stripe test mode allows unlimited testing without real charges
- RLS policies ensure multi-tenant security
