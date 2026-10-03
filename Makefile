REGION      ?= ap-south-1
ENV         ?= dev
TF_DIR      := terraform/environments/$(ENV)
PROJECT     := aws-network-lab-$(ENV)

export AWS_REGION   := $(REGION)
export ENV          := $(ENV)
export PROJECT      := $(PROJECT)

.PHONY: help fmt validate lint plan apply verify \
        test-dns test-ingress test-egress test-security \
        troubleshoot-sg troubleshoot-route troubleshoot-nat \
        destroy clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2}'

# ── Terraform ─────────────────────────────────────────────────────────────────

fmt: ## Format all Terraform code
	terraform -chdir=terraform fmt -recursive

validate: ## Validate Terraform configuration
	terraform -chdir=$(TF_DIR) init -backend=false && \
	terraform -chdir=$(TF_DIR) validate

lint: ## Run TFLint
	tflint --chdir=$(TF_DIR) --format=compact

plan: ## Run terraform plan (requires AWS credentials)
	terraform -chdir=$(TF_DIR) plan

apply: ## Deploy all infrastructure
	terraform -chdir=$(TF_DIR) apply

# ── Tests ──────────────────────────────────────────────────────────────────────

verify: ## Validate deployed network topology
	bash scripts/validate-network.sh

test-dns: ## Test DNS resolution
	bash scripts/test-dns.sh

test-ingress: ## Test public ingress through ALB
	bash scripts/test-ingress.sh

test-egress: ## Test private egress through NAT Gateway
	bash scripts/test-private-egress.sh

test-security: ## Verify security model (no public RDS, no public app IPs)
	bash scripts/verify-security.sh

test-all: verify test-ingress test-egress test-security ## Run all tests

# ── Troubleshooting scenarios ──────────────────────────────────────────────────

troubleshoot-sg: ## Simulate SG failure: Remove ALB→App ingress rule
	@echo "⚠  Simulating security group failure..."
	@echo "   This removes the App SG ingress from ALB SG, causing targets to become unhealthy."
	@echo "   Run: make verify to observe the failure, then make fix-sg to restore."

fix-sg: ## Restore SG after troubleshoot-sg
	@echo "Restoring security group rules via terraform apply..."
	terraform -chdir=$(TF_DIR) apply -target=module.security_groups

troubleshoot-route: ## Simulate route failure: Remove NAT route from private RT
	@echo "⚠  Simulating route table failure..."
	@echo "   Manually remove the 0.0.0.0/0 → NAT route from the private app route table."
	@echo "   Then run: make test-egress to observe the failure."

fix-route: ## Restore route table after troubleshoot-route
	terraform -chdir=$(TF_DIR) apply -target=module.routes

troubleshoot-nat: ## Describe NAT Gateway failure scenario
	@echo "NAT Gateway failure scenario documented in docs/troubleshooting.md"
	@echo "To simulate: delete the NAT Gateway manually in AWS Console"
	@echo "Observe: test-egress fails, but test-ingress still passes (ALB path unaffected)"

# ── Cleanup ────────────────────────────────────────────────────────────────────

destroy: ## Destroy all infrastructure (stops billing)
	bash scripts/cleanup.sh

clean: ## Remove local Terraform cache
	find terraform -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
	find terraform -name ".terraform.lock.hcl" -delete 2>/dev/null || true
