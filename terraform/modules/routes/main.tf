# ── Elastic IP for NAT Gateway ────────────────────────────────────────────────
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

# ── NAT Gateway ───────────────────────────────────────────────────────────────
# Placed in the first public subnet.
# Provides outbound internet connectivity for private subnets WITHOUT
# assigning public IPs to private resources. The source IP seen by the
# internet is the NAT Gateway's Elastic IP, not the private instance's IP.
resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = var.public_subnet_ids[0]

  tags = {
    Name = "${var.project_name}-nat-gw"
  }

  depends_on = [var.igw_id]
}

# ── Public Route Table ────────────────────────────────────────────────────────
# Routes:
#   10.0.0.0/16 → local  (VPC-internal, implicit)
#   0.0.0.0/0   → IGW    (internet-bound traffic)
resource "aws_route_table" "public" {
  vpc_id = var.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = var.igw_id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
    Tier = "public"
  }
}

# ── Private Application Route Table ──────────────────────────────────────────
# Routes:
#   10.0.0.0/16 → local         (VPC-internal, implicit)
#   0.0.0.0/0   → NAT Gateway   (internet-bound egress only)
# Note: traffic to the database stays on the local route; it never leaves the VPC.
resource "aws_route_table" "private_app" {
  vpc_id = var.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name = "${var.project_name}-private-app-rt"
    Tier = "private-app"
  }
}

# ── Private Database Route Table ──────────────────────────────────────────────
# Routes:
#   10.0.0.0/16 → local   (VPC-internal only)
# NO internet route. The database has zero outbound internet path.
resource "aws_route_table" "private_db" {
  vpc_id = var.vpc_id

  tags = {
    Name = "${var.project_name}-private-db-rt"
    Tier = "private-db"
  }
}

# ── Route Table Associations ──────────────────────────────────────────────────
# Each subnet must be explicitly associated with its intended route table.
# Subnets without an explicit association use the VPC's main route table.
# We never rely on that default — every subnet is explicitly associated.

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_ids)
  subnet_id      = var.public_subnet_ids[count.index]
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_app" {
  count          = length(var.private_app_subnet_ids)
  subnet_id      = var.private_app_subnet_ids[count.index]
  route_table_id = aws_route_table.private_app.id
}

resource "aws_route_table_association" "private_db" {
  count          = length(var.private_db_subnet_ids)
  subnet_id      = var.private_db_subnet_ids[count.index]
  route_table_id = aws_route_table.private_db.id
}
