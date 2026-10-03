variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "igw_id" {
  description = "Internet Gateway ID (used as depends_on and in public route)"
  type        = string
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
