data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  az_names = [
    for suffix in var.availability_zones :
    "${var.aws_region}${suffix}"
  ]
}

# ── Public Subnets ────────────────────────────────────────────────────────────
# Public subnets have map_public_ip_on_launch = true.
# The ROUTE TABLE (not the subnet itself) is what makes a subnet "public"
# by containing 0.0.0.0/0 → IGW. Resources in public subnets can receive
# inbound internet connections when their security groups permit it.
resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = var.vpc_id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = local.az_names[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  }
}

# ── Private Application Subnets ───────────────────────────────────────────────
# App instances live here. They have NO public IPs.
# Inbound traffic arrives only from the ALB (via the app security group).
# Outbound internet traffic routes via NAT Gateway in the public subnet.
resource "aws_subnet" "private_app" {
  count             = length(var.private_app_subnet_cidrs)
  vpc_id            = var.vpc_id
  cidr_block        = var.private_app_subnet_cidrs[count.index]
  availability_zone = local.az_names[count.index]

  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-private-app-${var.availability_zones[count.index]}"
    Tier = "private-app"
  }
}

# ── Private Database Subnets ──────────────────────────────────────────────────
# RDS lives here. No internet routing whatsoever.
# Traffic flows only from the application tier via VPC-local routing.
resource "aws_subnet" "private_db" {
  count             = length(var.private_db_subnet_cidrs)
  vpc_id            = var.vpc_id
  cidr_block        = var.private_db_subnet_cidrs[count.index]
  availability_zone = local.az_names[count.index]

  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-private-db-${var.availability_zones[count.index]}"
    Tier = "private-db"
  }
}
