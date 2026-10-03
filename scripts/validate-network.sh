#!/usr/bin/env bash
# ── validate-network.sh ────────────────────────────────────────────────────────
# Validates the deployed network topology using AWS CLI.
# Run after terraform apply. Requires AWS CLI configured.
# Usage: ./scripts/validate-network.sh [--region ap-south-1] [--env dev]
set -euo pipefail

REGION="${AWS_REGION:-ap-south-1}"
ENV="${ENV:-dev}"
PROJECT="aws-network-lab-${ENV}"
PASS=0
FAIL=0

red()    { echo -e "\033[31m$*\033[0m"; }
green()  { echo -e "\033[32m$*\033[0m"; }
yellow() { echo -e "\033[33m$*\033[0m"; }
info()   { echo -e "\033[36m$*\033[0m"; }

check() {
  local desc="$1"
  local result="$2"
  if [[ -n "$result" ]]; then
    green "  ✓ $desc"
    PASS=$((PASS+1))
  else
    red "  ✗ $desc"
    FAIL=$((FAIL+1))
  fi
}

echo ""
info "═══════════════════════════════════════════════════"
info "  AWS Network Lab — Network Validation"
info "  Region: $REGION | Project: $PROJECT"
info "═══════════════════════════════════════════════════"
echo ""

# ── 1. VPC ─────────────────────────────────────────────────────────────────────
echo "1. VPC"
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${PROJECT}-vpc" \
  --query "Vpcs[0].VpcId" --output text --region "$REGION" 2>/dev/null)
check "VPC exists: $VPC_ID" "$VPC_ID"

VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" \
  --query "Vpcs[0].CidrBlock" --output text --region "$REGION" 2>/dev/null)
check "VPC CIDR set: $VPC_CIDR" "$VPC_CIDR"

DNS_SUPPORT=$(aws ec2 describe-vpc-attribute --vpc-id "$VPC_ID" \
  --attribute enableDnsSupport \
  --query "EnableDnsSupport.Value" --output text --region "$REGION" 2>/dev/null)
[[ "$DNS_SUPPORT" == "true" ]] && DNS_OK="yes" || DNS_OK=""
check "VPC DNS support enabled" "$DNS_OK"

# ── 2. Subnets ─────────────────────────────────────────────────────────────────
echo ""
echo "2. Subnets"

PUB_SUBNETS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Tier,Values=public" \
  --query "Subnets[*].SubnetId" --output text --region "$REGION")
check "Public subnets exist" "$PUB_SUBNETS"

PRIV_APP_SUBNETS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Tier,Values=private-app" \
  --query "Subnets[*].SubnetId" --output text --region "$REGION")
check "Private app subnets exist" "$PRIV_APP_SUBNETS"

PRIV_DB_SUBNETS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Tier,Values=private-db" \
  --query "Subnets[*].SubnetId" --output text --region "$REGION")
check "Private DB subnets exist" "$PRIV_DB_SUBNETS"

# Verify NO public IPs auto-assigned for private subnets
PRIV_APP_PUBLIC_IP=$(aws ec2 describe-subnets --subnet-ids $PRIV_APP_SUBNETS \
  --query "Subnets[?MapPublicIpOnLaunch==\`true\`].SubnetId" \
  --output text --region "$REGION" 2>/dev/null)
[[ -z "$PRIV_APP_PUBLIC_IP" ]] && NO_PUBLIC_IP="yes" || NO_PUBLIC_IP=""
check "Private app subnets do NOT auto-assign public IPs" "$NO_PUBLIC_IP"

# ── 3. Internet Gateway ─────────────────────────────────────────────────────────
echo ""
echo "3. Internet Gateway"
IGW_ID=$(aws ec2 describe-internet-gateways \
  --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
  --query "InternetGateways[0].InternetGatewayId" --output text --region "$REGION")
check "Internet Gateway exists: $IGW_ID" "$IGW_ID"

# ── 4. NAT Gateway ─────────────────────────────────────────────────────────────
echo ""
echo "4. NAT Gateway"
NAT_GW=$(aws ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values=${VPC_ID}" "Name=state,Values=available" \
  --query "NatGateways[0].NatGatewayId" --output text --region "$REGION")
check "NAT Gateway exists and available: $NAT_GW" "$NAT_GW"

NAT_EIP=$(aws ec2 describe-nat-gateways \
  --nat-gateway-ids "$NAT_GW" \
  --query "NatGateways[0].NatGatewayAddresses[0].PublicIp" --output text --region "$REGION" 2>/dev/null)
check "NAT Gateway has Elastic IP: $NAT_EIP" "$NAT_EIP"

# ── 5. Route Tables ─────────────────────────────────────────────────────────────
echo ""
echo "5. Route Tables"
PUB_RT=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Tier,Values=public" \
  --query "RouteTables[0].RouteTableId" --output text --region "$REGION")
check "Public route table exists: $PUB_RT" "$PUB_RT"

PUB_IGW_ROUTE=$(aws ec2 describe-route-tables --route-table-ids "$PUB_RT" \
  --query "RouteTables[0].Routes[?GatewayId=='${IGW_ID}'].DestinationCidrBlock" \
  --output text --region "$REGION" 2>/dev/null)
check "Public RT has 0.0.0.0/0 → IGW" "$PUB_IGW_ROUTE"

PRIV_RT=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Tier,Values=private-app" \
  --query "RouteTables[0].RouteTableId" --output text --region "$REGION")
check "Private app route table exists: $PRIV_RT" "$PRIV_RT"

PRIV_NAT_ROUTE=$(aws ec2 describe-route-tables --route-table-ids "$PRIV_RT" \
  --query "RouteTables[0].Routes[?NatGatewayId=='${NAT_GW}'].DestinationCidrBlock" \
  --output text --region "$REGION" 2>/dev/null)
check "Private app RT has 0.0.0.0/0 → NAT" "$PRIV_NAT_ROUTE"

DB_RT=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Tier,Values=private-db" \
  --query "RouteTables[0].RouteTableId" --output text --region "$REGION")
check "Private DB route table exists: $DB_RT" "$DB_RT"

DB_NO_IGW=$(aws ec2 describe-route-tables --route-table-ids "$DB_RT" \
  --query "RouteTables[0].Routes[?GatewayId=='${IGW_ID}']" \
  --output text --region "$REGION" 2>/dev/null)
[[ -z "$DB_NO_IGW" ]] && DB_SAFE="yes" || DB_SAFE=""
check "DB route table has NO route to IGW (database is isolated)" "$DB_SAFE"

# ── 6. ALB ─────────────────────────────────────────────────────────────────────
echo ""
echo "6. Application Load Balancer"
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(LoadBalancerName, '${PROJECT}')].DNSName" \
  --output text --region "$REGION" 2>/dev/null)
check "ALB exists: $ALB_DNS" "$ALB_DNS"

ALB_SCHEME=$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(LoadBalancerName, '${PROJECT}')].Scheme" \
  --output text --region "$REGION" 2>/dev/null)
[[ "$ALB_SCHEME" == "internet-facing" ]] && ALB_INTERNET="yes" || ALB_INTERNET=""
check "ALB is internet-facing" "$ALB_INTERNET"

# ── 7. Security Groups ──────────────────────────────────────────────────────────
echo ""
echo "7. Security Groups"
ALB_SG=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=${PROJECT}-alb-sg" \
  --query "SecurityGroups[0].GroupId" --output text --region "$REGION")
check "ALB security group exists: $ALB_SG" "$ALB_SG"

APP_SG=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=${PROJECT}-app-sg" \
  --query "SecurityGroups[0].GroupId" --output text --region "$REGION")
check "App security group exists: $APP_SG" "$APP_SG"

DB_SG=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=${PROJECT}-db-sg" \
  --query "SecurityGroups[0].GroupId" --output text --region "$REGION")
check "DB security group exists: $DB_SG" "$DB_SG"

# DB SG must NOT have 0.0.0.0/0 ingress
DB_OPEN_INGRESS=$(aws ec2 describe-security-groups --group-ids "$DB_SG" \
  --query "SecurityGroups[0].IpPermissions[?IpRanges[?CidrIp=='0.0.0.0/0']]" \
  --output text --region "$REGION" 2>/dev/null)
[[ -z "$DB_OPEN_INGRESS" ]] && DB_SG_SAFE="yes" || DB_SG_SAFE=""
check "DB SG has NO 0.0.0.0/0 ingress (database is private)" "$DB_SG_SAFE"

# ── 8. RDS ─────────────────────────────────────────────────────────────────────
echo ""
echo "8. RDS"
RDS_ENDPOINT=$(aws rds describe-db-instances \
  --query "DBInstances[?contains(DBInstanceIdentifier, '${PROJECT}')].Endpoint.Address" \
  --output text --region "$REGION" 2>/dev/null)
check "RDS instance exists: $RDS_ENDPOINT" "$RDS_ENDPOINT"

RDS_PUBLIC=$(aws rds describe-db-instances \
  --query "DBInstances[?contains(DBInstanceIdentifier, '${PROJECT}')].PubliclyAccessible" \
  --output text --region "$REGION" 2>/dev/null)
[[ "$RDS_PUBLIC" == "false" ]] && RDS_PRIVATE="yes" || RDS_PRIVATE=""
check "RDS is NOT publicly accessible" "$RDS_PRIVATE"

# ── Summary ─────────────────────────────────────────────────────────────────────
echo ""
info "═══════════════════════════════════════════════════"
green "  PASS: $PASS"
if [[ $FAIL -gt 0 ]]; then
  red "  FAIL: $FAIL"
fi
info "═══════════════════════════════════════════════════"
echo ""

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
