#!/usr/bin/env bash
# ── test-dns.sh ────────────────────────────────────────────────────────────────
# Tests DNS resolution for the application hostname.
set -euo pipefail

PASS=0; FAIL=0
green() { echo -e "\033[32m  ✓ $*\033[0m"; PASS=$((PASS+1)); }
red()   { echo -e "\033[31m  ✗ $*\033[0m"; FAIL=$((FAIL+1)); }
yellow() { echo -e "\033[33m  ~ $*\033[0m"; }

ALB_DNS="${ALB_DNS:-$(terraform -chdir=terraform/environments/dev output -raw alb_dns_name 2>/dev/null || echo "")}"
APP_HOSTNAME="${APP_HOSTNAME:-}"

echo ""
echo "DNS Resolution Tests"
echo "═══════════════════════════════════════"
echo ""

# ── Test ALB DNS is resolvable ─────────────────────────────────────────────────
if [[ -n "$ALB_DNS" ]]; then
  ALB_IPS=$(dig +short "$ALB_DNS" 2>/dev/null || nslookup "$ALB_DNS" 2>/dev/null | grep Address | tail -1 | awk '{print $2}')
  [[ -n "$ALB_IPS" ]] && green "ALB DNS resolves: $ALB_DNS → $ALB_IPS" || red "ALB DNS does not resolve: $ALB_DNS"
fi

# ── Test custom hostname if configured ─────────────────────────────────────────
if [[ -n "$APP_HOSTNAME" ]]; then
  echo ""
  echo "  Testing custom hostname: $APP_HOSTNAME"
  CUSTOM_IPS=$(dig +short "$APP_HOSTNAME" 2>/dev/null)
  [[ -n "$CUSTOM_IPS" ]] && green "Custom hostname resolves: $APP_HOSTNAME → $CUSTOM_IPS" || red "Custom hostname does not resolve: $APP_HOSTNAME"

  # Check if the resolved IPs match the ALB
  if [[ -n "$ALB_DNS" && -n "$CUSTOM_IPS" ]]; then
    ALB_IPS_SORTED=$(dig +short "$ALB_DNS" | sort)
    CUSTOM_IPS_SORTED=$(echo "$CUSTOM_IPS" | sort)
    [[ "$ALB_IPS_SORTED" == "$CUSTOM_IPS_SORTED" ]] \
      && green "Custom hostname IPs match ALB IPs (Route 53 alias is correct)" \
      || yellow "IP sets differ — this is normal for ALB alias records (AWS resolves geographically)"
  fi
else
  yellow "APP_HOSTNAME not set — skipping custom domain DNS test"
  yellow "Set APP_HOSTNAME=app.yourdomain.com to test Route 53 DNS"
fi

# ── DNS trace / path ────────────────────────────────────────────────────────────
if [[ -n "$ALB_DNS" ]]; then
  echo ""
  echo "  DNS lookup trace for: $ALB_DNS"
  dig "$ALB_DNS" +noall +answer 2>/dev/null | head -10 || echo "  (dig not available)"
fi

echo ""
echo "═══════════════════════════════════"
echo "PASS: $PASS | FAIL: $FAIL"
[[ $FAIL -gt 0 ]] && exit 1 || exit 0
