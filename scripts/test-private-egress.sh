#!/usr/bin/env bash
# ── test-private-egress.sh ─────────────────────────────────────────────────────
# Tests that private application instances can reach the internet via NAT Gateway.
# Demonstrates: Private App → NAT Gateway → IGW → Internet
set -euo pipefail

PASS=0; FAIL=0
green() { echo -e "\033[32m  ✓ $*\033[0m"; PASS=$((PASS+1)); }
red()   { echo -e "\033[31m  ✗ $*\033[0m"; FAIL=$((FAIL+1)); }

ALB_DNS="${ALB_DNS:-$(terraform -chdir=terraform/environments/dev output -raw alb_dns_name 2>/dev/null || echo "")}"
NAT_IP="${NAT_IP:-$(terraform -chdir=terraform/environments/dev output -raw nat_gateway_ip 2>/dev/null || echo "")}"

if [[ -z "$ALB_DNS" ]]; then
  echo "ERROR: Set ALB_DNS (and optionally NAT_IP) env vars or run from repo root after terraform apply"
  exit 1
fi

echo ""
echo "Testing private egress via NAT Gateway"
echo "═══════════════════════════════════════"
echo ""

# ── Test NAT egress via /egress-check endpoint ─────────────────────────────────
EGRESS=$(curl -s "http://${ALB_DNS}/egress-check" --max-time 15)
echo "  Egress check response: $EGRESS"

PUBLIC_IP=$(echo "$EGRESS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('public_ip',''))" 2>/dev/null || echo "")
[[ -n "$PUBLIC_IP" ]] && green "Private instance can reach internet, public IP: $PUBLIC_IP" || red "Egress check failed — NAT route missing?"

if [[ -n "$NAT_IP" && -n "$PUBLIC_IP" ]]; then
  [[ "$PUBLIC_IP" == "$NAT_IP" ]] \
    && green "Egress IP matches NAT Gateway EIP ($NAT_IP) — confirming NAT path" \
    || red "Egress IP ($PUBLIC_IP) != NAT GW EIP ($NAT_IP) — unexpected routing"
fi

echo ""
echo "═══════════════════════════════════"
echo "PASS: $PASS | FAIL: $FAIL"
[[ $FAIL -gt 0 ]] && exit 1 || exit 0
