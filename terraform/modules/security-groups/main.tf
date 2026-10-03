# ── ALB Security Group ────────────────────────────────────────────────────────
# Allows HTTPS (443) and HTTP (80 → redirect) from anywhere.
# This is the only entry point from the public internet.
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Internet-facing ALB: allow HTTPS (443) and HTTP (80) from internet"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from internet (redirect to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound (to application tier)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

# ── Application Security Group ────────────────────────────────────────────────
# Only accepts traffic from the ALB security group.
# This is a security-group-to-security-group reference, which is more precise
# and maintainable than allowing the ALB's entire CIDR range.
resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Private app tier: allow app port from ALB SG only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Application port from ALB only"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound (for NAT egress and DB access)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-app-sg"
  }
}

# ── Database Security Group ───────────────────────────────────────────────────
# Only accepts connections from the application security group.
# No direct internet access is possible even if someone misroutes subnets.
resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "Private DB tier: allow DB port from app SG only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from app tier only"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    description = "Allow all outbound (e.g. for software updates via VPC endpoints)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-db-sg"
  }
}

# ── Network ACLs ──────────────────────────────────────────────────────────────
# NACLs are STATELESS — both inbound and outbound rules must be explicitly
# defined. For TCP connections this means allowing ephemeral ports (1024-65535)
# in the return direction. Security groups are STATEFUL (no return rule needed).

# Public Subnet NACL
resource "aws_network_acl" "public" {
  vpc_id     = var.vpc_id
  subnet_ids = var.public_subnet_ids

  # Inbound
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }
  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }
  # Ephemeral ports for return traffic from internet requests
  ingress {
    rule_no    = 900
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Outbound
  egress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }
  egress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }
  egress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = var.app_port
    to_port    = var.app_port
  }
  egress {
    rule_no    = 900
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  tags = {
    Name = "${var.project_name}-public-nacl"
  }
}

# Private App Subnet NACL
resource "aws_network_acl" "private_app" {
  vpc_id     = var.vpc_id
  subnet_ids = var.private_app_subnet_ids

  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = var.app_port
    to_port    = var.app_port
  }
  # Ephemeral ports for return traffic (NAT, HTTPS, DB responses)
  ingress {
    rule_no    = 900
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }
  egress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = var.db_port
    to_port    = var.db_port
  }
  egress {
    rule_no    = 900
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  tags = {
    Name = "${var.project_name}-private-app-nacl"
  }
}

# Private DB Subnet NACL
resource "aws_network_acl" "private_db" {
  vpc_id     = var.vpc_id
  subnet_ids = var.private_db_subnet_ids

  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = var.db_port
    to_port    = var.db_port
  }

  egress {
    rule_no    = 900
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  tags = {
    Name = "${var.project_name}-private-db-nacl"
  }
}
