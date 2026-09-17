#!/bin/bash

# Health Check Script for Riff Backend
# Performs comprehensive health checks on all services

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SUPABASE_URL="https://yrsviodciuepunofxoja.supabase.co"
SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inlyc3Zpb2RjaXVlcHVub2Z4b2phIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIwOTk0MTIsImV4cCI6MjA4NzY3NTQxMn0.GBYQIn6A6TmcHjL75m8bTNbPXe2zCGH28jrxrOhnmo8"

# Health status
HEALTHY=0
WARNINGS=0
ERRORS=0

echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Riff Backend Health Check${NC}"
echo -e "${YELLOW}  $(date)${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}\n"

# Function to check endpoint health
check_endpoint() {
    local name=$1
    local url=$2
    local expected_status=$3

    echo -n "  $name... "

    response=$(curl -s -w "%{http_code}" -o /dev/null --max-time 5 "$url" \
        -H "Authorization: Bearer $SUPABASE_ANON_KEY" 2>&1 || echo "000")

    if [ "$response" == "$expected_status" ]; then
        echo -e "${GREEN}✓ OK${NC} ($response)"
        ((HEALTHY++))
    elif [ "$response" == "000" ]; then
        echo -e "${RED}✗ TIMEOUT${NC}"
        ((ERRORS++))
    else
        echo -e "${YELLOW}! WARNING${NC} (got $response, expected $expected_status)"
        ((WARNINGS++))
    fi
}

# 1. Check Supabase API
echo -e "${BLUE}[1] Supabase API${NC}"
response=$(curl -s -w "%{http_code}" -o /dev/null "$SUPABASE_URL/rest/v1/" \
    -H "apikey: $SUPABASE_ANON_KEY" 2>&1 || echo "000")

if [ "$response" == "200" ]; then
    echo -e "  ${GREEN}✓ Supabase API responding${NC}\n"
    ((HEALTHY++))
else
    echo -e "  ${RED}✗ Supabase API not responding${NC}\n"
    ((ERRORS++))
fi

# 2. Check Edge Functions
echo -e "${BLUE}[2] Edge Functions${NC}"

check_endpoint "validate-subscription" \
    "$SUPABASE_URL/functions/v1/validate-subscription" \
    "401"

check_endpoint "log-usage" \
    "$SUPABASE_URL/functions/v1/log-usage" \
    "401"

check_endpoint "register-device" \
    "$SUPABASE_URL/functions/v1/register-device" \
    "401"

check_endpoint "sync-history" \
    "$SUPABASE_URL/functions/v1/sync-history" \
    "401"

check_endpoint "get-api-key" \
    "$SUPABASE_URL/functions/v1/get-api-key" \
    "401"

check_endpoint "create-checkout" \
    "$SUPABASE_URL/functions/v1/create-checkout" \
    "401"

check_endpoint "create-portal" \
    "$SUPABASE_URL/functions/v1/create-portal" \
    "401"

check_endpoint "stripe-webhook" \
    "$SUPABASE_URL/functions/v1/stripe-webhook" \
    "400"

check_endpoint "proxy-transcribe" \
    "$SUPABASE_URL/functions/v1/proxy-transcribe" \
    "401"

check_endpoint "proxy-refine" \
    "$SUPABASE_URL/functions/v1/proxy-refine" \
    "401"

echo ""

# 3. Check Authentication
echo -e "${BLUE}[3] Authentication Service${NC}"
auth_response=$(curl -s -w "%{http_code}" -o /dev/null "$SUPABASE_URL/auth/v1/health" \
    -H "apikey: $SUPABASE_ANON_KEY" 2>&1 || echo "000")

if [ "$auth_response" == "200" ]; then
    echo -e "  ${GREEN}✓ Auth service responding${NC}\n"
    ((HEALTHY++))
else
    echo -e "  ${RED}✗ Auth service not responding${NC}\n"
    ((ERRORS++))
fi

# 4. Database Connection
echo -e "${BLUE}[4] Database${NC}"
db_response=$(curl -s "$SUPABASE_URL/rest/v1/profiles?select=count" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Range: 0-0" 2>&1 || echo "error")

if echo "$db_response" | grep -q "count"; then
    echo -e "  ${GREEN}✓ Database connection OK${NC}\n"
    ((HEALTHY++))
else
    echo -e "  ${RED}✗ Database connection failed${NC}\n"
    ((ERRORS++))
fi

# 5. Check Environment Variables (via function test)
echo -e "${BLUE}[5] Environment Configuration${NC}"

# Test if functions have required env vars (they'll fail gracefully if not)
echo -e "  ${YELLOW}ⓘ Some checks may show warnings if Stripe is not configured${NC}"
echo -e "  ${YELLOW}  This is expected in development/testing${NC}\n"

# Summary
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Health Check Summary${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Healthy:${NC} $HEALTHY"
echo -e "${YELLOW}! Warnings:${NC} $WARNINGS"
echo -e "${RED}✗ Errors:${NC} $ERRORS"
echo -e "${YELLOW}Total Checks:${NC} $((HEALTHY + WARNINGS + ERRORS))\n"

# Overall status
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  ✓ ALL SYSTEMS OPERATIONAL ✓${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  ! SYSTEMS OPERATIONAL WITH WARNINGS !${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    exit 0
else
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}  ✗ SYSTEM ERRORS DETECTED ✗${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo -e "${YELLOW}Check Supabase logs:${NC}"
    echo -e "  https://supabase.com/dashboard/project/yrsviodciuepunofxoja/logs/edge-functions\n"
    exit 1
fi
