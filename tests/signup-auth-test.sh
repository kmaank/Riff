#!/bin/bash
# Signup + email confirmation redirect test
# Verifies that signup includes emailRedirectTo so confirmation links open Riff.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Load from Riff config if available
CONFIG_PATH="$HOME/Library/Application Support/Riff/config.json"
if [ -f "$CONFIG_PATH" ] && command -v python3 >/dev/null 2>&1; then
    _vars=$(python3 -c "
import json,sys
with open(sys.argv[1]) as f: c=json.load(f)
a=c.get('auth',{})
u=a.get('supabase_url','')
k=a.get('supabase_anon_key','')
if u: print('SUPABASE_URL='+u)
if k: print('SUPABASE_ANON_KEY='+k)
" "$CONFIG_PATH" 2>/dev/null)
    [ -n "$_vars" ] && eval "$_vars"
fi

# Override with env vars
SUPABASE_URL="${SUPABASE_URL:-https://yrsviodciuepunofxoja.supabase.co}"
SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}"

if [ -z "$SUPABASE_ANON_KEY" ]; then
    echo -e "${RED}Error: SUPABASE_ANON_KEY not set. Set it or ensure config.json has auth.supabase_anon_key${NC}"
    exit 1
fi

# Use a valid-looking test domain (example.com often rejected by Supabase)
TEST_EMAIL="test-riff-$(date +%s)@mailinator.com"
TEST_PASSWORD="Test123!@#"

echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Riff Signup + Email Redirect Test${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "Supabase URL: $SUPABASE_URL"
echo -e "Test email: $TEST_EMAIL\n"

echo -e "${BLUE}[1] Signup with redirect_to=riff://auth/callback${NC}"
signup_response=$(curl -s -X POST \
    "$SUPABASE_URL/auth/v1/signup?redirect_to=$(python3 -c 'from urllib.parse import quote; print(quote("riff://auth/callback", safe=""))')" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
    -H "Content-Type: application/json" \
    -d "{
        \"email\": \"$TEST_EMAIL\",
        \"password\": \"$TEST_PASSWORD\"
    }")

# Check for success (either tokens or confirmation_required)
if echo "$signup_response" | grep -q '"id"'; then
    echo -e "${GREEN}✓ Signup request accepted${NC}"
    if echo "$signup_response" | grep -q '"access_token"'; then
        echo -e "  → Auto-confirmed (no email confirmation required)"
    else
        echo -e "  → Email confirmation required"
        echo -e "\n${BLUE}[2] Next steps to test full flow:${NC}"
        echo -e "  1. Check your inbox for $TEST_EMAIL"
        echo -e "  2. Click the 'Confirm your mail' link"
        echo -e "  3. It should open Riff (riff://auth/callback#access_token=...)"
        echo -e "  4. If it opens localhost:3000 instead, see docs/TROUBLESHOOTING_AUTH.md"
    fi
else
    echo -e "${RED}✗ Signup failed${NC}"
    echo "$signup_response" | head -20
    exit 1
fi
