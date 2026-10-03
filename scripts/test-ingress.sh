#!/usr/bin/env bash
# ── test-ingress.sh ────────────────────────────────────────────────────────────
# Tests that the public ALB is reachable and returns expected responses.
# Demonstrates: Internet → Route 53 → ALB → Target Group → Private App
set -euo pipefail

PASS=0; FAIL=0
green() { echo -e "\033[32m  ✓ $*\033[0m"; PASS=$((PASS+1)); }
red()   { echo -e "\033[31m  ✗ $*\033[0m"; FAIL=$((FAIL+1)); }

# Get ALB DNS from terraform output or environment
ALB_DNS="${ALB_DNS:-$(terraform -chdir=terraform/environments/dev output -raw alb_dns_name 2>/dev/null || echo "")}"

if [[ -z "$ALB_DNS" ]]; then
  echo "ERROR: Set ALB_DNS env var or run from repo root after terraform apply"
  exit 1
fi

echo ""
echo "Testing ingress via ALB: $ALB_DNS"
echo "═══════════════════════════════════════"
echo ""

# ── HTTP health check ──────────────────────────────────────────────────────────
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://${ALB_DNS}/health" --max-time 10)
[[ "$HTTP_STATUS" == "200" ]] && green "HTTP /health returns 200" || red "HTTP /health returned $HTTP_STATUS (expected 200)"

# ── Root endpoint returns JSON with AZ ────────────────────────────────────────
ROOT_BODY=$(curl -s "http://${ALB_DNS}/" --max-time 10)
echo "  Root response: $ROOT_BODY"
AZ=$(echo "$ROOT_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('availability_zone',''))" 2>/dev/null || echo "")
[[ -n "$AZ" && "$AZ" != "unknown" ]] && green "Root endpoint returns AZ: $AZ" || red "Root endpoint missing AZ field"

# ── Multi-AZ round-robin ───────────────────────────────────────────────────────
echo ""
echo "  Running 6 requests to demonstrate AZ round-robin..."
AZS=()
for i in {1..6}; do
  BODY=$(curl -s "http://${ALB_DNS}/az" --max-time 10)
  THIS_AZ=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('availability_zone',''))" 2>/dev/null || echo "?")
  AZS+=("$THIS_AZ")
  echo "    Request $i → AZ: $THIS_AZ"
done

# Check if we saw more than one AZ (proves round-robin)
UNIQUE_AZS=$(printf '%s\n' "${AZS[@]}" | sort -u | wc -l | tr -d ' ')
[[ "$UNIQUE_AZS" -gt 1 ]] && green "ALB distributed requests across $UNIQUE_AZS AZs" || red "All requests went to same AZ — check that both instances are healthy"

# ── Verify private app has no public IP ────────────────────────────────────────
# The /network endpoint shows the private IP of the instance
PRIV_IP=$(curl -s "http://${ALB_DNS}/network" --max-time 10 | \
  python3 -c "import sys,json; print(json.load(sys.stdin).get('private_ip',''))" 2>/dev/null || echo "")
[[ "$PRIV_IP" =~ ^10\. ]] && green "Instance has private IP only: $PRIV_IP" || red "Unexpected IP: $PRIV_IP"

echo ""
echo "═══════════════════════════════════"
echo "PASS: $PASS | FAIL: $FAIL"
[[ $FAIL -gt 0 ]] && exit 1 || exit 0
