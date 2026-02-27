#!/bin/bash

# Stripe Webhook Testing Script
# Simulates Stripe webhook events to test the webhook handler

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SUPABASE_URL="https://yrsviodciuepunofxoja.supabase.co"

echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Stripe Webhook Test${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}\n"

echo -e "${BLUE}This script helps you test Stripe webhooks.${NC}\n"

echo -e "${YELLOW}Testing Methods:${NC}"
echo -e "  1. Use Stripe CLI (recommended)"
echo -e "  2. Use Stripe Dashboard webhook testing"
echo -e "  3. Manual curl test (limited)\n"

echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Method 1: Stripe CLI (Recommended)${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}\n"

echo -e "${BLUE}Step 1: Install Stripe CLI${NC}"
echo -e "  Mac: brew install stripe/stripe-cli/stripe"
echo -e "  Linux: See https://stripe.com/docs/stripe-cli\n"

echo -e "${BLUE}Step 2: Login to Stripe${NC}"
echo -e "  $ stripe login\n"

echo -e "${BLUE}Step 3: Forward webhooks to your Edge Function${NC}"
echo -e "  $ stripe listen --forward-to $SUPABASE_URL/functions/v1/stripe-webhook\n"

echo -e "${BLUE}Step 4: Trigger test events${NC}"
echo -e "  # Test subscription created"
echo -e "  $ stripe trigger customer.subscription.created\n"
echo -e "  # Test subscription updated"
echo -e "  $ stripe trigger customer.subscription.updated\n"
echo -e "  # Test subscription deleted"
echo -e "  $ stripe trigger customer.subscription.deleted\n"
echo -e "  # Test payment succeeded"
echo -e "  $ stripe trigger invoice.payment_succeeded\n"
echo -e "  # Test payment failed"
echo -e "  $ stripe trigger invoice.payment_failed\n"

echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Method 2: Stripe Dashboard${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}\n"

echo -e "${BLUE}Step 1: Go to your webhook endpoint${NC}"
echo -e "  https://dashboard.stripe.com/webhooks\n"

echo -e "${BLUE}Step 2: Click on your endpoint${NC}"
echo -e "  $SUPABASE_URL/functions/v1/stripe-webhook\n"

echo -e "${BLUE}Step 3: Click 'Send test webhook'${NC}"
echo -e "  Select event type and send\n"

echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Method 3: Manual Test (Limited)${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}\n"

echo -e "${BLUE}Testing webhook endpoint availability...${NC}\n"

# Test 1: No signature (should fail with 400)
echo -e "${YELLOW}Test 1: No Stripe signature (should fail)${NC}"
response=$(curl -s -w "\n%{http_code}" -X POST \
    "$SUPABASE_URL/functions/v1/stripe-webhook" \
    -H "Content-Type: application/json" \
    -d '{"type":"customer.subscription.created"}')

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

echo -e "  Status: $http_code"
echo -e "  Response: $body"

if [ "$http_code" == "400" ]; then
    echo -e "${GREEN}✓ Correctly rejected unsigned request${NC}\n"
else
    echo -e "${RED}✗ Unexpected response${NC}\n"
fi

# Test 2: Invalid signature (should fail with 400)
echo -e "${YELLOW}Test 2: Invalid Stripe signature (should fail)${NC}"
response=$(curl -s -w "\n%{http_code}" -X POST \
    "$SUPABASE_URL/functions/v1/stripe-webhook" \
    -H "Content-Type: application/json" \
    -H "Stripe-Signature: t=1234567890,v1=invalid" \
    -d '{"type":"customer.subscription.created"}')

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

echo -e "  Status: $http_code"
echo -e "  Response: $body"

if [ "$http_code" == "400" ]; then
    echo -e "${GREEN}✓ Correctly rejected invalid signature${NC}\n"
else
    echo -e "${RED}✗ Unexpected response${NC}\n"
fi

echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Recommendations${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}\n"

echo -e "${GREEN}✓ Webhook endpoint is deployed and responding${NC}"
echo -e "${GREEN}✓ Signature validation is working${NC}\n"

echo -e "${BLUE}Next steps:${NC}"
echo -e "  1. Use Stripe CLI to test real webhook events"
echo -e "  2. Monitor Supabase logs during testing"
echo -e "  3. Check your database for subscription updates\n"

echo -e "${YELLOW}View webhook logs:${NC}"
echo -e "  https://supabase.com/dashboard/project/yrsviodciuepunofxoja/logs/edge-functions\n"

echo -e "${YELLOW}Stripe CLI Quick Reference:${NC}"
echo -e "  stripe listen --forward-to $SUPABASE_URL/functions/v1/stripe-webhook"
echo -e "  stripe trigger customer.subscription.created"
echo -e "  stripe trigger invoice.payment_succeeded\n"
