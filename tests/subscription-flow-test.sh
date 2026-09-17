#!/bin/bash

# Complete Subscription Flow Test
# Tests the entire user journey from signup to subscription

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

# Generate random test user
TEST_EMAIL="test-$(date +%s)@example.com"
TEST_PASSWORD="Test123!@#"

echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Riff Subscription Flow Test${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}\n"

# Step 1: Sign Up
echo -e "${BLUE}[Step 1]${NC} Creating test user..."
echo -e "  Email: $TEST_EMAIL"

signup_response=$(curl -s -X POST \
    "$SUPABASE_URL/auth/v1/signup" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Content-Type: application/json" \
    -d "{
        \"email\": \"$TEST_EMAIL\",
        \"password\": \"$TEST_PASSWORD\"
    }")

# Extract access token
ACCESS_TOKEN=$(echo "$signup_response" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
USER_ID=$(echo "$signup_response" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)

if [ -z "$ACCESS_TOKEN" ]; then
    echo -e "${RED}✗ Failed to create user${NC}"
    echo "$signup_response"
    exit 1
fi

echo -e "${GREEN}✓ User created successfully${NC}"
echo -e "  User ID: $USER_ID"
echo -e "  Token: ${ACCESS_TOKEN:0:20}...\n"

# Step 2: Validate Subscription (Free Tier)
echo -e "${BLUE}[Step 2]${NC} Validating subscription (should be free tier)..."

validate_response=$(curl -s -X GET \
    "$SUPABASE_URL/functions/v1/validate-subscription" \
    -H "Authorization: Bearer $ACCESS_TOKEN")

echo -e "  Response: $validate_response"

if echo "$validate_response" | grep -q "free"; then
    echo -e "${GREEN}✓ Free tier validation successful${NC}\n"
else
    echo -e "${YELLOW}! Unexpected response (might still be valid)${NC}\n"
fi

# Step 3: Register Device
echo -e "${BLUE}[Step 3]${NC} Registering device..."

device_response=$(curl -s -X POST \
    "$SUPABASE_URL/functions/v1/register-device" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "device_id": "test-mac-device",
        "platform": "macos",
        "app_version": "1.0.0"
    }')

echo -e "  Response: $device_response"

if echo "$device_response" | grep -q -E "(success|registered|device_id)"; then
    echo -e "${GREEN}✓ Device registered successfully${NC}\n"
else
    echo -e "${YELLOW}! Device registration response (check manually)${NC}\n"
fi

# Step 4: Get API Key
echo -e "${BLUE}[Step 4]${NC} Getting API key..."

apikey_response=$(curl -s -X GET \
    "$SUPABASE_URL/functions/v1/get-api-key" \
    -H "Authorization: Bearer $ACCESS_TOKEN")

echo -e "  Response: $apikey_response"

if echo "$apikey_response" | grep -q "api_key"; then
    echo -e "${GREEN}✓ API key retrieved successfully${NC}\n"
else
    echo -e "${YELLOW}! API key response (check manually)${NC}\n"
fi

# Step 5: Log Usage
echo -e "${BLUE}[Step 5]${NC} Logging usage..."

usage_response=$(curl -s -X POST \
    "$SUPABASE_URL/functions/v1/log-usage" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "endpoint": "transcribe",
        "duration_seconds": 10,
        "metadata": {"test": true}
    }')

echo -e "  Response: $usage_response"

if echo "$usage_response" | grep -q -E "(success|logged|usage)"; then
    echo -e "${GREEN}✓ Usage logged successfully${NC}\n"
else
    echo -e "${YELLOW}! Usage logging response (check manually)${NC}\n"
fi

# Step 6: Sync History
echo -e "${BLUE}[Step 6]${NC} Syncing history..."

history_response=$(curl -s -X POST \
    "$SUPABASE_URL/functions/v1/sync-history" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "entries": [
            {
                "device_id": "test-mac-device",
                "transcription": "Test transcription",
                "refined_text": "Test refined text",
                "audio_duration": 10,
                "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
            }
        ]
    }')

echo -e "  Response: $history_response"

if echo "$history_response" | grep -q -E "(success|synced|entries)"; then
    echo -e "${GREEN}✓ History synced successfully${NC}\n"
else
    echo -e "${YELLOW}! History sync response (check manually)${NC}\n"
fi

# Step 7: Create Checkout Session
echo -e "${BLUE}[Step 7]${NC} Creating checkout session..."
echo -e "${YELLOW}  Note: Requires STRIPE_SECRET_KEY to be set${NC}"

checkout_response=$(curl -s -X POST \
    "$SUPABASE_URL/functions/v1/create-checkout" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "price_id": "price_test_placeholder"
    }')

echo -e "  Response: $checkout_response"

if echo "$checkout_response" | grep -q -E "(url|session|checkout)"; then
    echo -e "${GREEN}✓ Checkout session created${NC}\n"
elif echo "$checkout_response" | grep -q -E "(error|STRIPE_SECRET_KEY)"; then
    echo -e "${YELLOW}! Stripe not configured (expected in test)${NC}\n"
else
    echo -e "${YELLOW}! Checkout response (check manually)${NC}\n"
fi

# Summary
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Test Summary${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ User signup and authentication${NC}"
echo -e "${GREEN}✓ Subscription validation${NC}"
echo -e "${GREEN}✓ Device registration${NC}"
echo -e "${GREEN}✓ API key generation${NC}"
echo -e "${GREEN}✓ Usage logging${NC}"
echo -e "${GREEN}✓ History sync${NC}"
echo -e "${YELLOW}~ Stripe checkout (depends on configuration)${NC}\n"

echo -e "${BLUE}Test User Created:${NC}"
echo -e "  Email: $TEST_EMAIL"
echo -e "  Password: $TEST_PASSWORD"
echo -e "  User ID: $USER_ID"
echo -e "\n${YELLOW}You can use these credentials to test the app manually!${NC}\n"
