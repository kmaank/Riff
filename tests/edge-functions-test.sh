#!/bin/bash

# Edge Functions Testing Suite for Riff
# Tests all deployed Edge Functions

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SUPABASE_URL="https://yrsviodciuepunofxoja.supabase.co"
SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inlyc3Zpb2RjaXVlcHVub2Z4b2phIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIwOTk0MTIsImV4cCI6MjA4NzY3NTQxMn0.GBYQIn6A6TmcHjL75m8bTNbPXe2zCGH28jrxrOhnmo8"

echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Riff Edge Functions Test Suite${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}\n"

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function to test an endpoint
test_endpoint() {
    local name=$1
    local endpoint=$2
    local method=$3
    local data=$4
    local expected_status=$5

    echo -e "\n${YELLOW}Testing:${NC} $name"
    echo -e "  Endpoint: $endpoint"
    echo -e "  Method: $method"

    if [ -n "$data" ]; then
        response=$(curl -s -w "\n%{http_code}" -X "$method" \
            "$SUPABASE_URL/functions/v1/$endpoint" \
            -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
            -H "Content-Type: application/json" \
            -d "$data")
    else
        response=$(curl -s -w "\n%{http_code}" -X "$method" \
            "$SUPABASE_URL/functions/v1/$endpoint" \
            -H "Authorization: Bearer $SUPABASE_ANON_KEY")
    fi

    http_code=$(echo "$response" | tail -n 1)
    body=$(echo "$response" | head -n -1)

    echo -e "  Status: $http_code"
    echo -e "  Response: $body" | head -c 200

    if [ "$http_code" == "$expected_status" ]; then
        echo -e "  ${GREEN}✓ PASSED${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "  ${RED}✗ FAILED${NC} (expected $expected_status, got $http_code)"
        ((TESTS_FAILED++))
    fi
}

echo -e "\n${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  1. Testing Authentication Endpoints${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"

# Test validate-subscription (should fail without auth)
test_endpoint \
    "Validate Subscription (no auth)" \
    "validate-subscription" \
    "GET" \
    "" \
    "401"

# Test get-api-key (should fail without auth)
test_endpoint \
    "Get API Key (no auth)" \
    "get-api-key" \
    "GET" \
    "" \
    "401"

echo -e "\n${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  2. Testing Device Registration${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"

# Test register-device (should fail without auth)
test_endpoint \
    "Register Device (no auth)" \
    "register-device" \
    "POST" \
    '{"device_id":"test-device","platform":"android","app_version":"1.0.0"}' \
    "401"

echo -e "\n${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  3. Testing Usage Logging${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"

# Test log-usage (should fail without auth)
test_endpoint \
    "Log Usage (no auth)" \
    "log-usage" \
    "POST" \
    '{"endpoint":"transcribe","duration_seconds":10}' \
    "401"

echo -e "\n${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  4. Testing History Sync${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"

# Test sync-history (should fail without auth)
test_endpoint \
    "Sync History (no auth)" \
    "sync-history" \
    "POST" \
    '{"entries":[]}' \
    "401"

echo -e "\n${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  5. Testing Stripe Endpoints${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"

# Test create-checkout (should fail without auth)
test_endpoint \
    "Create Checkout (no auth)" \
    "create-checkout" \
    "POST" \
    '{"price_id":"price_test"}' \
    "401"

# Test create-portal (should fail without auth)
test_endpoint \
    "Create Portal (no auth)" \
    "create-portal" \
    "POST" \
    '{}' \
    "401"

# Test stripe-webhook (should fail without Stripe signature)
test_endpoint \
    "Stripe Webhook (no signature)" \
    "stripe-webhook" \
    "POST" \
    '{"type":"test"}' \
    "400"

echo -e "\n${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  6. Testing Proxy Endpoints${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"

# Test proxy-transcribe (should fail without auth)
test_endpoint \
    "Proxy Transcribe (no auth)" \
    "proxy-transcribe" \
    "POST" \
    '{"audio":"test"}' \
    "401"

# Test proxy-refine (should fail without auth)
test_endpoint \
    "Proxy Refine (no auth)" \
    "proxy-refine" \
    "POST" \
    '{"text":"test"}' \
    "401"

echo -e "\n${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Test Summary${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Passed:${NC} $TESTS_PASSED"
echo -e "${RED}✗ Failed:${NC} $TESTS_FAILED"
echo -e "${YELLOW}Total:${NC} $((TESTS_PASSED + TESTS_FAILED))\n"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed! ✓${NC}\n"
    exit 0
else
    echo -e "${RED}Some tests failed! ✗${NC}\n"
    exit 1
fi
