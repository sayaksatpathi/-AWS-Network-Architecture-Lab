variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "aws-network-lab"
}

variable "environment" {
  description = "Environment label (dev / staging / prod)"
  type        = string
  default     = "dev"
}

# ── VPC ───────────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Two AZ suffixes to use (e.g. [\"a\",\"b\"])"
  type        = list(string)
  default     = ["a", "b"]
}

# ── Subnets ───────────────────────────────────────────────────────────────────

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "CIDR blocks for private application subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "private_db_subnet_cidrs" {
  description = "CIDR blocks for private database subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

# ── Application ───────────────────────────────────────────────────────────────

variable "app_instance_type" {
  description = "EC2 instance type for application tier"
  type        = string
  default     = "t3.micro"
}

variable "app_instance_count" {
  description = "Number of application instances (minimum 2 for multi-AZ)"
  type        = number
  default     = 2
}

variable "app_port" {
  description = "Port the application listens on"
  type        = number
  default     = 8080
}

variable "key_pair_name" {
  description = "EC2 key pair name for SSH access (optional – leave empty to disable)"
  type        = string
  default     = ""
}

# ── RDS ───────────────────────────────────────────────────────────────────────

variable "db_engine" {
  description = "RDS database engine"
  type        = string
  default     = "postgres"
}

variable "db_engine_version" {
  description = "RDS engine version"
  type        = string
  default     = "15.4"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "dbadmin"
  sensitive   = true
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
}

variable "db_multi_az" {
  description = "Enable Multi-AZ deployment for RDS"
  type        = bool
  default     = false
}

# ── DNS / TLS ─────────────────────────────────────────────────────────────────

variable "domain_name" {
  description = "Route 53 hosted zone domain name (leave empty to skip DNS/TLS)"
  type        = string
  default     = ""
}

variable "subdomain" {
  description = "Subdomain to create (e.g. 'app' creates app.<domain_name>)"
  type        = string
  default     = "app"
}

variable "create_dns" {
  description = "Whether to create Route 53 DNS records (requires domain_name)"
  type        = bool
  default     = false
}

variable "create_tls" {
  description = "Whether to create ACM certificate and HTTPS listener (requires domain_name)"
  type        = bool
  default     = false
}

# ── ALB ───────────────────────────────────────────────────────────────────────

variable "alb_deletion_protection" {
  description = "Enable deletion protection on the ALB"
  type        = bool
  default     = false
}

# ── Flow Logs ─────────────────────────────────────────────────────────────────

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs to CloudWatch"
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "CloudWatch log retention period for VPC flow logs"
  type        = number
  default     = 7
}
