variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "app_port" {
  type    = number
  default = 8080
}

variable "db_port" {
  description = "Database port (5432 for PostgreSQL, 3306 for MySQL)"
  type        = number
  default     = 5432
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_app_subnet_ids" {
  type = list(string)
}

variable "private_db_subnet_ids" {
  type = list(string)
}
