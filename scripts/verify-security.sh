#!/usr/bin/env bash
# ── verify-security.sh ─────────────────────────────────────────────────────────
# Verifies that the security model is correctly enforced:
#   - RDS is not publicly accessible
#   - App instances have no public IPs
#   - DB SG has no 0.0.0.0/0 ingress
#   - Private subnets are not associated with a public route table
set -euo pipefail

REGION="${AWS_REGION:-ap-south-1}"
ENV="${ENV:-dev}"
PROJECT="aws-network-lab-${ENV}"
PASS=0; FAIL=0

green() { echo -e "\033[32m  ✓ $*\033[0m"; PASS=$((PASS+1)); }
red()   { echo -e "\033[31m  ✗ $*\033[0m"; FAIL=$((FAIL+1)); }

echo ""
echo "Security Verification: $PROJECT"
echo "═══════════════════════════════════════"
echo ""

VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${PROJECT}-vpc" \
  --query "Vpcs[0].VpcId" --output text --region "$REGION")

# 1. RDS not publicly accessible
RDS_PUBLIC=$(aws rds describe-db-instances \
  --query "DBInstances[?contains(DBInstanceIdentifier,'${PROJECT}')].PubliclyAccessible" \
  --output text --region "$REGION" 2>/dev/null)
[[ "$RDS_PUBLIC" == "false" ]] && green "RDS is NOT publicly accessible" || red "RDS IS publicly accessible — FIX IMMEDIATELY"

# 2. App instances have no public IPs
APP_PUBLIC_IPS=$(aws ec2 describe-instances \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=${PROJECT}-app*" "Name=instance-state-name,Values=running" \
  --query "Reservations[*].Instances[?PublicIpAddress!=null].PublicIpAddress" \
  --output text --region "$REGION" 2>/dev/null)
[[ -z "$APP_PUBLIC_IPS" ]] && green "App instances have NO public IPs" || red "App instances have public IPs: $APP_PUBLIC_IPS — FIX IMMEDIATELY"

# 3. DB SG has no open ingress
DB_SG=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=${PROJECT}-db-sg" \
  --query "SecurityGroups[0].GroupId" --output text --region "$REGION")
DB_OPEN=$(aws ec2 describe-security-groups --group-ids "$DB_SG" \
  --query "SecurityGroups[0].IpPermissions[?IpRanges[?CidrIp=='0.0.0.0/0']]" \
  --output text --region "$REGION" 2>/dev/null)
[[ -z "$DB_OPEN" ]] && green "DB SG has no 0.0.0.0/0 ingress" || red "DB SG has open ingress — FIX IMMEDIATELY"

# 4. Private subnets use correct route tables
IGW_ID=$(aws ec2 describe-internet-gateways \
  --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
  --query "InternetGateways[0].InternetGatewayId" --output text --region "$REGION")

PRIV_APP_SUBNETS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Tier,Values=private-app" \
  --query "Subnets[*].SubnetId" --output text --region "$REGION")

for SUBNET in $PRIV_APP_SUBNETS; do
  RT=$(aws ec2 describe-route-tables \
    --filters "Name=association.subnet-id,Values=${SUBNET}" \
    --query "RouteTables[0].RouteTableId" --output text --region "$REGION")
  HAS_IGW=$(aws ec2 describe-route-tables --route-table-ids "$RT" \
    --query "RouteTables[0].Routes[?GatewayId=='${IGW_ID}']" \
    --output text --region "$REGION" 2>/dev/null)
  [[ -z "$HAS_IGW" ]] && green "Private app subnet $SUBNET has NO route to IGW" || red "Private app subnet $SUBNET has route to IGW — subnet is accidentally public"
done

echo ""
echo "═══════════════════════════════════"
echo "PASS: $PASS | FAIL: $FAIL"
[[ $FAIL -gt 0 ]] && exit 1 || exit 0
