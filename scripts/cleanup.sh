#!/usr/bin/env bash
# ── cleanup.sh ─────────────────────────────────────────────────────────────────
# Destroys all resources created by terraform apply.
# Stops billing. Run when you're done with the lab.
set -euo pipefail

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  AWS Network Lab — CLEANUP                       ║"
echo "║  This will destroy ALL lab resources             ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "This will incur NO further charges after completion."
echo "Resources with costs: NAT Gateway, ALB, RDS, EC2, EIP, CloudWatch"
echo ""
read -p "Type 'destroy' to confirm: " CONFIRM
[[ "$CONFIRM" != "destroy" ]] && echo "Aborted." && exit 0

cd terraform/environments/dev
terraform destroy -auto-approve
echo ""
echo "All resources destroyed. Billing stopped."
