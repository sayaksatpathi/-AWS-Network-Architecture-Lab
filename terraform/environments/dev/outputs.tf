output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.vpc.vpc_cidr
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.subnets.public_subnet_ids
}

output "private_app_subnet_ids" {
  description = "Private application subnet IDs"
  value       = module.subnets.private_app_subnet_ids
}

output "private_db_subnet_ids" {
  description = "Private database subnet IDs"
  value       = module.subnets.private_db_subnet_ids
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer (use to test without a custom domain)"
  value       = module.alb.alb_dns_name
}

output "app_url" {
  description = "Application URL (custom domain or ALB DNS)"
  value       = var.create_dns ? "https://${module.dns.app_fqdn}" : "http://${module.alb.alb_dns_name}"
}

output "nat_gateway_ip" {
  description = "Elastic IP of the NAT Gateway (private instances egress from this IP)"
  value       = module.routes.nat_gateway_public_ip
}

output "app_instance_ids" {
  description = "EC2 instance IDs in the private application tier"
  value       = module.application.instance_ids
}

output "rds_endpoint" {
  description = "RDS endpoint (only reachable from the application tier)"
  value       = module.rds.db_endpoint
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret containing DB credentials"
  value       = module.rds.db_secret_arn
}

output "flow_log_group" {
  description = "CloudWatch Log Group for VPC flow logs"
  value       = module.vpc.flow_log_group_name
}
