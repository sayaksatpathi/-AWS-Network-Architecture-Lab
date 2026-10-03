locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ── VPC ───────────────────────────────────────────────────────────────────────
module "vpc" {
  source = "../../modules/vpc"

  project_name            = local.name_prefix
  vpc_cidr                = var.vpc_cidr
  enable_flow_logs        = var.enable_flow_logs
  flow_log_retention_days = var.flow_log_retention_days
}

# ── Subnets ───────────────────────────────────────────────────────────────────
module "subnets" {
  source = "../../modules/subnets"

  project_name             = local.name_prefix
  vpc_id                   = module.vpc.vpc_id
  aws_region               = var.aws_region
  availability_zones       = var.availability_zones
  public_subnet_cidrs      = var.public_subnet_cidrs
  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  private_db_subnet_cidrs  = var.private_db_subnet_cidrs
}

# ── Route Tables + NAT Gateway ─────────────────────────────────────────────────
module "routes" {
  source = "../../modules/routes"

  project_name           = local.name_prefix
  vpc_id                 = module.vpc.vpc_id
  igw_id                 = module.vpc.igw_id
  public_subnet_ids      = module.subnets.public_subnet_ids
  private_app_subnet_ids = module.subnets.private_app_subnet_ids
  private_db_subnet_ids  = module.subnets.private_db_subnet_ids
}

# ── Security Groups + NACLs ────────────────────────────────────────────────────
module "security_groups" {
  source = "../../modules/security-groups"

  project_name           = local.name_prefix
  vpc_id                 = module.vpc.vpc_id
  vpc_cidr               = var.vpc_cidr
  app_port               = var.app_port
  db_port                = var.db_engine == "postgres" ? 5432 : 3306
  public_subnet_ids      = module.subnets.public_subnet_ids
  private_app_subnet_ids = module.subnets.private_app_subnet_ids
  private_db_subnet_ids  = module.subnets.private_db_subnet_ids
}

# ── Application Load Balancer ──────────────────────────────────────────────────
module "alb" {
  source = "../../modules/alb"

  project_name               = local.name_prefix
  vpc_id                     = module.vpc.vpc_id
  alb_sg_id                  = module.security_groups.alb_sg_id
  public_subnet_ids          = module.subnets.public_subnet_ids
  app_port                   = var.app_port
  enable_deletion_protection = var.alb_deletion_protection
  create_tls                 = var.create_tls
  acm_certificate_arn        = module.dns.certificate_arn
}

# ── DNS / TLS ──────────────────────────────────────────────────────────────────
module "dns" {
  source = "../../modules/dns"

  project_name = local.name_prefix
  create_dns   = var.create_dns
  create_tls   = var.create_tls
  domain_name  = var.domain_name
  subdomain    = var.subdomain
  alb_dns_name = module.alb.alb_dns_name
  alb_zone_id  = module.alb.alb_zone_id
}

# ── RDS ────────────────────────────────────────────────────────────────────────
module "rds" {
  source = "../../modules/rds"

  project_name          = local.name_prefix
  private_db_subnet_ids = module.subnets.private_db_subnet_ids
  db_sg_id              = module.security_groups.db_sg_id
  db_engine             = var.db_engine
  db_engine_version     = var.db_engine_version
  db_instance_class     = var.db_instance_class
  db_name               = var.db_name
  db_username           = var.db_username
  allocated_storage     = var.db_allocated_storage
  multi_az              = var.db_multi_az
}

# ── Application Tier ───────────────────────────────────────────────────────────
module "application" {
  source = "../../modules/application"

  project_name           = local.name_prefix
  aws_region             = var.aws_region
  private_app_subnet_ids = module.subnets.private_app_subnet_ids
  app_sg_id              = module.security_groups.app_sg_id
  target_group_arn       = module.alb.target_group_arn
  instance_type          = var.app_instance_type
  instance_count         = var.app_instance_count
  app_port               = var.app_port
  key_pair_name          = var.key_pair_name
  db_endpoint            = module.rds.db_address
  db_name                = var.db_name
  db_username            = var.db_username
  db_secret_arn          = module.rds.db_secret_arn
}
