variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "alb_sg_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "app_port" {
  type    = number
  default = 8080
}

variable "enable_deletion_protection" {
  type    = bool
  default = false
}

variable "create_tls" {
  type    = bool
  default = false
}

variable "acm_certificate_arn" {
  type    = string
  default = ""
}
