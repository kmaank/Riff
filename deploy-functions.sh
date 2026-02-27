#!/bin/bash
set -e

# Supabase configuration
export SUPABASE_ACCESS_TOKEN="sbp_58516a505f403e1414697dd6ae6f8b0907432912"
PROJECT_REF="yrsviodciuepunofxoja"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Deploying Riff Edge Functions to Supabase${NC}"
echo "================================================"

# List of functions to deploy
FUNCTIONS=(
  "validate-subscription"
  "log-usage"
  "register-device"
  "sync-history"
  "get-api-key"
  "proxy-transcribe"
  "proxy-refine"
  "create-checkout"
  "create-portal"
  "stripe-webhook"
)

# Deploy each function
SUCCESS_COUNT=0
FAIL_COUNT=0

for func in "${FUNCTIONS[@]}"; do
  echo ""
  echo -e "${BLUE}📦 Deploying: ${func}${NC}"

  if npx supabase functions deploy "$func" --project-ref "$PROJECT_REF" --no-verify-jwt 2>&1; then
    echo -e "${GREEN}✅ Successfully deployed: ${func}${NC}"
    ((SUCCESS_COUNT++))
  else
    echo -e "${RED}❌ Failed to deploy: ${func}${NC}"
    ((FAIL_COUNT++))
  fi
done

echo ""
echo "================================================"
echo -e "${BLUE}📊 Deployment Summary${NC}"
echo "================================================"
echo -e "${GREEN}✅ Successful: ${SUCCESS_COUNT}${NC}"
echo -e "${RED}❌ Failed: ${FAIL_COUNT}${NC}"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
  echo -e "${GREEN}🎉 All functions deployed successfully!${NC}"
  exit 0
else
  echo -e "${RED}⚠️  Some functions failed to deploy. Check errors above.${NC}"
  exit 1
fi
